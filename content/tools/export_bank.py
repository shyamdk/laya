#!/usr/bin/env python3
"""Export the question bank to structured JSON: LaTeX-rendered, MCQ options split out,
skills + frequency tiers attached. This is the single source of truth for the DB seed."""
import json, re, os, sys, collections

sys.path.insert(0, os.path.dirname(__file__))
from build_doc import CH1, CH2, ANS1, ANS2          # noqa: E402
from build_solutions import SOL1, SOL2              # noqa: E402
from topics import T1, T2, analyse, stars           # noqa: E402

OUT = os.path.join(os.path.dirname(__file__), "..", "data", "bank.json")

# ---------------------------------------------------------------- LaTeX
# Our source markup uses ^{...} for superscripts, plus √ ∛ and unicode operators.
# We emit text with $...$ spans that flutter_math_fork / KaTeX can render.

TOK = "\x00%d\x00"
TOKRE = re.compile(r"\x00(\d+)\x00")


def to_latex(s: str) -> str:
    """Convert one source string into text with $...$ maths spans.

    Each converted fragment is stashed behind an opaque token so that later rules
    can never re-match inside emitted LaTeX (that bug produced 172 KaTeX failures:
    the superscript rule was stealing the ')' out of '\\right)').
    """
    frags: list[str] = []

    def stash(tex: str) -> str:
        frags.append(tex)
        return TOK % (len(frags) - 1)

    def resolve(x: str) -> str:
        """Inline any tokens back to raw LaTeX (for nesting inside \\sqrt{...} etc.)."""
        return TOKRE.sub(lambda m: frags[int(m.group(1))], x)

    def norm(x: str) -> str:
        """Unicode -> LaTeX, for text destined to sit INSIDE a maths span."""
        return (x.replace("−", "-").replace("–", "-")
                 .replace("×", r" \times ").replace("÷", r" \div ")
                 .replace("≤", r" \le ").replace("≥", r" \ge ")
                 # a bare '_' means subscript in LaTeX; the fill-in-the-blank
                 # questions use '___' as a literal blank, so escape it
                 .replace("_", r"\_"))

    # normalise unicode minus up front so every later rule sees ASCII '-'
    t = s.replace("−", "-").replace("–", "-")

    BASE = r"(?:\x00\d+\x00|[\d.]+|\w|\))"      # what an exponent can attach to

    # 1. root carrying an exponent:  ∛10^{6}  ->  \sqrt[3]{10^{6}}   (NOT (∛10)^6)
    t = re.sub(r"∛([\d.]+)\^\{([^}]*)\}",
               lambda m: stash(r"\sqrt[3]{%s^{%s}}" % (m[1], norm(m[2]))), t)
    t = re.sub(r"√([\d.]+)\^\{([^}]*)\}",
               lambda m: stash(r"\sqrt{%s^{%s}}" % (m[1], norm(m[2]))), t)
    # 2. bracketed fraction carrying an exponent:  (5/9)^{2x}
    t = re.sub(r"\((-?[\w.]+)/(-?[\w.]+)\)\^\{([^}]*)\}",
               lambda m: stash(r"\left(\frac{%s}{%s}\right)^{%s}"
                               % (norm(m[1]), norm(m[2]), norm(m[3]))), t)
    # 3. fraction whose DENOMINATOR carries the exponent:  27/3^{9} -> \frac{27}{3^{9}}
    #    (previously this produced \frac{27}{3}^{9}, which is a different number)
    t = re.sub(r"(?<![\w/])(-?\d+)/(\d+)\^\{([^}]*)\}",
               lambda m: stash(r"\frac{%s}{%s^{%s}}" % (m[1], m[2], norm(m[3]))), t)
    # 4. plain bracketed fraction:  (5/9)
    t = re.sub(r"\((-?[\w.]+)/(-?[\w.]+)\)",
               lambda m: stash(r"\left(\frac{%s}{%s}\right)" % (norm(m[1]), norm(m[2]))), t)
    # 5. bare numeric fraction:  27/64   (guarded so 'km/h' and '2:3:4' are untouched)
    t = re.sub(r"(?<![\w/])(-?\d+)/(\d+)(?![\w/^])",
               lambda m: stash(r"\frac{%s}{%s}" % (m[1], m[2])), t)
    # 6. roots on a bare number, so nested cases like √(128 - √49) work: the inner
    #    √49 becomes a token, then the outer √( ... ) swallows it.
    t = re.sub(r"∛([\d.]+)", lambda m: stash(r"\sqrt[3]{%s}" % m[1]), t)
    t = re.sub(r"√([\d.]+)", lambda m: stash(r"\sqrt{%s}" % m[1]), t)
    # 7. roots wrapping a bracket (may contain tokens from step 6)
    t = re.sub(r"∛\(([^()]*)\)", lambda m: stash(r"\sqrt[3]{%s}" % resolve(norm(m[1]))), t)
    t = re.sub(r"√\(([^()]*)\)", lambda m: stash(r"\sqrt{%s}" % resolve(norm(m[1]))), t)
    # 8. roots applied directly to an existing token:  √<frac>
    t = re.sub(r"∛(\x00\d+\x00)", lambda m: stash(r"\sqrt[3]{%s}" % resolve(m[1])), t)
    t = re.sub(r"√(\x00\d+\x00)", lambda m: stash(r"\sqrt{%s}" % resolve(m[1])), t)
    # 9. ANY bracket carrying an exponent:  (-2)^{6}, (32)^{-2/5}, (√4)^{0}
    #    Without this the superscript rule below grabs only the ')' and orphans the
    #    bracket contents, which is what broke (-2)^{6} into '(-2' + '$)^{6}$'.
    t = re.sub(r"\(([^()]*)\)\^\{([^}]*)\}",
               lambda m: stash(r"\left(%s\right)^{%s}"
                               % (resolve(norm(m[1])), resolve(norm(m[2])))), t)
    # 10. superscript on a token, number, word char or bracket:  p^{-3}, 0.7^{3}, 2^{6}
    t = re.sub(BASE + r"\^\{([^}]*)\}",
               lambda m: stash("%s^{%s}" % (resolve(m.group(0).split("^{")[0]),
                                            resolve(norm(m[1])))), t)

    # 8. every surviving token becomes a $...$ span; merge ones that are only
    #    separated by an operator so "2^{3} × 2^{2}" is one span, not three.
    def norm_ops(x: str) -> str:
        """Operators only — safe to run over already-converted LaTeX."""
        return (x.replace("×", r" \times ").replace("÷", r" \div ")
                 .replace("−", "-").replace("–", "-"))

    #     (do NOT norm() here — the stashed fragments are already normalised LaTeX,
    #      and re-normalising turned '\_' into '\\_')
    t = re.sub(r"\x00\d+\x00(?:\s*(?:[×÷+=]|(?<=\s)-(?=\s))\s*\x00\d+\x00)*",
               lambda m: "$" + norm_ops(resolve(m.group(0))) + "$", t)
    t = TOKRE.sub(lambda m: "$" + frags[int(m.group(1))] + "$", t)   # any stragglers
    return t


# ---------------------------------------------------------------- MCQ split
OPT = re.compile(r"\(([a-d])\)\s*(.+?)(?=\s*\([a-d]\)|$)", re.S)


def split_mcq(qtext, answer):
    """Return (stem, [options], correct_index) or (qtext, [], None) if not an MCQ.

    An MCQ must have all four of (a)(b)(c)(d) AND an answer that names one of them.
    Multi-part questions also use (a)(b)(c) — they are excluded by requiring (d),
    and by requiring the answer to start with a single option letter.
    """
    lines = qtext.split("\n")
    body = "\n".join(lines[1:])
    if not all(f"({c})" in body for c in "abcd"):
        return qtext, [], None
    m = re.match(r"^\(([a-d])\)", answer.strip())
    if not m:
        return qtext, [], None
    # a case study has (a)(b)(c)(d) parts each with (i)(ii)... — exclude it
    if "(i)" in qtext and "(ii)" in qtext:
        return qtext, [], None
    opts = [(c, txt.strip().rstrip(".")) for c, txt in OPT.findall(body)]
    if len(opts) != 4:
        return qtext, [], None
    stem = lines[0].strip()
    correct = "abcd".index(m.group(1))
    return stem, [o[1] for o in opts], correct


def qtype(marks, is_mcq):
    if is_mcq:
        return "mcq"
    return "short" if marks <= 2 else "long"


def difficulty(marks):
    return {1: "easy", 2: "medium", 3: "hard", 4: "challenge"}[marks]


TIMER = {1: 60, 2: 120, 3: 210, 4: 300}

chapters = [
    {"code": "ch1", "number": 1, "title": "A Square and A Cube",
     "book": "NCERT Ganita Prakash, Grade 8",
     "items": (CH1, ANS1, SOL1, T1)},
    {"code": "ch2", "number": 2, "title": "Power Play",
     "book": "NCERT Ganita Prakash, Grade 8",
     "items": (CH2, ANS2, SOL2, T2)},
]

out = {"chapters": [], "skills": [], "questions": []}
skill_ids = {}

for ch in chapters:
    items, answers, sols, tags = ch.pop("items")
    exam_count = {t: ex for t, _, ex, _ in analyse(items, tags)}
    total_exams = len({s for _, s, _ in items})
    out["chapters"].append({k: ch[k] for k in ("code", "number", "title", "book")})

    for i, ((q, src, marks), ans, steps, tag) in enumerate(zip(items, answers, sols, tags), 1):
        if tag not in skill_ids:
            skill_ids[tag] = len(skill_ids) + 1
            out["skills"].append({
                "id": skill_ids[tag], "name": tag, "chapter": ch["code"],
                "exams_seen_in": exam_count[tag], "total_exams": total_exams,
                "tier": stars(exam_count[tag]) or "-",
            })
        stem, opts, correct = split_mcq(q, ans)
        is_mcq = correct is not None
        out["questions"].append({
            "code": f"{ch['code']}-q{i:03d}",
            "chapter": ch["code"],
            "skill_id": skill_ids[tag],
            "source_exam": src,
            "marks": marks,
            "difficulty": difficulty(marks),
            "timer_seconds": TIMER[marks],
            "type": qtype(marks, is_mcq),
            "stem_latex": to_latex(stem),
            "options_latex": [to_latex(o) for o in opts],
            "correct_option": correct,
            "answer_latex": to_latex(ans),
            "solution_steps_latex": [to_latex(s) for s in steps],
        })

# ---------------------------------------------------------------- concept guide
# Learn mode shows these before the practice questions.
from build_concepts import C1, C2, TIER1, TIER2, REAL1, REAL2   # noqa: E402

out["concept_sections"] = []
for ch_code, sections, tiers, reals in (("ch1", C1, TIER1, REAL1), ("ch2", C2, TIER2, REAL2)):
    for idx, (title, blocks) in enumerate(sections, 1):
        tier, why = tiers.get(idx, ("", ""))
        body = []
        for kind, payload in blocks:
            if kind in ("p", "key", "warn"):
                body.append({"kind": kind, "text": to_latex(payload)})
            elif kind in ("eg", "steps", "bullets"):
                body.append({"kind": kind, "lines": [to_latex(x) for x in payload]})
            elif kind == "check":
                body.append({"kind": "check",
                             "items": [{"q": to_latex(q), "a": to_latex(a)} for q, a in payload]})
            elif kind == "tbl":
                heads, rows = payload
                body.append({"kind": "tbl",
                             "head": [to_latex(h) for h in heads],
                             "rows": [[to_latex(c) for c in r] for r in rows]})
        if idx in reals:
            body.append({"kind": "real", "text": to_latex(reals[idx])})
        out["concept_sections"].append({
            "chapter": ch_code, "idx": idx, "title": to_latex(title),
            "tier": tier or "-", "why": why, "body": body,
        })

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w") as f:
    json.dump(out, f, indent=1, ensure_ascii=False)
print(f"  concept sections: {len(out['concept_sections'])}")

n = len(out["questions"])
mcq = sum(1 for q in out["questions"] if q["type"] == "mcq")
by_type = collections.Counter(q["type"] for q in out["questions"])
by_diff = collections.Counter(q["difficulty"] for q in out["questions"])
print(f"exported {n} questions, {len(out['skills'])} skills, {len(out['chapters'])} chapters")
print("  by type:      ", dict(by_type))
print("  by difficulty:", dict(by_diff))
print("  MCQs with options split out:", mcq)
print("  solution steps:", sum(len(q["solution_steps_latex"]) for q in out["questions"]))
print("->", os.path.abspath(OUT))
