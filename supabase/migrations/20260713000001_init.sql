-- Laya MVP schema
-- Content (chapters/skills/questions/solutions/concepts) is read-only reference data.
-- Learner data (attempts/leitner/mastery) is private to each user, enforced by RLS.
--
-- ADR-008: deterministic code owns correctness. Scoring, the Leitner schedule and
-- mastery are computed HERE, in the database — never by the AI, and never by the client.

-- ============================================================ profiles
create table if not exists profiles (
  id            uuid primary key references auth.users on delete cascade,
  display_name  text not null default 'Student',
  created_at    timestamptz not null default now()
);

-- a row in profiles appears automatically when someone signs up
create or replace function handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name', 'Student'));
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- ============================================================ content
create table if not exists chapters (
  id      serial primary key,
  code    text unique not null,          -- 'ch1'
  number  int  not null,
  title   text not null,                 -- 'A Square and A Cube'
  book    text not null
);

-- tier is how often the skill appeared in the 17 real past papers.
-- '***' = 7+ exams, '**' = 4-6, '*' = 2-3. Counted, not guessed — it drives
-- both the study-priority display and the adaptive weighting.
create table if not exists skills (
  id             int primary key,
  chapter_id     int not null references chapters on delete cascade,
  name           text not null,
  exams_seen_in  int  not null,
  total_exams    int  not null,
  tier           text not null check (tier in ('***','**','*','-'))
);

create table if not exists questions (
  id              serial primary key,
  code            text unique not null,   -- 'ch1-q001'
  chapter_id      int  not null references chapters on delete cascade,
  skill_id        int  not null references skills   on delete cascade,
  source_exam     text not null,          -- '2025-26 Half Yearly'
  marks           int  not null check (marks between 1 and 4),
  difficulty      text not null check (difficulty in ('easy','medium','hard','challenge')),
  timer_seconds   int  not null,          -- derived from marks
  type            text not null check (type in ('mcq','short','long')),
  stem_latex      text not null,
  options_latex   jsonb not null default '[]'::jsonb,
  correct_option  int,                    -- index into options_latex; null unless mcq
  answer_latex    text not null,
  constraint mcq_has_options check (
    (type = 'mcq' and correct_option is not null and jsonb_array_length(options_latex) = 4)
    or (type <> 'mcq' and correct_option is null)
  )
);
create index if not exists questions_chapter_idx on questions (chapter_id);
create index if not exists questions_skill_idx   on questions (skill_id);

create table if not exists solution_steps (
  question_id  int  not null references questions on delete cascade,
  step_no      int  not null,
  text_latex   text not null,
  primary key (question_id, step_no)
);

create table if not exists concept_sections (
  id          serial primary key,
  chapter_id  int  not null references chapters on delete cascade,
  idx         int  not null,
  title       text not null,
  tier        text not null,
  why         text not null default '',
  body        jsonb not null,             -- [{kind:'p'|'eg'|'key'|'warn'|'tbl'|'check'|'real', ...}]
  unique (chapter_id, idx)
);

-- ============================================================ learner data
create table if not exists attempts (
  id            bigserial primary key,
  user_id       uuid not null references auth.users on delete cascade,
  question_id   int  not null references questions  on delete cascade,
  mode          text not null check (mode in ('learn','test')),
  is_correct    boolean not null,
  answer_given  text,
  seconds_taken int,
  timed_out     boolean not null default false,
  created_at    timestamptz not null default now()
);
create index if not exists attempts_user_idx on attempts (user_id, created_at desc);

-- Leitner: box 1..5, due after 1/2/4/8/16 days. Correct promotes one box;
-- wrong drops straight back to box 1 (ADR-009).
create table if not exists leitner_state (
  user_id      uuid not null references auth.users on delete cascade,
  question_id  int  not null references questions  on delete cascade,
  box          int  not null default 1 check (box between 1 and 5),
  due_at       date not null default current_date,
  last_seen_at timestamptz,
  primary key (user_id, question_id)
);
create index if not exists leitner_due_idx on leitner_state (user_id, due_at);

create table if not exists skill_mastery (
  user_id     uuid not null references auth.users on delete cascade,
  skill_id    int  not null references skills     on delete cascade,
  attempts    int  not null default 0,
  correct     int  not null default 0,
  mastery     numeric(5,2) not null default 0,   -- 0..100
  updated_at  timestamptz not null default now(),
  primary key (user_id, skill_id)
);

create table if not exists test_sessions (
  id           bigserial primary key,
  user_id      uuid not null references auth.users on delete cascade,
  chapters     text[] not null,
  difficulty   text,
  total        int not null default 0,
  score        int not null default 0,
  started_at   timestamptz not null default now(),
  finished_at  timestamptz
);

-- ============================================================ the engine
-- Records an attempt and advances BOTH the Leitner box and the skill mastery,
-- atomically. The client cannot skip this — it is the only write path.
create or replace function record_attempt(
  p_question_id   int,
  p_mode          text,
  p_is_correct    boolean,
  p_answer_given  text default null,
  p_seconds_taken int  default null,
  p_timed_out     boolean default false
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_user   uuid := auth.uid();
  v_skill  int;
  v_box    int;
  v_due    date;
  v_att    int;
  v_cor    int;
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  select skill_id into v_skill from questions where id = p_question_id;
  if v_skill is null then
    raise exception 'unknown question %', p_question_id;
  end if;

  insert into attempts (user_id, question_id, mode, is_correct, answer_given, seconds_taken, timed_out)
  values (v_user, p_question_id, p_mode, p_is_correct, p_answer_given, p_seconds_taken, p_timed_out);

  -- Leitner
  insert into leitner_state (user_id, question_id, box, due_at, last_seen_at)
  values (v_user, p_question_id, 1, current_date, now())
  on conflict (user_id, question_id) do nothing;

  select box into v_box from leitner_state
   where user_id = v_user and question_id = p_question_id;

  if p_is_correct then
    v_box := least(v_box + 1, 5);
  else
    v_box := 1;                        -- a miss sends it right back to the start
  end if;
  v_due := current_date + (case v_box when 1 then 1 when 2 then 2 when 3 then 4
                                      when 4 then 8 else 16 end);

  update leitner_state
     set box = v_box, due_at = v_due, last_seen_at = now()
   where user_id = v_user and question_id = p_question_id;

  -- mastery for the skill
  insert into skill_mastery (user_id, skill_id, attempts, correct, mastery)
  values (v_user, v_skill, 0, 0, 0)
  on conflict (user_id, skill_id) do nothing;

  update skill_mastery
     set attempts   = attempts + 1,
         correct    = correct + (case when p_is_correct then 1 else 0 end),
         mastery    = round(100.0 * (correct + (case when p_is_correct then 1 else 0 end))
                            / (attempts + 1), 2),
         updated_at = now()
   where user_id = v_user and skill_id = v_skill
   returning attempts, correct into v_att, v_cor;

  return jsonb_build_object(
    'box', v_box, 'due_at', v_due,
    'skill_id', v_skill, 'skill_attempts', v_att, 'skill_correct', v_cor
  );
end $$;

-- Picks the next questions to study.
-- Order: (1) anything overdue, oldest first, then (2) unseen questions —
-- and within each group, bias toward the skills that come up most in real exams.
create or replace function next_questions(
  p_chapters text[] default null,
  p_limit    int    default 10
) returns setof questions
language sql stable security definer set search_path = public as $$
  select q.*
    from questions q
    join skills   s on s.id = q.skill_id
    join chapters c on c.id = q.chapter_id
    left join leitner_state l
           on l.question_id = q.id and l.user_id = auth.uid()
   where (p_chapters is null or c.code = any(p_chapters))
     and (l.due_at is null or l.due_at <= current_date)
   order by
     (l.question_id is not null and l.due_at <= current_date) desc,  -- overdue first
     l.due_at asc nulls last,
     case s.tier when '***' then 0 when '**' then 1 when '*' then 2 else 3 end,
     random()
   limit p_limit;
$$;

-- ============================================================ RLS
alter table profiles         enable row level security;
alter table attempts         enable row level security;
alter table leitner_state    enable row level security;
alter table skill_mastery    enable row level security;
alter table test_sessions    enable row level security;
alter table chapters         enable row level security;
alter table skills           enable row level security;
alter table questions        enable row level security;
alter table solution_steps   enable row level security;
alter table concept_sections enable row level security;

-- content: any signed-in user may read; nobody may write from the client
drop policy if exists content_read_chapters on chapters;
drop policy if exists content_read_skills   on skills;
drop policy if exists content_read_qs       on questions;
drop policy if exists content_read_steps    on solution_steps;
drop policy if exists content_read_concepts on concept_sections;
create policy content_read_chapters on chapters         for select to authenticated using (true);
create policy content_read_skills   on skills           for select to authenticated using (true);
create policy content_read_qs       on questions        for select to authenticated using (true);
create policy content_read_steps    on solution_steps   for select to authenticated using (true);
create policy content_read_concepts on concept_sections for select to authenticated using (true);

-- learner data: you can only ever see and touch your own rows
drop policy if exists own_profile  on profiles;
create policy own_profile  on profiles      for all to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists own_attempts on attempts;
create policy own_attempts on attempts      for select to authenticated
  using (user_id = auth.uid());
-- note: no INSERT policy on purpose. Attempts are written ONLY through
-- record_attempt(), so the client cannot fabricate a score or skip the engine.

drop policy if exists own_leitner  on leitner_state;
create policy own_leitner  on leitner_state for select to authenticated
  using (user_id = auth.uid());

drop policy if exists own_mastery  on skill_mastery;
create policy own_mastery  on skill_mastery for select to authenticated
  using (user_id = auth.uid());

drop policy if exists own_sessions on test_sessions;
create policy own_sessions on test_sessions for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
