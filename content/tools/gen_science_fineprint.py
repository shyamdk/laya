#!/usr/bin/env python3
"""Questions from the TEXTBOOK FINE PRINT — the side-boxes the school likes to ask from.

The NCERT 'Curiosity' chapters carry a lot of material outside the main flow:
  "A step further"         — the extra detail box
  "Our scientific heritage"— the Indian-science history box
  figure captions, activity notes, named scientists, dates and numbers

Schools ask from exactly this. It is easy to skip when revising, which is why it
is worth its own skill.

Same discipline as the rest: the model may only ask about text that IS in the
fine print, must quote the supporting sentence verbatim, and everything that
survives is read by a human.
"""
import difflib, json, os, re, subprocess
from urllib import request

HERE = os.path.dirname(os.path.abspath(__file__))
BOOKS = os.path.join(HERE, "..", "..", "data", "subject", "science")
BANK = os.path.join(HERE, "..", "data", "science_bank.json")

KEY = next(l.split("=", 1)[1].strip() for l in open(os.path.join(HERE, "..", "..", ".env"))
           if l.startswith("OPENAI_API_KEY="))

# scoped page ranges — same as the main bank
CHAPTERS = [
    ("sci-chem", "Chemistry — Particulate Nature of Matter", "7. Particulate nature of matter.pdf", 1, 9, "*", 2),
    ("sci-bio", "Biology — The Cell", "2. the invisible living world .pdf", 1, 6, "**", 29),
    ("sci-phys", "Physics — Light", "10. Light 10.pdf", 1, 18, "***", 30),
]

# the markers that begin a fine-print box
MARKERS = ["a step further", "our scientific heritage", "science and society",
           "did you know", "more to know"]
STOP = ["let us explore", "let us investigate", "let us experiment", "activity",
        "reprint 2026-27", "keep the curiosity alive"]


def fine_print(pdf, a, b):
    """Pull the side-boxes, figure captions and named-scientist lines."""
    out = []
    for p in range(a, b + 1):
        t = subprocess.run(["pdftotext", "-f", str(p), "-l", str(p),
                            os.path.join(BOOKS, pdf), "-"],
                           capture_output=True).stdout.decode("utf-8", "replace")
        lines = [l.strip() for l in t.split("\n") if l.strip()]
        i = 0
        while i < len(lines):
            if any(m in lines[i].lower() for m in MARKERS):
                box = [lines[i]]
                j = i + 1
                while j < len(lines) and len(box) < 22:
                    lo = lines[j].lower()
                    if any(s in lo for s in STOP) or re.match(r"^\d+\.\d+\s+[A-Z]", lines[j]):
                        break
                    box.append(lines[j])
                    j += 1
                out.append(f"[p{p}] " + " ".join(box))
                i = j
            else:
                i += 1
        # figure captions carry testable detail too
        for c in re.findall(r"(Fig\.\s*\d+\.\d+[a-z]?:\s*[^\n]{12,90})", t):
            out.append(f"[p{p} caption] {c.strip()}")
    return "\n\n".join(out)


def chat(messages, max_tokens=5000):
    body = json.dumps({"model": "gpt-4o", "temperature": 0.2, "max_tokens": max_tokens,
                       "response_format": {"type": "json_object"}, "messages": messages}).encode()
    req = request.Request("https://api.openai.com/v1/chat/completions", data=body,
                          headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"})
    try:
        with request.urlopen(req, timeout=300) as r:
            return json.loads(json.load(r)["choices"][0]["message"]["content"])
    except Exception as e:
        import urllib.error
        if isinstance(e, urllib.error.HTTPError):
            print("   OpenAI error:", e.code, e.read().decode()[:300])
        raise


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


SYSTEM = (
    "You write MCQs for a Grade 8 student from the FINE PRINT of an NCERT science chapter — "
    "the 'A step further' boxes, the 'Our scientific heritage' boxes, and figure captions.\n"
    "These are the small details a student skips when revising, and the ones schools like to ask.\n"
    "RULES:\n"
    "- Ask ONLY about what is in the fine print below. Nothing else.\n"
    "- Favour the specific, checkable detail: names of scientists, the work they wrote, "
    "which surface a coating goes on, numbers, dates, the exact term used.\n"
    "- 'evidence' MUST be an EXACT sentence copied from the fine print. Never paraphrase.\n"
    "- Exactly 4 options, exactly one correct. Wrong options must be plausible.\n"
    "- 'explain' is one short sentence in plain English.\n"
    "Return your answer as JSON."
)

bank = json.load(open(BANK))
next_skill = max(s["id"] for s in bank["skills"]) + 1
existing = {q["stem"].lower().strip() for q in bank["questions"]}
added, dropped = 0, 0

for code, title, pdf, a, b, tier, papers in CHAPTERS:
    fp = fine_print(pdf, a, b)
    if len(fp.split()) < 60:
        print(f"{title}: too little fine print, skipping")
        continue

    sid = next_skill
    next_skill += 1
    bank["skills"].append({"id": sid, "name": f"Textbook fine print ({title.split(' — ')[0]})",
                           "chapter": code, "tier": tier,
                           "exams_seen_in": papers, "total_exams": 59})

    print(f"\n=== {title}: {len(fp.split())} words of fine print ===")
    r = chat([{"role": "system", "content": SYSTEM},
              {"role": "user", "content":
                  f"=== FINE PRINT ===\n{fp}\n\nWrite 12 MCQs. "
                  '{"questions":[{"stem":"..","options":["..","..","..",".."],'
                  '"answer_index":0,"evidence":"exact sentence","explain":"..",'
                  '"difficulty":"easy|medium"}]}'}])

    for i, q in enumerate(r.get("questions", []), 1):
        opts = [o.strip() for o in q.get("options", [])]
        ai, ev = q.get("answer_index"), (q.get("evidence") or "").strip()
        stem = (q.get("stem") or "").strip()
        if (len(opts) != 4 or len(set(opts)) != 4 or not isinstance(ai, int)
                or not (0 <= ai < 4) or not in_text(fp, ev)
                or stem.lower() in existing):
            dropped += 1
            continue
        existing.add(stem.lower())
        marks = 1 if q.get("difficulty") == "easy" else 2
        bank["questions"].append({
            "code": f"{code}-fp{i:03d}", "chapter": code, "skill_id": sid,
            "stem": stem, "options": opts, "correct_option": ai,
            "explain": (q.get("explain") or "").strip(), "evidence": ev,
            "difficulty": q.get("difficulty", "easy"), "marks": marks,
            "timer_seconds": 60 if marks == 1 else 120,
        })
        added += 1

json.dump(bank, open(BANK, "w"), indent=1)
print(f"\n{'='*60}\nadded {added} fine-print questions, dropped {dropped}")
print(f"bank now {len(bank['questions'])} questions, {len(bank['skills'])} skills")
