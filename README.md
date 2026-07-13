# Laya

An adaptive maths practice app for one Grade 8 student.

Content is **107 real questions** pulled from 17 Sri Kumaran past papers (2021-22 → 2025-26),
covering NCERT *Ganita Prakash* Chapter 1 (A Square and A Cube) and Chapter 2 (Power Play).

- **Learn** — read the concepts, then practise. Untimed, worked solution one tap away.
- **Test** — timed questions with a countdown taken from the paper's own mark allocation.
- **Progress** — mastery per skill, so you know what to revise.

Questions are prioritised by how often each skill **actually appeared** in those 17 papers
(★★★ = 7+ exams). Those weights were counted, not guessed.

## Stack

| | |
|---|---|
| App | Flutter (web today; Android/iOS need Studio/Xcode) |
| State | Riverpod, clean architecture, repository interfaces |
| Maths | LaTeX rendered with `flutter_math_fork` |
| Backend | Supabase — Postgres + Auth + RLS + Edge Functions |
| AI | OpenAI, called **only** from an Edge Function |

## Running it

Needs Docker (for Supabase), Flutter and the Supabase CLI.

```bash
# 1. backend: starts Postgres + Auth, applies migrations, seeds the 107 questions
supabase start
supabase db reset

# 2. AI (optional): the key stays server-side, never in the app
echo "OPENAI_API_KEY=sk-..." > supabase/functions/.env
supabase functions serve --env-file supabase/functions/.env

# 3. app
cd app
flutter run -d chrome \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_ANON_KEY="$(cd .. && supabase status -o env | grep ANON_KEY | cut -d'"' -f2)"
```

## How it decides what to show next

Leitner boxes 1-5. A correct answer promotes a question one box; a wrong answer sends it
straight back to box 1. Boxes fall due after 1 / 2 / 4 / 8 / 16 days. Within what's due,
selection is biased toward the skills that come up most in real exams.

All of that lives in Postgres (`next_questions`, `record_attempt`), not in the client.

## Two rules the code enforces

**The AI never decides correctness.** It only re-explains a question whose answer we already
computed and verified offline. It cannot score, grade, or invent an answer (ADR-008).

**The client cannot fake a score.** There is deliberately no INSERT policy on `attempts`.
The only write path is `record_attempt()`, which records the answer and advances the Leitner
box and mastery atomically.

## Layout

```
app/          Flutter app
  lib/domain/       entities + repository INTERFACES (no Supabase types here)
  lib/data/         Supabase implementations of those interfaces
  lib/features/     auth · learn · test · dashboard · practice
content/      the question bank and the pipeline that produced it
supabase/     migrations, seed, Edge Function
spec/         vision, MVP spec, ADRs
```

Swapping Supabase for a FastAPI tier means writing new implementations of the three
repository interfaces and touching nothing else (ADR-014).

## Content

`content/data/bank.json` is the source of truth; `supabase/seed.sql` is generated from it.

```bash
python3 content/tools/export_bank.py    # -> bank.json
node   content/tools/validate_latex.mjs # must print "parse failures : 0"
python3 content/tools/gen_seed.py       # -> supabase/seed.sql
supabase/test_schema.sh                 # loads it into a throwaway Postgres, tests the engine
```

**`pdftotext` destroys the maths in these PDFs** — `(-3p^-3)^2` comes out as garbage. There is
no reliable automatic text path from the source papers; the questions were read and transcribed
by hand. Any future ingestion must assume this (ADR-013).

## Copyright

The Sri Kumaran papers are **not in this repo** (see `.gitignore`) and are used for personal
study only. If this ever goes beyond family use, the content must be re-authored.
