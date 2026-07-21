-- Speed & accuracy drills — a Kumon-style track, deliberately separate from
-- the Leitner/MCQ engine above. Arithmetic is generated procedurally on the
-- client (drill_gen.dart mirrors content/tools/drill_gen.py); Postgres only
-- holds the level ladder (content) and the mastery gate (learner data), same
-- split as everywhere else in this schema.
--
-- Mastery = speed AND accuracy, gated here so the client cannot fake it
-- (ADR-008 applies just as much to a stopwatch as to a Leitner box):
--   1. A student's FIRST attempt at a level sets her own baseline time —
--      we never asserted a borrowed "standard completion time" because we
--      could not verify Kumon's own published figures.
--   2. She advances once she beats 85% of her baseline time with >=90%
--      accuracy, on TWO attempts in a row. Missing either resets the streak,
--      matching Kumon's "redo the whole sheet" rule.

create table if not exists drill_strands (
  id   serial primary key,
  code text unique not null,     -- 'addition' | 'subtraction' | 'mult_tables' | 'multiplication' | 'division'
  name text not null,
  seq  int not null
);

create table if not exists drill_levels (
  id        serial primary key,
  strand_id int  not null references drill_strands on delete cascade,
  code      text unique not null,   -- 'ADD-1'
  seq       int  not null,
  title     text not null,
  gen       jsonb not null          -- generation spec; mirrors content/data/drill_levels.json
);
create index if not exists drill_levels_strand_idx on drill_levels (strand_id, seq);

-- per-student progress on a level
create table if not exists drill_progress (
  user_id            uuid not null references auth.users on delete cascade,
  level_id           int  not null references drill_levels on delete cascade,
  status             text not null default 'locked' check (status in ('locked','active','mastered')),
  baseline_seconds   numeric,
  best_seconds       numeric,
  consecutive_passes int  not null default 0,
  attempts_count     int  not null default 0,
  mastered_at        timestamptz,
  updated_at         timestamptz not null default now(),
  primary key (user_id, level_id)
);

-- one row per worksheet attempt (the log a student sees as her progress graph)
create table if not exists drill_attempts (
  id            bigserial primary key,
  user_id       uuid not null references auth.users on delete cascade,
  level_id      int  not null references drill_levels on delete cascade,
  total         int  not null,
  correct       int  not null,
  seconds_taken numeric not null,
  passed        boolean not null,     -- did THIS attempt clear the mastery bar
  created_at    timestamptz not null default now()
);
create index if not exists drill_attempts_user_idx on drill_attempts (user_id, level_id, created_at desc);

-- ============================================================ the engine
-- Records a worksheet attempt and advances the mastery gate atomically.
-- The client reports total/correct/seconds_taken; it never decides pass/fail.
create or replace function record_drill_attempt(
  p_level_id      int,
  p_total         int,
  p_correct       int,
  p_seconds_taken numeric
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_user      uuid := auth.uid();
  v_strand    int;
  v_seq       int;
  v_baseline  numeric;
  v_target    numeric;
  v_accuracy  numeric;
  v_is_first  boolean;
  v_passed    boolean;
  v_streak    int;
  v_mastered  boolean := false;
  v_next_id   int;
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  select strand_id, seq into v_strand, v_seq from drill_levels where id = p_level_id;
  if v_strand is null then
    raise exception 'unknown level %', p_level_id;
  end if;

  insert into drill_progress (user_id, level_id, status)
  values (v_user, p_level_id, 'active')
  on conflict (user_id, level_id) do nothing;

  select baseline_seconds into v_baseline
    from drill_progress where user_id = v_user and level_id = p_level_id;

  v_accuracy := p_correct::numeric / greatest(p_total, 1);
  v_is_first := v_baseline is null;

  if v_is_first then
    -- first attempt: sets the baseline, never itself a pass (nothing to beat yet)
    v_baseline := p_seconds_taken;
    v_passed := false;
  else
    v_target := v_baseline * 0.85;
    v_passed := v_accuracy >= 0.90 and p_seconds_taken <= v_target;
  end if;

  insert into drill_attempts (user_id, level_id, total, correct, seconds_taken, passed)
  values (v_user, p_level_id, p_total, p_correct, p_seconds_taken, v_passed);

  update drill_progress
     set baseline_seconds   = v_baseline,
         best_seconds       = least(coalesce(best_seconds, p_seconds_taken), p_seconds_taken),
         attempts_count     = attempts_count + 1,
         consecutive_passes = case when v_is_first then 0
                                    when v_passed then consecutive_passes + 1
                                    else 0 end,
         updated_at         = now()
   where user_id = v_user and level_id = p_level_id
   returning consecutive_passes into v_streak;

  if v_streak >= 2 then
    v_mastered := true;
    update drill_progress
       set status = 'mastered', mastered_at = coalesce(mastered_at, now())
     where user_id = v_user and level_id = p_level_id;

    -- unlock the next level in the same strand
    select id into v_next_id from drill_levels
     where strand_id = v_strand and seq = v_seq + 1;
    if v_next_id is not null then
      insert into drill_progress (user_id, level_id, status)
      values (v_user, v_next_id, 'active')
      on conflict (user_id, level_id) do update
        set status = case when drill_progress.status = 'locked' then 'active'
                           else drill_progress.status end;
    end if;
  end if;

  return jsonb_build_object(
    'passed', coalesce(v_passed, false),
    'mastered', v_mastered,
    'is_first', v_is_first,
    'baseline_seconds', v_baseline,
    'target_seconds', v_baseline * 0.85,
    'consecutive_passes', v_streak
  );
end $$;

-- Diagnostic placement: mark everything up to (not including) p_level_code as
-- mastered-without-drilling ("she's already fluent here, skip it"), and make
-- that level active. Used once, right after the short placement quiz.
create or replace function set_drill_placement(
  p_strand     text,
  p_level_code text
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_user      uuid := auth.uid();
  v_strand_id int;
  v_seq       int;
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  select id into v_strand_id from drill_strands where code = p_strand;
  select seq into v_seq from drill_levels where code = p_level_code and strand_id = v_strand_id;
  if v_strand_id is null or v_seq is null then
    raise exception 'unknown strand/level %/%', p_strand, p_level_code;
  end if;

  insert into drill_progress (user_id, level_id, status, mastered_at)
  select v_user, id, case when seq < v_seq then 'mastered'
                          when seq = v_seq then 'active'
                          else 'locked' end,
         case when seq < v_seq then now() else null end
    from drill_levels where strand_id = v_strand_id
  on conflict (user_id, level_id) do update
    set status = excluded.status, mastered_at = excluded.mastered_at;
end $$;

-- ============================================================ RLS
alter table drill_strands  enable row level security;
alter table drill_levels   enable row level security;
alter table drill_progress enable row level security;
alter table drill_attempts enable row level security;

drop policy if exists content_read_drill_strands on drill_strands;
drop policy if exists content_read_drill_levels  on drill_levels;
create policy content_read_drill_strands on drill_strands for select to authenticated using (true);
create policy content_read_drill_levels  on drill_levels  for select to authenticated using (true);

drop policy if exists own_drill_progress on drill_progress;
create policy own_drill_progress on drill_progress for select to authenticated
  using (user_id = auth.uid());

drop policy if exists own_drill_attempts on drill_attempts;
create policy own_drill_attempts on drill_attempts for select to authenticated
  using (user_id = auth.uid());
-- no INSERT policy on either — both are written only through the two
-- functions above, same discipline as attempts/leitner_state.

grant select on drill_strands, drill_levels, drill_progress, drill_attempts to authenticated;
grant execute on function record_drill_attempt(int, int, int, numeric) to authenticated;
grant execute on function set_drill_placement(text, text) to authenticated;
