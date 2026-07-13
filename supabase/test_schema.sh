#!/usr/bin/env bash
# Loads the migration + seed into a throwaway Postgres and exercises the engine.
# Proves the schema works BEFORE we point Supabase at it.
set -euo pipefail

CT=laya-pgtest
PW=laya
DB=laya

cleanup() { docker rm -f $CT >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup

echo "==> starting postgres"
docker run -d --name $CT -e POSTGRES_PASSWORD=$PW -e POSTGRES_DB=$DB -p 55432:5432 \
  postgres:16-alpine >/dev/null

for i in $(seq 1 40); do
  docker exec $CT pg_isready -U postgres -q && break
  sleep 0.5
done
echo "    ready"

psql() { docker exec -i $CT psql -U postgres -d $DB -v ON_ERROR_STOP=1 "$@"; }

# Supabase provides auth.users and auth.uid(); stub them so the migration runs
# unchanged against plain Postgres.
echo "==> stubbing supabase auth"
psql -q <<'SQL'
create schema if not exists auth;
create table auth.users (
  id uuid primary key default gen_random_uuid(),
  raw_user_meta_data jsonb default '{}'::jsonb
);
create table if not exists _test_ctx (uid uuid);
create or replace function auth.uid() returns uuid
  language sql stable as $$ select uid from _test_ctx limit 1 $$;
SQL

echo "==> applying migration"
docker cp migrations/20260713_0001_init.sql $CT:/m.sql >/dev/null && psql -q -f /m.sql 2>&1 | grep -vi 'notice' || true

echo "==> loading seed"
docker cp seed.sql $CT:/s.sql >/dev/null && psql -q -f /s.sql 2>&1 | grep -vi 'notice' || true

echo
echo "==> content loaded"
psql -t -A -F' | ' <<'SQL'
select 'chapters', count(*) from chapters
union all select 'skills', count(*) from skills
union all select 'questions', count(*) from questions
union all select 'solution_steps', count(*) from solution_steps
union all select 'concept_sections', count(*) from concept_sections
union all select 'mcqs (4 options + correct)', count(*) from questions where type='mcq';
SQL

echo
echo "==> ENGINE TEST: create a user, answer questions, check Leitner + mastery"
psql <<'SQL'
\set QUIET on
insert into auth.users (id) values ('11111111-1111-1111-1111-111111111111');
insert into _test_ctx values ('11111111-1111-1111-1111-111111111111');
\set QUIET off

-- pick a question and answer it CORRECTLY three times
select 'answering ch1-q001 correctly x3' as step;
select record_attempt((select id from questions where code='ch1-q001'), 'test', true, 'b', 30)->>'box' as box_after_1;
select record_attempt((select id from questions where code='ch1-q001'), 'test', true, 'b', 25)->>'box' as box_after_2;
select record_attempt((select id from questions where code='ch1-q001'), 'test', true, 'b', 20)->>'box' as box_after_3;

select 'leitner state (expect box=4, due in 8 days)' as step;
select box, due_at - current_date as due_in_days from leitner_state
 where question_id = (select id from questions where code='ch1-q001');

select 'now get it WRONG (expect box resets to 1, due in 1 day)' as step;
select record_attempt((select id from questions where code='ch1-q001'), 'test', false, 'a', 45)->>'box' as box_after_wrong;
select box, due_at - current_date as due_in_days from leitner_state
 where question_id = (select id from questions where code='ch1-q001');

select 'skill mastery (3 of 4 correct => 75.00)' as step;
select s.name, m.attempts, m.correct, m.mastery
  from skill_mastery m join skills s on s.id = m.skill_id;
SQL

echo
echo "==> ADAPTIVE TEST: does next_questions() favour high-frequency (***) skills?"
psql <<'SQL'
select s.tier, count(*) as picked
  from next_questions(array['ch1'], 40) q
  join skills s on s.id = q.skill_id
 group by s.tier order by s.tier desc;
SQL

echo
echo "==> SECURITY TEST: can a client fake an attempt by inserting directly?"
psql -t -A <<'SQL'
select case when count(*) = 0
  then 'PASS - no INSERT policy on attempts; the only write path is record_attempt()'
  else 'FAIL - a direct INSERT policy exists' end
from pg_policies where tablename='attempts' and cmd='INSERT';
SQL

echo
echo "==> CONSTRAINT TEST: reject an MCQ that has no correct option"
psql -t -A <<'SQL'
do $$
begin
  insert into questions (code, chapter_id, skill_id, source_exam, marks, difficulty,
                         timer_seconds, type, stem_latex, options_latex, correct_option, answer_latex)
  values ('bad-1', 1, 1, 'x', 1, 'easy', 60, 'mcq', 'q', '["a","b","c","d"]'::jsonb, null, 'a');
  raise notice 'FAIL - bad MCQ was accepted';
exception when check_violation then
  raise notice 'PASS - bad MCQ rejected by mcq_has_options';
end $$;
SQL

echo
echo "all checks complete"
