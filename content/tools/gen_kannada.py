#!/usr/bin/env python3
"""Generate the Kannada question bank from content/data/kannada_source.json.

Every question is DERIVED from the textbook - nothing is invented. Distractors are
drawn from the same lesson's own word list (or the same grammar topic's other types),
so a wrong option is always a plausible confusion, never nonsense.

Question types: mcq (tap an option) and match (tap-to-pair). No Kannada typing.
"""
import json, os, random, re

HERE = os.path.dirname(__file__)
SRC = os.path.join(HERE, "..", "data", "kannada_source.json")
OUT = os.path.join(HERE, "..", "data", "kannada_bank.json")

random.seed(8)   # deterministic output
src = json.load(open(SRC))

TIERS = {c: v["tier"] for c, v in src["exam_frequency_counts"].items()
         if not c.startswith("_")}
COUNTS = {c: v for c, v in src["exam_frequency_counts"].items() if not c.startswith("_")}

skills, questions = [], []
skill_id = {}


def add_skill(code, name_kn, name_en, tier, papers, of):
    if code in skill_id:
        return skill_id[code]
    sid = len(skill_id) + 1
    skill_id[code] = sid
    skills.append({"id": sid, "code": code, "name": f"{name_kn} — {name_en}",
                   "tier": tier, "exams_seen_in": papers, "total_exams": of})
    return sid


def q(code, topic, skill, stem_en, stem_kn, options, correct, explain, marks=1):
    questions.append({
        "code": code, "topic": topic, "skill_id": skill,
        "type": "mcq",
        "stem_en": stem_en,            # the instruction, in English
        "stem_kn": stem_kn,            # the Kannada being asked about
        "options": options,
        "correct_option": correct,
        "explain_en": explain,
        "marks": marks,
        "difficulty": "easy" if marks == 1 else "medium",
        "timer_seconds": 45 if marks == 1 else 90,
    })


def distractors(pool, right, n=3):
    # dedupe the pool: a repeated entry could otherwise be sampled twice, which
    # would put the SAME option on screen twice and make two answers look right.
    others = sorted({x for x in pool if x != right and "stays apart" not in x})
    return random.sample(others, min(n, len(others)))


def shuffled(right, wrong):
    opts = [right] + wrong
    random.shuffle(opts)
    return opts, opts.index(right)


# ------------------------------------------------------- vocabulary
voc = COUNTS["vocabulary"]
for L in src["lessons"]:
    sid = add_skill(f"kn-vocab-{L['code']}", f"ಪದಗಳ ಅರ್ಥ ({L['title_kn']})",
                    f"Word meanings — {L['title_en'].split(' - ')[0]}",
                    voc["tier"], voc["papers"], voc["of"])
    words = L["word_meanings"]
    meanings = [w["meaning"] for w in words]
    forms = [w["word"] for w in words]

    for i, w in enumerate(words, 1):
        # word -> meaning
        opts, ci = shuffled(w["meaning"], distractors(meanings, w["meaning"]))
        q(f"{L['code']}-vm{i:02d}", "vocabulary", sid,
          "What does this word mean?", w["word"], opts, ci,
          f"{w['word']} = {w['meaning']}  ({L['title_kn']}, ಪದಗಳ ಅರ್ಥ)")
        # meaning -> word
        opts, ci = shuffled(w["word"], distractors(forms, w["word"]))
        q(f"{L['code']}-mv{i:02d}", "vocabulary", sid,
          "Which word has this meaning?", w["meaning"], opts, ci,
          f"{w['meaning']} = {w['word']}  ({L['title_kn']}, ಪದಗಳ ಅರ್ಥ)")

# ------------------------------------------------------- grammar: classify
for g in src["grammar_topics"]:
    cnt = COUNTS.get(g["code"], {"tier": "*", "papers": 0, "of": 49})
    sid = add_skill(g["code"], g["name_kn"], g["name_en"].split(" - ")[0],
                    cnt["tier"], cnt["papers"], cnt["of"])

    types = g.get("types", [])
    type_names = [t["name_kn"] for t in types]

    for t in types:
        for j, ex in enumerate(t["examples"], 1):
            # Which type is this?  (given the split form)
            if len(type_names) >= 2:
                opts, ci = shuffled(t["name_kn"], distractors(type_names, t["name_kn"]))
                if g["code"] in ("kn-g-sandhi", "kn-g-samasa"):
                    stem = f"{ex['split']}  →  {ex['joined']}"
                    ask = "Which type is this?"
                    why = f"{ex['split']} → {ex['joined']} is {t['name_kn']} ({t['name_en']}). {t.get('rule_en','')}"
                else:
                    stem = ex["joined"]
                    ask = "Which type of word is this?"
                    why = f"{ex['joined']} is {t['name_kn']} — {t['name_en']}."
                code = f"{g['code']}-{re.sub(r'[^a-z]','',t['name_en'][:4].lower())}{j:02d}"
                q(code, "grammar", sid, ask, stem, opts, ci, why.strip())

    # "what is the joined form?" — only where a split exists
    if g["code"] in ("kn-g-sandhi", "kn-g-samasa"):
        all_joined = [e["joined"] for t in types for e in t["examples"]]
        for t in types:
            for j, ex in enumerate(t["examples"], 1):
                if "stays apart" in ex["joined"]:
                    continue
                opts, ci = shuffled(ex["joined"], distractors(all_joined, ex["joined"]))
                code = f"{g['code']}-join{re.sub(r'[^a-z]','',t['name_en'][:3].lower())}{j:02d}"
                q(code, "grammar", sid, "Join these two words. What do you get?",
                  ex["split"], opts, ci,
                  f"{ex['split']} → {ex['joined']}  ({t['name_kn']})", marks=2)

    # plain definition facts
    for j, f in enumerate(g.get("drill_facts", []), 1):
        pool = [x["a_kn"] for gg in src["grammar_topics"] for x in gg.get("drill_facts", [])]
        opts, ci = shuffled(f["a_kn"], distractors(pool, f["a_kn"]))
        q(f"{g['code']}-fact{j:02d}", "grammar", sid, f["q_en"], "",
          opts, ci, f"{f['q_en']} → {f['a_kn']}  ({g['name_kn']})")

# ------------------------------------------------------- match sets
matches = []
for L in src["lessons"]:
    pairs = [{"left": w["word"], "right": w["meaning"]} for w in L["word_meanings"]]
    for k in range(0, len(pairs), 5):
        chunk = pairs[k:k + 5]
        if len(chunk) >= 4:
            matches.append({
                "code": f"{L['code']}-match{k//5+1}",
                "skill_id": skill_id[f"kn-vocab-{L['code']}"],
                "type": "match",
                "stem_en": "Match each word to its meaning",
                "pairs": chunk,
                "marks": len(chunk),
                "difficulty": "medium",
                "timer_seconds": 30 * len(chunk),
            })

bank = {"subject": "kannada", "skills": skills,
        "questions": questions, "match_sets": matches,
        "lessons": [{"code": L["code"], "number": L["number"], "title_kn": L["title_kn"],
                     "title_en": L["title_en"], "author_kn": L["author_kn"],
                     "type": L["type"]} for L in src["lessons"]],
        "grammar_topics": [{"code": g["code"], "name_kn": g["name_kn"],
                            "name_en": g["name_en"], "explain_en": g["explain_en"],
                            "types": g.get("types", []), "taught_in": g["taught_in"]}
                           for g in src["grammar_topics"]]}

json.dump(bank, open(OUT, "w"), ensure_ascii=False, indent=1)

import collections
print(f"skills:     {len(skills)}")
for s in skills:
    n = sum(1 for x in questions if x["skill_id"] == s["id"])
    print(f"  {s['tier']:<3} {s['name']:<46} {n:>3} questions  ({s['exams_seen_in']}/{s['total_exams']} papers)")
print(f"\nquestions:  {len(questions)} MCQ")
print(f"match sets: {len(matches)}")
print("by topic:  ", dict(collections.Counter(x['topic'] for x in questions)))
print("->", os.path.abspath(OUT))
