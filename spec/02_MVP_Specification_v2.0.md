# MVP Specification (v2.0)

> Supersedes v1.1. Rewritten after spec review to resolve three contradictions with
> `data/notes.txt`. Changes from v1.1 are listed at the bottom.

## Goal

Validate the complete platform end-to-end using **real Grade 8 content** — NCERT
*Ganita Prakash* Chapter 1 (A Square and A Cube) and Chapter 2 (Power Play), backed by
107 questions extracted from 17 Sri Kumaran past papers (2021-22 → 2025-26).

The MVP is a **thin but complete vertical slice**: one student, two chapters, every layer
of the architecture exercised.

## Audience & scale

Personal use — Laya and family. Single-digit user count.

Consequences:
- Auth stays simple (Supabase email/password, no age-gating or consent machinery).
- No multi-tenancy, no teacher/admin roles.
- Sri Kumaran's copyrighted papers are used for **personal study only**. They must not be
  redistributed. If this ever becomes a product, all content must be re-authored. See Risks.

## Content — already built and verified

| Asset | Count | Status |
|---|---|---|
| Questions (with source paper + marks) | 107 | transcribed, verified |
| Answers | 107 | independently computed + verified |
| Worked solution steps | 629 | book-method only |
| Skill tags | 30 distinct | assigned per question |
| Frequency tier (★★★/★★/★) | all 107 | **counted** from the 17 papers |
| Concept-guide sections | 34 | written, with real-life examples |
| Questions needing a diagram | **0** | ← the reason this MVP is tractable |

Difficulty and timing derive from the paper's own mark allocation:

| Marks | Difficulty | Timer |
|---|---|---|
| 1 | Easy | 60 s |
| 2 | Medium | 120 s |
| 3 | Hard | 210 s |
| 4 | Challenge | 300 s |

## Features (MVP scope)

1. **Auth** — Supabase email/password. One student profile.
2. **Learn mode** — pick a chapter → read concept sections → practise questions, untimed,
   with the worked solution one tap away. Biased toward ★★★ skills.
3. **Test mode** — pick a chapter (or both) and a difficulty → timed questions with a
   visible countdown → score + review.
4. **Adaptive engine** — Leitner boxes (1–5; correct promotes, wrong resets to box 1;
   due after 1/2/4/8/16 days) with selection weighted toward high-frequency skills.
5. **Mastery tracking** — a mastery score per *skill* (not per question), so the dashboard
   says "cube root by estimation: 72%".
6. **AI explanations** — "explain this differently" on any question, via OpenAI, called
   through a Supabase Edge Function.
7. **Progress dashboard** — mastery by skill, streaks, questions due today, weakest skills.
8. **Parent summary** — a read-only session summary. (Not a parent *portal*; that stays out
   of scope, resolving the v1.1 self-contradiction.)

## Out of scope

Teacher portal · parent portal · voice tutor · other subjects · other grades ·
diagram/figure questions · offline mode.

## Architecture (per ADR, as amended)

```
Flutter (Android / iOS / Web)
   │  Riverpod · Clean Architecture · repository interfaces
   │  flutter_math_fork  ← renders LaTeX questions
   ▼
Supabase
   ├── Auth              (email/password)
   ├── Postgres + RLS    (content, attempts, mastery, Leitner state)
   └── Edge Function     (ai-explain) ──► OpenAI
                          ↑ the API key lives HERE, never in the app
```

**Security rule:** the OpenAI key is a server-side secret in the Edge Function. It must
never appear in Flutter source, in the built app, or in the repo.

All data access sits behind repository interfaces, so a FastAPI tier can replace Supabase
later without touching the UI (see ADR-013).

## Content format

Questions, options and solution steps are stored as **LaTeX** and rendered with
`flutter_math_fork`. This is required: the bank uses 213 superscripts, 18 √, 10 ∛ and 56
fractions. Unicode cannot stack fractions or draw radical bars.

## Success criteria (measurable)

1. Laya can register, log in, and complete a timed test on either chapter.
2. Answering a question updates its Leitner box and the skill's mastery score, verifiably
   in the database.
3. Questions tagged ★★★ are served measurably more often than unstarred ones.
4. The AI explanation endpoint returns a useful alternative explanation in < 5 s, and the
   OpenAI key is provably absent from the built client.
5. The same schema accepts a third chapter with no code change — proving Phase 2 reuse.

## Risks

| Risk | Mitigation |
|---|---|
| **Copyright** — the papers are Sri Kumaran's | Personal use only; never distribute. Re-author before any product. |
| Secrets in `.env` (school password, API key) | Never commit. Add `.gitignore` before `git init`. Key lives in Edge Function. |
| AI gives a *wrong* maths explanation | AI never scores or decides correctness (ADR-008). It only re-explains a question whose answer we already know. Show our verified solution alongside. |
| Old-syllabus questions use methods not in the book | Already flagged in the content (⚠ tags on long division, Pythagorean triplets, fractional exponents). |

## Changes from v1.1

1. **Content: multiplication tables → Grade 8 Squares & Cubes + Power Play.** v1.1 proposed
   multiplication tables as a thin slice; since the Grade 8 content is already extracted and
   contains **zero diagrams**, we can use the real thing at no extra ingestion cost.
2. **Backend: FastAPI vs Supabase resolved → Supabase** (ADR-003 stands; `data/notes.txt`
   is superseded).
3. **"Parent session summary" vs "Parent portal" contradiction resolved** — summary is in,
   portal is out.
4. Added the missing algorithm (Leitner), content format (LaTeX), difficulty/timing model,
   and measurable success criteria.
