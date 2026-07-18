#!/usr/bin/env python3
"""Build the Social Science question bank from the three scoped chapters.

  Ch1  Natural Resources and their Uses          (Geography)
  Ch2  Reshaping India's Political Map            (History — NEW to 2026-27)
  Ch3  Universal Franchise & India's Electoral System (Civics)

Important honesty note on the importance stars: they are counted from the 51 real
Sri Kumaran Social papers ONLY where the topic is perennial (Ch1 geography, Ch3
civics). Ch2 is NEW-syllabus history — the old papers never tested the Delhi
Sultanate or Vijayanagara (0/51), so Ch2 tiers are set by TEXTBOOK EMPHASIS and
flagged as new, not by a frequency that would be misleadingly zero.

Same discipline as the Science bank: the model drafts questions, must quote the
exact chapter sentence supporting each answer, a gate drops anything whose quote
is not verbatim, and every survivor is human-reviewed.
"""
import difflib, json, os, re, subprocess
from urllib import request

HERE = os.path.dirname(os.path.abspath(__file__))
BOOKS = os.path.join(HERE, "..", "..", "data", "subject", "social")
OUT = os.path.join(HERE, "..", "data", "social_bank.json")

KEY = next(l.split("=", 1)[1].strip() for l in open(os.path.join(HERE, "..", "..", ".env"))
           if l.startswith("OPENAI_API_KEY="))

TOPICS = [
    dict(code="soc-geo", area="Geography", number=1,
         title="Natural Resources and their Uses",
         pdf="1. Natural Resources and their uses.pdf",
         scope="Natural resources: what they are; the two ways of categorising them — "
               "(a) by USE: resources essential for life (air, water, soil/food), resources for "
               "materials, resources for energy; and (b) RENEWABLE vs NON-RENEWABLE; the distribution "
               "of resources in India (iron ore, energy, water); the 'paradox of plenty'; and "
               "responsible/wise use — conservation and STEWARDSHIP (organic farming, solar energy).",
         skills=["Types of natural resources", "Renewable vs non-renewable",
                 "Distribution of resources in India", "Conservation and stewardship"],
         tier="***", papers=32, of=51, n=30,
         why="Natural resources appeared in 32 of the 51 real Social papers."),
    dict(code="soc-hist", area="History", number=2,
         title="Reshaping India's Political Map",
         pdf="2. Reshaping India's political Map.pdf",
         scope="The political history from the Delhi Sultanate to the 18th century: the RISE AND FALL "
               "of the DELHI SULTANATE; the VIJAYANAGARA EMPIRE (Krishnadeva Raya, Hampi); the MUGHALS "
               "(Babur & the first battle of Panipat 1526, Akbar, the administrative framework, Abul "
               "Fazl); RESISTANCE — the Rajputs (Maharana Pratap, Haldighati), the Ahoms (battle of "
               "Saraighat), and the rise of the Sikhs (Guru Gobind Singh); how India was administered; "
               "and people's lives. Ask about names, battles, dates and places that the chapter states.",
         skills=["The Delhi Sultanate", "The Vijayanagara Empire", "The Mughals",
                 "Resistance: Rajputs, Ahoms, Sikhs", "Administration & people's lives"],
         tier="**", papers=11, of=51, n=34,
         why="NEW to the 2026-27 syllabus — the old papers did not test it. Marked by textbook emphasis."),
    dict(code="soc-civ", area="Civics", number=3,
         title="Universal Franchise & India's Electoral System",
         pdf="3. Universal Franchise and India's Electrol System.pdf",
         scope="UNIVERSAL ADULT FRANCHISE (every adult citizen gets ONE vote, regardless of caste, "
               "religion, gender, wealth or education); how barriers to voting are bridged; the "
               "ELECTION COMMISSION OF INDIA (its structure, the Chief Election Commissioner, "
               "Returning Officer, EVM and VVPAT, the Model Code of Conduct, T.N. Seshan); and "
               "elections to the LOK SABHA, STATE LEGISLATIVE ASSEMBLIES, the RAJYA SABHA, and the "
               "election of the PRESIDENT and VICE-PRESIDENT.",
         skills=["Universal adult franchise", "The Election Commission of India",
                 "EVM, VVPAT and the Model Code", "Lok Sabha, Rajya Sabha & elections"],
         tier="**", papers=17, of=51, n=30,
         why="Elections (Lok Sabha / Rajya Sabha) appeared in 17 of the 51 real Social papers."),
]

SYSTEM = (
    "You write multiple-choice questions for a Grade 8 student from an NCERT Social Science chapter.\n"
    "RULES:\n"
    "- Ask ONLY about content inside the stated scope. Ignore everything else in the text.\n"
    "- Every question must be answerable from the chapter text alone. No outside knowledge.\n"
    "- 'evidence' MUST be an EXACT sentence copied from the chapter text. Never paraphrase it. "
    "If you cannot copy one, do not write the question.\n"
    "- Exactly 4 options, exactly one correct. Wrong options must be plausible (a real confusion), "
    "never silly.\n"
    "- For History, prefer concrete checkable facts: who, which battle, which year, which place, which "
    "kingdom. For Civics, prefer the rule/definition and the body responsible. For Geography, prefer "
    "the category, the example, and the reason.\n"
    "- Mix difficulty: about half recall, half applying the idea.\n"
    "- 'skill' must be one of the skills given.\n"
    "- 'explain' is one or two short sentences telling the student WHY, in plain English.\n"
    "Return the result as JSON."
)


def chat(messages, max_tokens=8000):
    body = json.dumps({"model": "gpt-4o", "temperature": 0.2, "max_tokens": max_tokens,
                       "response_format": {"type": "json_object"}, "messages": messages}).encode()
    req = request.Request("https://api.openai.com/v1/chat/completions", data=body,
                          headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"})
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


bank = {"subject": "social", "chapters": [], "skills": [], "questions": []}
skill_id = {}
dropped = []

for t in TOPICS:
    text = subprocess.run(["pdftotext", os.path.join(BOOKS, t["pdf"]), "-"],
                          capture_output=True).stdout.decode("utf-8", "replace")
    text = re.sub(r"\n{2,}", "\n", text)

    bank["chapters"].append({"code": t["code"], "number": t["number"],
                             "title": f"{t['area']} — {t['title']}",
                             "book": "NCERT Social Science, Grade 8"})
    for s in t["skills"]:
        if s not in skill_id:
            skill_id[s] = len(skill_id) + 1
            bank["skills"].append({"id": skill_id[s], "name": s, "chapter": t["code"],
                                   "tier": t["tier"], "exams_seen_in": t["papers"],
                                   "total_exams": t["of"], "why": t["why"]})

    print(f"\n=== {t['area']}: {t['title']} ({len(text.split())} words) ===")
    # History chapter is long — chunk the request across two calls for coverage
    r = chat([{"role": "system", "content": SYSTEM},
              {"role": "user", "content":
                  f"SCOPE: {t['scope']}\nSKILLS (use these exact names): {t['skills']}\n\n"
                  f"=== CHAPTER TEXT ===\n{text[:24000]}\n\n"
                  f"Write {t['n']} MCQs spread across ALL the skills. Return as JSON: "
                  '{"questions":[{"stem":"..","options":["..","..","..",".."],"answer_index":0,'
                  '"skill":"..","evidence":"exact sentence from the chapter","explain":"..",'
                  '"difficulty":"easy|medium|hard"}]}'}])

    got = r.get("questions", [])
    kept = 0
    for i, q in enumerate(got, 1):
        opts = [o.strip() for o in q.get("options", [])]
        ai, ev, sk = q.get("answer_index"), (q.get("evidence") or "").strip(), q.get("skill")
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
            "code": f"{t['code']}-q{i:03d}", "chapter": t["code"], "skill_id": skill_id[sk],
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
    print(f"  {s['tier']:<3} {s['name']:<38} {c[s['id']]:>3} questions")
print(f"\n-> {os.path.abspath(OUT)}")
