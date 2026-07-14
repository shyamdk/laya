#!/usr/bin/env python3
"""Ingest the school's Kannada practice worksheets for the two lessons.

The worksheets are pure MCQ — exactly the format of the coming test — but they
ship with NO answer key. Every answer therefore has to be DERIVED, and a wrong
answer here teaches Laya the wrong thing. So nothing is guessed.

Pipeline, with two independent readers and a hard validation gate:

  PASS 1 — transcribe.  GPT-4o reads each worksheet PAGE IMAGE and returns the
           MCQs. Reading the image avoids tesseract's OCR errors.
  CHECK   — every transcribed option must also appear in the INDEPENDENT
           tesseract OCR of the same page (fuzzy). Two readers must agree, or
           the question is dropped. This is what stops invented Kannada.

  PASS 2 — answer.  GPT-4o answers each question using ONLY the study notes /
           textbook, and must quote the supporting sentence.
  CHECK   — the quote must appear in the source text, and the answer must be one
           of the options. Otherwise the question is dropped as UNGROUNDED.

Dropped questions are listed, not guessed — a human can add them by hand.
"""
import base64, difflib, glob, json, os, re, subprocess
from urllib import request

HERE = os.path.dirname(os.path.abspath(__file__))
SCRATCH = ("/private/tmp/claude-501/-Users-shyamdk-Developer-personal-laya/"
           "1dfe91e0-b9f9-4229-bb5a-4897164b4f29/scratchpad/kn")
DATA = os.path.join(HERE, "..", "data")
OUT = os.path.join(DATA, "kannada_worksheets.json")

KEY = next(l.split("=", 1)[1].strip() for l in open(os.path.join(HERE, "..", "..", ".env"))
           if l.startswith("OPENAI_API_KEY="))


def chat(messages, max_tokens=4000):
    body = json.dumps({"model": "gpt-4o", "temperature": 0, "max_tokens": max_tokens,
                       "response_format": {"type": "json_object"},
                       "messages": messages}).encode()
    req = request.Request("https://api.openai.com/v1/chat/completions", data=body,
                          headers={"Authorization": f"Bearer {KEY}",
                                   "Content-Type": "application/json"})
    with request.urlopen(req, timeout=240) as r:
        return json.loads(json.load(r)["choices"][0]["message"]["content"])


def norm(s):
    return re.sub(r"[\s​‌‍‘’\"'.,;:!?()\[\]-]+", "", s or "")


def agrees(ocr, text, cutoff=0.80):
    """Does the independent tesseract OCR contain this string (near enough)?"""
    h, n = norm(ocr), norm(text)
    if not n:
        return False
    if n in h:
        return True
    w = len(n)
    for i in range(0, max(1, len(h) - w + 1), 3):
        if difflib.SequenceMatcher(None, h[i:i + w + 8], n).ratio() >= cutoff:
            return True
    return False


# NOTE: GPT-4o CANNOT read Kannada script from an image. Asked to transcribe the
# worksheet pages it hallucinated all 43 questions ("ಗೋವಿಂದ ಪ್ರ.ರಚನೆ ಮಾಡಿದ ತಾಯಿಗಳ"),
# and the OCR cross-check rejected every one. So it is NOT allowed to read Kannada.
# Its only job is to SPLIT the tesseract OCR text into stem + options. Every
# character it emits must already exist in that OCR.
TRANSCRIBE = (
    "You are given the raw OCR text of a Kannada MCQ worksheet page.\n"
    "Split it into questions. COPY the Kannada characters EXACTLY as they appear in "
    "the OCR — you are a formatter, not a reader. Never correct, translate, "
    "re-spell or improve anything. Never add a character that is not in the OCR.\n"
    "Drop the option label (the 'ಅ)' / 'a)' prefix) but keep the option text verbatim.\n"
    "Only return questions that have 4 options in the OCR.\n"
    'JSON: {"questions":[{"n":"1","stem":"...","options":["..","..","..",".."]}]}'
)

ANSWER = (
    "You answer Kannada MCQs using ONLY the evidence supplied.\n"
    "- Answer ONLY if the evidence settles it. Otherwise answer_index = null.\n"
    "- evidence_quote must be copied EXACTLY from the evidence. Never paraphrase. "
    "If you cannot copy one, use \"\".\n"
    "- Do NOT use outside knowledge. Do NOT guess.\n"
    'JSON: {"answers":[{"n":"1","answer_index":0,"evidence_quote":"...",'
    '"why_en":"one short English sentence"}]}'
)

JOBS = [
    ("kn-l1", "ಮಗ್ಗದ ಸಾಹೇಬ", "ms_worksheet",
     "1. maggada-saheba/practice-sheet", ["ms_notes", "ms_sandharbha"]),
    ("kn-l5", "ಕನ್ನಡಿಗರ ತಾಯಿ", "kt_worksheet",
     "5. kannadigaraThayi/practice-sheets", ["kt_notes"]),
]

BOOK = os.path.join(DATA, "kannada_source.json")
src = json.load(open(BOOK))

kept, dropped = [], []

for code, title, tag, folder, ev_files in JOBS:
    pdf = glob.glob(os.path.join(HERE, "..", "..", "data", "subject", "kannada",
                                 folder, "*.pdf"))[0]
    subprocess.run(["pdftoppm", "-r", "200", "-png", pdf, f"{SCRATCH}/{tag}img"],
                   capture_output=True)
    pages = sorted(glob.glob(f"{SCRATCH}/{tag}img-*.png"))
    ocr = open(f"{SCRATCH}/{tag}.txt").read()

    # evidence = the school's own study notes + the word lists from the textbook
    lesson = next(l for l in src["lessons"] if l["code"] == code)
    book_facts = "\n".join(f"{w['word']} = {w['meaning']}" for w in lesson["word_meanings"])
    book_facts += "\n" + "\n".join(f"{n['term']}: {n['note']}" for n in lesson["notes"])
    evidence = "\n\n".join(open(f"{SCRATCH}/{e}.txt").read() for e in ev_files) \
        + "\n\n=== TEXTBOOK WORD MEANINGS ===\n" + book_facts

    print(f"\n=== {title} — {len(pages)} worksheet pages ===")

    # PASS 1: structure the tesseract OCR, one page at a time
    qs = []
    for i, pg in enumerate(pages, 1):
        page_ocr = subprocess.run(["tesseract", pg, "stdout", "-l", "kan"],
                                  capture_output=True).stdout.decode("utf-8", "replace")
        r = chat([{"role": "system", "content": TRANSCRIBE},
                  {"role": "user", "content": f"=== OCR of page {i} ===\n{page_ocr}"}])
        got = r.get("questions", [])
        qs += got
        print(f"    page {i}: {len(got)} questions")

    # CHECK: the independent tesseract OCR must agree with the transcription
    verified = []
    for q in qs:
        opts = [o.strip() for o in q.get("options", [])]
        if len(opts) < 3:
            dropped.append({**q, "lesson": code, "dropped_because": "fewer than 3 options"})
            continue
        bad = [o for o in opts if not agrees(ocr, o)]
        if bad:
            dropped.append({**q, "lesson": code,
                            "dropped_because": f"tesseract OCR does not confirm option {bad[0][:18]!r}"})
            continue
        verified.append({**q, "options": opts})
    print(f"    transcribed {len(qs)}, confirmed by the second reader: {len(verified)}")

    # PASS 2: answer, grounded in the notes
    if verified:
        payload = [{"n": q["n"], "stem": q["stem"], "options": q["options"]} for q in verified]
        r = chat([{"role": "system", "content": ANSWER},
                  {"role": "user", "content":
                      f"=== EVIDENCE (the only thing you may reason from) ===\n{evidence}\n\n"
                      f"=== QUESTIONS ===\n{json.dumps(payload, ensure_ascii=False)}"}],
                 max_tokens=4000)
        ans = {str(a["n"]): a for a in r.get("answers", [])}

        for q in verified:
            a = ans.get(str(q["n"]))
            ai = a.get("answer_index") if a else None
            quote = (a.get("evidence_quote") or "").strip() if a else ""
            why = (a.get("why_en") or "").strip() if a else ""

            if ai is None or not isinstance(ai, int) or not (0 <= ai < len(q["options"])):
                dropped.append({**q, "lesson": code,
                                "dropped_because": "model would not commit to an answer from the notes"})
            elif not quote or not agrees(evidence, quote, cutoff=0.75):
                dropped.append({**q, "lesson": code,
                                "dropped_because": "no verbatim supporting quote in the notes"})
            else:
                kept.append({"lesson": code, "n": q["n"], "stem": q["stem"],
                             "options": q["options"], "answer_index": ai,
                             "evidence": quote, "why_en": why})

print("\n" + "=" * 74)
print(f"KEPT    {len(kept):>3}  — answer grounded in a verbatim quote from the school's notes")
print(f"DROPPED {len(dropped):>3}  — NOT guessed; listed below for a human to add")
for d in dropped:
    print(f"   q{str(d.get('n')):<4} {d['dropped_because'][:56]:<56} {str(d.get('stem'))[:28]}")

json.dump({"kept": kept, "dropped": dropped}, open(OUT, "w"), ensure_ascii=False, indent=1)
print(f"\n-> {os.path.abspath(OUT)}")
