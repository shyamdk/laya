-- Admin flag + cross-module access tracking.
--
-- "Admin" here means one thing: the parent account can see everyone's
-- activity log. Everyone else can only touch it through log_access() —
-- there is no INSERT policy, same rule as attempts/drill_attempts.

alter table profiles add column if not exists is_admin boolean not null default false;

-- the parent's account is recognised by email, both for existing signups
-- and any future one (re-signup, new device, etc.)
update profiles set is_admin = true
 where id in (select id from auth.users where email = 'shyamdk@gmail.com');

create or replace function handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, display_name, is_admin)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'display_name', 'Student'),
    new.email = 'shyamdk@gmail.com'
  );
  return new;
end $$;

-- ============================================================ access_log
-- One row per navigation into a module. Granularity goes down to the
-- chapter/drill-level actually opened, not just "Learn" or "Drills".
create table if not exists access_log (
  id                bigserial primary key,
  user_id           uuid not null references auth.users on delete cascade,
  module            text not null check (module in (
                       'subject_home', 'learn_chapter', 'test_run', 'progress',
                       'drills_home', 'drills_strand', 'drills_worksheet'
                     )),
  subject_code      text,
  chapter_code      text,
  drill_strand_code text,
  drill_level_code  text,
  created_at        timestamptz not null default now()
);
create index if not exists access_log_created_idx on access_log (created_at desc);
create index if not exists access_log_user_idx on access_log (user_id, created_at desc);

create or replace function log_access(
  p_module            text,
  p_subject_code      text default null,
  p_chapter_code      text default null,
  p_drill_strand_code text default null,
  p_drill_level_code  text default null
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  insert into access_log (user_id, module, subject_code, chapter_code, drill_strand_code, drill_level_code)
  values (auth.uid(), p_module, p_subject_code, p_chapter_code, p_drill_strand_code, p_drill_level_code);
end $$;

-- Admin-only read, joined against auth.users for the email (that table is
-- never directly exposed to PostgREST). Raises if the caller isn't the admin.
create or replace function admin_activity_log(p_limit int default 200)
returns table (
  id                bigint,
  user_email        text,
  display_name      text,
  module            text,
  subject_code      text,
  chapter_code      text,
  drill_strand_code text,
  drill_level_code  text,
  created_at        timestamptz
)
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from profiles pr where pr.id = auth.uid() and pr.is_admin) then
    raise exception 'not authorized';
  end if;

  return query
    select a.id, u.email::text, p.display_name, a.module, a.subject_code,
           a.chapter_code, a.drill_strand_code, a.drill_level_code, a.created_at
      from access_log a
      join auth.users u on u.id = a.user_id
      join profiles   p on p.id = a.user_id
     order by a.created_at desc
     limit p_limit;
end $$;

-- ============================================================ RLS
alter table access_log enable row level security;

drop policy if exists admin_read_access_log on access_log;
create policy admin_read_access_log on access_log for select to authenticated
  using (exists (select 1 from profiles where id = auth.uid() and is_admin));
-- no INSERT policy — written only through log_access().

grant select on access_log to authenticated;
grant execute on function log_access(text, text, text, text, text) to authenticated;
grant execute on function admin_activity_log(int) to authenticated;
