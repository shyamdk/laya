#!/usr/bin/env python3
"""Fine-print + top-up questions for Social Science.

The school asks from the side-boxes. In these chapters they are:
  'Tapestry of the Past'      — the history detail boxes (Ch2)
  'Governance and Democracy'  — the civics boxes (Ch3)
  'DON'T MISS OUT' / 'THINK ABOUT IT' — the geography boxes (Ch1)
plus the timeline, figure captions and named people.

This pass also TOPS UP the 'Administration & people's lives' skill, which the
first generation missed (it sits in the later part of the long history chapter).

Same gate: every option and the evidence sentence must be verbatim in the chapter.
"""
import difflib, json, os, re, subprocess
from urllib import request

HERE = os.path.dirname(os.path.abspath(__file__))
BOOKS = os.path.join(HERE, "..", "..", "data", "subject", "social")
BANK = os.path.join(HERE, "..", "data", "social_bank.json")
KEY = next(l.split("=", 1)[1].strip() for l in open(os.path.join(HERE, "..", "..", ".env"))
           if l.startswith("OPENAI_API_KEY="))

PDF = {"soc-geo": "1. Natural Resources and their uses.pdf",
       "soc-hist": "2. Reshaping India's political Map.pdf",
       "soc-civ": "3. Universal Franchise and India's Electrol System.pdf"}

BOX_MARKERS = ["tapestry of the past", "governance and democracy", "don't miss out",
               "don’t miss out", "think about it", "did you know"]
STOP = ["chapter", "fig.", "reprint", "indd", "let us", "questions", "table"]


def full_text(code):
    t = subprocess.run(["pdftotext", os.path.join(BOOKS, PDF[code]), "-"],
                       capture_output=True).stdout.decode("utf-8", "replace")
    return re.sub(r"\n{2,}", "\n", t)


def fine_print(code):
    """Pull the box paragraphs, the timeline and figure captions."""
    raw = subprocess.run(["pdftotext", "-layout", os.path.join(BOOKS, PDF[code]), "-"],
                         capture_output=True).stdout.decode("utf-8", "replace")
    lines = [l.strip() for l in raw.split("\n")]
    out, i = [], 0
    while i < len(lines):
        if any(m in lines[i].lower() for m in BOX_MARKERS):
            box, j = [lines[i]], i + 1
            while j < len(lines) and len(box) < 18:
                lo = lines[j].lower()
                if not lines[j] or any(s in lo for s in STOP):
                    break
                box.append(lines[j])
                j += 1
            if len(" ".join(box)) > 60:
                out.append(" ".join(box))
            i = j
        else:
            i += 1
    caps = re.findall(r"(Fig\.\s*\d+\.\d+\.\s*[^\n]{15,90})", raw)
    return "\n\n".join(out + caps)


def chat(messages, max_tokens=6000):
    body = json.dumps({"model": "gpt-4o", "temperature": 0.2, "max_tokens": max_tokens,
                       "response_format": {"type": "json_object"}, "messages": messages}).encode()
    req = request.Request("https://api.openai.com/v1/chat/completions", data=body,
                          headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"})
    with request.urlopen(req, timeout=300) as r:
        return json.loads(json.load(r)["choices"][0]["message"]["content"])


def norm(s):
    return re.sub(r"\s+", " ", (s or "")).strip().lower()


def in_text(text, quote, cutoff=0.80):
    h, n = norm(text), norm(quote)
    if not n or len(n) < 12:
        return False
    if n in h:
        return True
    w = len(n)
    for i in range(0, max(1, len(h) - w + 1), 4):
        if difflib.SequenceMatcher(None, h[i:i + w + 10], n).ratio() >= cutoff:
            return True
    return False


bank = json.load(open(BANK))
next_skill = max(s["id"] for s in bank["skills"]) + 1
existing = [q["stem"].lower() for q in bank["questions"]]


def similar(stem):
    return any(difflib.SequenceMatcher(None, e, stem.lower()).ratio() > 0.80 for e in existing)


# ---- fine-print skill per chapter
FP_SYS = (
    "You write MCQs for a Grade 8 student from the FINE PRINT of an NCERT Social Science chapter — "
    "the side-boxes, the timeline, and figure captions. These are the details students skip and "
    "schools ask.\n"
    "- Ask ONLY about what is in the fine print given. Favour the specific checkable fact: a name, a "
    "year, a place, a battle, a term.\n"
    "- 'evidence' MUST be an exact sentence/line copied from the fine print. If you cannot, skip it.\n"
    "- 4 options, exactly one correct, plausible distractors.\n"
    "Return JSON."
)

TIER = {"soc-geo": ("***", 32), "soc-hist": ("**", 11), "soc-civ": ("**", 17)}
added, dropped = 0, 0

for code in ("soc-geo", "soc-hist", "soc-civ"):
    fp = fine_print(code)
    if len(fp.split()) < 60:
        print(f"{code}: little fine print, skipping")
        continue
    tier, papers = TIER[code]
    sid = next_skill
    next_skill += 1
    area = {"soc-geo": "Geography", "soc-hist": "History", "soc-civ": "Civics"}[code]
    bank["skills"].append({"id": sid, "name": f"Textbook fine print ({area})", "chapter": code,
                           "tier": tier, "exams_seen_in": papers, "total_exams": 51,
                           "why": "The school asks from the side-boxes, timeline and captions."})
    print(f"\n=== {area} fine print: {len(fp.split())} words ===")
    r = chat([{"role": "system", "content": FP_SYS},
              {"role": "user", "content": f"=== FINE PRINT ===\n{fp[:14000]}\n\nWrite 12 MCQs. JSON: "
               '{"questions":[{"stem":"..","options":["..","..","..",".."],"answer_index":0,'
               '"evidence":"exact line","explain":"..","difficulty":"easy|medium"}]}'}])
    for i, q in enumerate(r.get("questions", []), 1):
        opts = [o.strip() for o in q.get("options", [])]
        ai, ev, stem = q.get("answer_index"), (q.get("evidence") or "").strip(), (q.get("stem") or "").strip()
        if (len(opts) != 4 or len(set(opts)) != 4 or not isinstance(ai, int) or not (0 <= ai < 4)
                or not in_text(fp, ev) or similar(stem)):
            dropped += 1
            continue
        existing.append(stem.lower())
        marks = 1 if q.get("difficulty") == "easy" else 2
        bank["questions"].append({"code": f"{code}-fp{i:03d}", "chapter": code, "skill_id": sid,
                                  "stem": stem, "options": opts, "correct_option": ai,
                                  "explain": (q.get("explain") or "").strip(), "evidence": ev,
                                  "difficulty": q.get("difficulty", "easy"), "marks": marks,
                                  "timer_seconds": 60 if marks == 1 else 120})
        added += 1

# ---- top-up: Administration & people's lives (from the later history text)
admin_sid = next(s["id"] for s in bank["skills"] if s["name"] == "Administration & people's lives")
htext = full_text("soc-hist")
tail = htext[18000:]
ADMIN_SYS = (
    "You write MCQs from an NCERT History chapter about how India was ADMINISTERED under the Delhi "
    "Sultanate and the Mughals, and about PEOPLE'S LIVES.\n"
    "- Ask only about administration and people's lives. Favour concrete facts (Abul Fazl, the "
    "administrative framework, land revenue, officials, daily life).\n"
    "- 'evidence' must be an exact sentence from the text. 4 options, one correct.\n"
    "Return JSON."
)
print("\n=== History top-up: Administration & people's lives ===")
r = chat([{"role": "system", "content": ADMIN_SYS},
          {"role": "user", "content": f"=== TEXT ===\n{tail[:16000]}\n\nWrite 8 MCQs. JSON: "
           '{"questions":[{"stem":"..","options":["..","..","..",".."],"answer_index":0,'
           '"evidence":"exact sentence","explain":"..","difficulty":"easy|medium"}]}'}])
for i, q in enumerate(r.get("questions", []), 1):
    opts = [o.strip() for o in q.get("options", [])]
    ai, ev, stem = q.get("answer_index"), (q.get("evidence") or "").strip(), (q.get("stem") or "").strip()
    if (len(opts) != 4 or len(set(opts)) != 4 or not isinstance(ai, int) or not (0 <= ai < 4)
            or not in_text(htext, ev) or similar(stem)):
        dropped += 1
        continue
    existing.append(stem.lower())
    marks = 1 if q.get("difficulty") == "easy" else 2
    bank["questions"].append({"code": f"soc-hist-adm{i:03d}", "chapter": "soc-hist", "skill_id": admin_sid,
                              "stem": stem, "options": opts, "correct_option": ai,
                              "explain": (q.get("explain") or "").strip(), "evidence": ev,
                              "difficulty": q.get("difficulty", "easy"), "marks": marks,
                              "timer_seconds": 60 if marks == 1 else 120})
    added += 1

json.dump(bank, open(BANK, "w"), indent=1)
print(f"\nadded {added}, dropped {dropped}. bank now {len(bank['questions'])} questions, {len(bank['skills'])} skills")
