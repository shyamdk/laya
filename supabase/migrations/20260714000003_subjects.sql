-- Add a SUBJECT dimension so the same engine serves Maths and Kannada.
--
-- A Kannada "chapter" is either a lesson (ಮಗ್ಗದ ಸಾಹೇಬ) or a standalone grammar
-- topic (ಸಂಧಿ) — grammar is not tied to one lesson, which is why chapters are
-- the right shape for both.
--
-- Everything else (Leitner, mastery, record_attempt, next_questions) is unchanged:
-- the engine never cared what the content was.

create table if not exists subjects (
  id     serial primary key,
  code   text unique not null,     -- 'maths' | 'kannada'
  name   text not null,
  script text not null default 'latin' check (script in ('latin', 'kannada'))
);

insert into subjects (code, name, script) values
  ('maths',   'Mathematics', 'latin'),
  ('kannada', 'ಕನ್ನಡ (Kannada)', 'kannada')
on conflict (code) do nothing;

-- existing content is all maths
alter table chapters add column if not exists subject_id int references subjects;
update chapters set subject_id = (select id from subjects where code = 'maths')
 where subject_id is null;
alter table chapters alter column subject_id set not null;

-- Kannada questions carry an English instruction ("What does this word mean?")
-- alongside the Kannada being asked about. Maths leaves this null.
alter table questions add column if not exists stem_en text;

-- tap-to-match questions: no Kannada typing needed
alter table questions add column if not exists match_pairs jsonb;
alter table questions drop constraint if exists questions_type_check;
alter table questions add constraint questions_type_check
  check (type in ('mcq', 'short', 'long', 'match'));

-- the MCQ constraint must now tolerate 'match' (which has pairs, not options)
alter table questions drop constraint if exists mcq_has_options;
alter table questions add constraint mcq_has_options check (
      (type = 'mcq'   and correct_option is not null and jsonb_array_length(options_latex) between 3 and 4)
   or (type = 'match' and match_pairs is not null and jsonb_array_length(match_pairs) >= 2)
   or (type in ('short','long') and correct_option is null)
);

-- why each answer is right, in English (Kannada uses it; maths has solution_steps)
alter table questions add column if not exists explain_en text;

-- a match set is worth one mark per pair, so it can exceed the 1-4 of a written
-- maths question
alter table questions drop constraint if exists questions_marks_check;
alter table questions add constraint questions_marks_check check (marks between 1 and 10);

-- Serve the adaptive queue for ONE subject at a time.
create or replace function next_questions(
  p_chapters text[] default null,
  p_limit    int    default 10,
  p_subject  text   default null
) returns setof questions
language sql stable security definer set search_path = public as $$
  select q.*
    from questions q
    join skills   s on s.id = q.skill_id
    join chapters c on c.id = q.chapter_id
    join subjects sub on sub.id = c.subject_id
    left join leitner_state l
           on l.question_id = q.id and l.user_id = auth.uid()
   where (p_subject  is null or sub.code = p_subject)
     and (p_chapters is null or c.code = any(p_chapters))
     and (l.due_at is null or l.due_at <= current_date)
   order by
     (l.question_id is not null and l.due_at <= current_date) desc,   -- overdue first
     l.due_at asc nulls last,
     case s.tier when '***' then 0 when '**' then 1 when '*' then 2 else 3 end,
     random()
   limit p_limit;
$$;

grant select on subjects to authenticated;
grant execute on function next_questions(text[], int, text) to authenticated;
