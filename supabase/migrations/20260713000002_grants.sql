-- Row Level Security decides WHICH ROWS you may see.
-- Table GRANTs decide whether you may touch the table AT ALL.
-- Both are required. Without these grants every query returned
-- "42501 permission denied", even though the RLS policies were correct.

grant usage on schema public to anon, authenticated;

-- content: read-only for signed-in users (RLS already restricts to SELECT)
grant select on chapters, skills, questions, solution_steps, concept_sections
  to authenticated;

-- learner data: readable by the owner (RLS enforces "owner"); NOT insertable —
-- attempts may only be written through record_attempt().
grant select on attempts, leitner_state, skill_mastery to authenticated;

grant select, insert, update on profiles to authenticated;
grant select, insert, update on test_sessions to authenticated;
grant usage, select on sequence test_sessions_id_seq to authenticated;

-- the engine
grant execute on function record_attempt(int, text, boolean, text, int, boolean) to authenticated;
grant execute on function next_questions(text[], int) to authenticated;
