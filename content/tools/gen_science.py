#!/usr/bin/env python3
"""Build the Science question bank from the NCERT 'Curiosity' Grade 8 chapters.

Scope is exactly what the test covers:
  Chemistry  ch.7  Particulate Nature of Matter — 7.1 and 7.2 only (book p.98-106)
  Biology    ch.2  The Invisible Living World  — the cell and its organelles only
                    (NOT microorganisms — out of the test's scope)
  Physics    ch.10 Light                       — the whole chapter

Unlike Kannada, this text extracts cleanly, so the source is reliable. The model
drafts questions but must quote the textbook sentence that supports each answer;
a validation gate then drops anything whose quote is not verbatim in the chapter.
Every surviving question is then read by a human.
"""
import difflib, json, os, re, subprocess
from urllib import request

HERE = os.path.dirname(os.path.abspath(__file__))
BOOKS = os.path.join(HERE, "..", "..", "data", "subject", "science")
OUT = os.path.join(HERE, "..", "data", "science_bank.json")

KEY = next(l.split("=", 1)[1].strip() for l in open(os.path.join(HERE, "..", "..", ".env"))
           if l.startswith("OPENAI_API_KEY="))

# (code, chapter title, pdf, page range in the PDF, skills, tier from the papers)
TOPICS = [
    dict(code="sci-chem", subject_area="Chemistry", number=7,
         title="Particulate Nature of Matter (7.1–7.2)",
         pdf="7. Particulate nature of matter.pdf", pages=(1, 9),
         scope="Sections 7.1 (what matter is made of) and 7.2 (solid, liquid, gaseous states) "
               "ONLY — book pages 98 to 106. Do NOT ask about interparticle spacing (7.3+).",
         skills=["Particles of matter", "States of matter: solid, liquid, gas"],
         tier="*", papers=2, of=59, n=26),
    dict(code="sci-bio", subject_area="Biology", number=2,
         title="The Invisible Living World — the Cell",
         pdf="2. the invisible living world .pdf", pages=(1, 6),
         scope="The CELL and its ORGANELLES only. Cover EVERY organelle the chapter "
               "describes, several questions each: cell membrane, cell wall, cytoplasm, "
               "nucleus, chloroplast/plastids, vacuole. Also cell shape variation (muscle vs "
               "nerve cell) and plant vs animal cell. "
               "NOTE: the chapter LABELS mitochondria in Fig 2.5 but NEVER states its function, "
               "so do NOT write a question about what mitochondria does. "
               "Do NOT ask about microorganisms (2.3, 2.4) — out of the test's scope.",
         skills=["Cell structure", "Cell organelles and their functions", "Plant cell vs animal cell"],
         tier="**", papers=29, of=59, n=34),
    dict(code="sci-phys", subject_area="Physics", number=10,
         title="Light",
         pdf="10. Light 10.pdf", pages=(1, 18),
         scope="The whole Light chapter: spherical mirrors (concave/convex), image "
               "characteristics, the laws of reflection, and lenses (convex/concave).",
         skills=["Laws of reflection", "Spherical mirrors", "Lenses", "Image characteristics"],
         tier="***", papers=30, of=59, n=36),
]

SYSTEM = (
    "You write multiple-choice questions for a Grade 8 student from an NCERT science chapter.\n"
    "RULES:\n"
    "- Ask ONLY about content inside the stated scope. Ignore everything else in the text.\n"
    "- Every question must be answerable from the chapter text alone.\n"
    "- 'evidence' MUST be an EXACT sentence copied from the chapter text. Never paraphrase it. "
    "If you cannot copy one, do not write the question.\n"
    "- Exactly 4 options. Exactly one correct. Wrong options must be plausible "
    "(a real confusion a student makes), never silly.\n"
    "- Mix difficulty: about half recall, half applying the idea.\n"
    "- 'skill' must be one of the skills given.\n"
    "- 'explain' is one or two short sentences telling the student WHY, in plain English."
)


def chat(messages, max_tokens=8000):
    body = json.dumps({"model": "gpt-4o", "temperature": 0.2, "max_tokens": max_tokens,
                       "response_format": {"type": "json_object"},
                       "messages": messages}).encode()
    req = request.Request("https://api.openai.com/v1/chat/completions", data=body,
                          headers={"Authorization": f"Bearer {KEY}",
                                   "Content-Type": "application/json"})
    with request.urlopen(req, timeout=300) as r:
        return json.loads(json.load(r)["choices"][0]["message"]["content"])


def norm(s):
    return re.sub(r"\s+", " ", (s or "")).strip().lower()


def in_text(text, quote, cutoff=0.82):
    h, n = norm(text), norm(quote)
    if not n or len(n) < 12:
        return False
    if n in h:
        return True
    w = len(n)
    for i in range(0, max(1, len(h) - w + 1), 5):
        if difflib.SequenceMatcher(None, h[i:i + w + 10], n).ratio() >= cutoff:
            return True
    return False


bank = {"subject": "science", "chapters": [], "skills": [], "questions": []}
skill_id = {}
dropped = []

for t in TOPICS:
    text = subprocess.run(
        ["pdftotext", "-f", str(t["pages"][0]), "-l", str(t["pages"][1]),
         os.path.join(BOOKS, t["pdf"]), "-"],
        capture_output=True).stdout.decode("utf-8", "replace")
    text = re.sub(r"\n{2,}", "\n", text)

    bank["chapters"].append({"code": t["code"], "number": t["number"],
                             "title": f"{t['subject_area']} — {t['title']}",
                             "book": "NCERT Curiosity, Grade 8"})
    for s in t["skills"]:
        if s not in skill_id:
            skill_id[s] = len(skill_id) + 1
            bank["skills"].append({"id": skill_id[s], "name": s, "chapter": t["code"],
                                   "tier": t["tier"], "exams_seen_in": t["papers"],
                                   "total_exams": t["of"]})

    print(f"\n=== {t['subject_area']}: {t['title']} ({len(text.split())} words) ===")
    r = chat([{"role": "system", "content": SYSTEM},
              {"role": "user", "content":
                  f"SCOPE: {t['scope']}\n"
                  f"SKILLS (use these exact names): {t['skills']}\n\n"
                  f"=== CHAPTER TEXT ===\n{text}\n\n"
                  f"Write {t['n']} MCQs. JSON: {{\"questions\":[{{\"stem\":\"..\","
                  f"\"options\":[\"..\",\"..\",\"..\",\"..\"],\"answer_index\":0,"
                  f"\"skill\":\"..\",\"evidence\":\"exact sentence from the chapter\","
                  f"\"explain\":\"..\",\"difficulty\":\"easy|medium|hard\"}}]}}"}])

    got = r.get("questions", [])
    kept = 0
    for i, q in enumerate(got, 1):
        opts = [o.strip() for o in q.get("options", [])]
        ai = q.get("answer_index")
        ev = (q.get("evidence") or "").strip()
        sk = q.get("skill")

        why = None
        if len(opts) != 4:
            why = "not 4 options"
        elif not isinstance(ai, int) or not (0 <= ai < 4):
            why = "bad answer index"
        elif len(set(opts)) != 4:
            why = "duplicate options"
        elif sk not in skill_id:
            why = f"unknown skill {sk!r}"
        elif not in_text(text, ev):
            why = "evidence not verbatim in the chapter"

        if why:
            dropped.append({"topic": t["code"], "stem": q.get("stem", "")[:60], "why": why})
            continue

        marks = {"easy": 1, "medium": 2, "hard": 3}.get(q.get("difficulty", "easy"), 1)
        bank["questions"].append({
            "code": f"{t['code']}-q{i:03d}",
            "chapter": t["code"], "skill_id": skill_id[sk],
            "stem": q["stem"].strip(), "options": opts, "correct_option": ai,
            "explain": (q.get("explain") or "").strip(), "evidence": ev,
            "difficulty": q.get("difficulty", "easy"), "marks": marks,
            "timer_seconds": {1: 60, 2: 120, 3: 180}[marks],
        })
        kept += 1
    print(f"    model wrote {len(got)}, kept {kept}")

json.dump(bank, open(OUT, "w"), indent=1)

import collections
print("\n" + "=" * 66)
print(f"kept    {len(bank['questions'])} questions")
print(f"dropped {len(dropped)} (not guessed)")
for d in dropped[:8]:
    print(f"   {d['why']:<36} {d['stem']}")
c = collections.Counter(q["skill_id"] for q in bank["questions"])
print()
for s in bank["skills"]:
    print(f"  {s['tier']:<3} {s['name']:<38} {c[s['id']]:>3} questions  ({s['exams_seen_in']}/{s['total_exams']} papers)")
print(f"\n-> {os.path.abspath(OUT)}")
