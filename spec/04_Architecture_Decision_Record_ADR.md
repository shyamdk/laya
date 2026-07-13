# Architecture Decision Record (ADR)

## ADR-001: Cross-platform Framework
**Decision:** Flutter + Dart
**Reason:** Single codebase for Android, iOS, Web, excellent performance, mature ecosystem.

## ADR-002: State Management
**Decision:** Riverpod
**Reason:** Compile-time safety, testability, scalable dependency injection.

## ADR-003: Backend
**Decision:** Supabase
**Reason:** Rapid development with PostgreSQL, Auth, Storage, Realtime, RLS.

## ADR-004: Database
**Decision:** PostgreSQL
**Reason:** Relational data, SQL, analytics, extensibility for future subjects.

## ADR-005: Authentication
**Decision:** Supabase Auth
**Reason:** Secure, email verification, password reset, OAuth support.

## ADR-006: Architecture
**Decision:** Modular Monolith first
**Reason:** Simpler deployment and development. Split into services only when justified.

## ADR-007: App Architecture
**Decision:** Clean Architecture + Repository Pattern
**Reason:** Separation of concerns, easier testing, AI-assisted code generation.

## ADR-008: AI Strategy
**Decision:** AI augments learning; deterministic code controls correctness.
AI responsibilities:
- Tutor
- Explanations
- Motivation
- Parent/Teacher summaries
- Study recommendations

Deterministic responsibilities:
- Question generation
- Scoring
- Adaptive scheduling
- Mastery calculations

## ADR-008a: AI Provider (added v2.0)
**Decision:** OpenAI, called from a Supabase Edge Function.
**Reason:** Key already available. The Edge Function is mandatory, not stylistic — a key shipped
in a Flutter app (APK or web JS) can be extracted by anyone. The app calls the function; the
function holds the secret.
**Constraint:** AI is never in the correctness path. It re-explains questions whose answers we
have already computed and verified. It does not score, grade or generate questions (see ADR-008).

## ADR-009: Adaptive Learning
**Decision:** Maintain mastery per learning objective/fact and use spaced repetition plus performance metrics.

**Amended v2.0 — the algorithm, previously unspecified:**
- **Leitner boxes 1–5.** A correct answer promotes a question one box; a wrong answer sends it
  straight back to box 1. Boxes become due after 1, 2, 4, 8, 16 days.
- **Frequency weighting.** Selection is biased toward skills that historically appear most often
  in the real exams (★★★ = seen in 7+ of the 17 papers). This implements the "repeat frequently
  asked questions more often" requirement, and the weights are *counted*, not guessed.
- **Mastery is tracked per SKILL, not per question** — 30 skills across the two chapters — so the
  dashboard can say "cube root by estimation: 72%".
Rejected: SM-2 (needs a 0–5 quality rating per answer; more machinery than this MVP earns).

## ADR-010: Security
- Row Level Security
- Principle of least privilege
- Secure secrets
- Audit logging
- Privacy by design

## ADR-011: Content
Curriculum separated from application logic.
Supports multiple grades and subjects.

## ADR-012: Product Roadmap
~~Phase 1: Multiplication MVP~~ **(superseded v2.0)**
**Phase 1:** Grade 8 MVP — Ganita Prakash Ch.1 (Squares & Cubes) + Ch.2 (Power Play), 107 real
past-paper questions. Chosen over the multiplication slice because the content is already
extracted and verified, and contains **zero diagrams** — so it costs no more to build and
delivers real value immediately.
**Phase 2:** Remaining Grade 8 maths chapters, then other subjects.
**Phase 3:** Full adaptive AI learning platform.

## ADR-013: Content & Maths Format (added v2.0)
**Decision:** Store question text, options and solution steps as **LaTeX**; render with
`flutter_math_fork`.
**Reason:** The bank needs 213 superscripts, 18 √, 10 ∛ and 56 fractions. Unicode cannot stack a
fraction or draw a radical bar, and would collapse in Phase 2.
**Note:** PDF text extraction *destroys* maths — `pdftotext` turned `(−3p⁻³)²` into garbage.
Questions were therefore transcribed by reading the pages visually. Any future ingestion must
assume this: **there is no reliable automatic text path from these PDFs.**

## ADR-014: Repository Abstraction (added v2.0)
**Decision:** All data access sits behind repository interfaces in Flutter; no Supabase types
leak into domain or UI layers.
**Reason:** `data/notes.txt` asked for a loosely-coupled backend and named FastAPI. We chose
Supabase for speed (ADR-003), so this abstraction is how we honour the loose-coupling
requirement — a FastAPI tier can be substituted later without touching the UI.
