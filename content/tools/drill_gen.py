#!/usr/bin/env python3
"""Procedural problem generator for the Kumon-style speed & accuracy drills.

Pure arithmetic, no LLM — a level's "gen" spec (from drill_levels.json)
deterministically defines a family of problems; this module draws concrete,
non-duplicate problems from that family. Used by both the printable
worksheet builder (Python) and, eventually, the in-app drill (ported to Dart
with the same digit-range/carry rules so problems feel identical).

A "level" never mixes more than one new idea — mirrors the Kumon philosophy
of single-step increments (see the mind-map / study-guide precedent in this
repo for how we ground content decisions before building on them).
"""
import random


def digit_range(n):
    return {1: (1, 9), 2: (10, 99), 3: (100, 999), 4: (1000, 9999)}[n]


def _has_carry(a, b, width):
    da = [int(c) for c in str(a).zfill(width)]
    db = [int(c) for c in str(b).zfill(width)]
    return any(x + y >= 10 for x, y in zip(da, db))


def _has_borrow(a, b, width):
    da = [int(c) for c in str(a).zfill(width)]
    db = [int(c) for c in str(b).zfill(width)]
    return any(x < y for x, y in zip(da, db))


def _one(gen, rng):
    t = gen["type"]

    if t == "add":
        if "a" in gen and "b" in gen:
            for _ in range(500):
                a, b = rng.randint(*gen["a"]), rng.randint(*gen["b"])
                s = a + b
                if s < gen.get("min_sum", 0):
                    continue
                if s > gen.get("max_sum", 10 ** 9):
                    continue
                return {"key": ("add", a, b), "stem": f"{a} + {b} =", "answer": str(s)}
        ra, rb = digit_range(gen["digits_a"]), digit_range(gen["digits_b"])
        width = max(gen["digits_a"], gen["digits_b"])
        want_carry = gen.get("carry")
        for _ in range(500):
            a, b = rng.randint(*ra), rng.randint(*rb)
            if want_carry is not None and _has_carry(a, b, width) != want_carry:
                continue
            return {"key": ("add", a, b), "stem": f"{a} + {b} =", "answer": str(a + b)}

    if t == "add_column":
        rng_d = digit_range(gen["digits"])
        nums = [rng.randint(*rng_d) for _ in range(gen["count"])]
        return {"key": ("addcol", tuple(nums)), "stem": " + ".join(map(str, nums)) + " =",
                "answer": str(sum(nums))}

    if t == "sub":
        ra, rb = digit_range(gen["digits_a"]), digit_range(gen["digits_b"])
        width = max(gen["digits_a"], gen["digits_b"])
        want_borrow = gen.get("borrow")
        need_zero = gen.get("zeros", False)
        for _ in range(800):
            a, b = rng.randint(*ra), rng.randint(*rb)
            if a < b:
                continue
            if want_borrow is not None and _has_borrow(a, b, width) != want_borrow:
                continue
            if need_zero and "0" not in str(a)[1:]:
                continue
            return {"key": ("sub", a, b), "stem": f"{a} − {b} =", "answer": str(a - b)}

    if t == "table":
        table, lo_hi = gen["table"], gen["range"]
        n = rng.randint(*lo_hi)
        a, b = (table, n) if rng.random() < 0.5 else (n, table)
        return {"key": ("mul", table, n), "stem": f"{a} × {b} =", "answer": str(table * n)}

    if t == "table_mixed":
        table = rng.choice(gen["tables"])
        n = rng.randint(*gen["range"])
        a, b = (table, n) if rng.random() < 0.5 else (n, table)
        return {"key": ("mul", table, n), "stem": f"{a} × {b} =", "answer": str(table * n)}

    if t == "mul":
        ra, rb = digit_range(gen["digits_a"]), digit_range(gen["digits_b"])
        want_carry = gen.get("carry")
        for _ in range(500):
            a, b = rng.randint(*ra), rng.randint(*rb)
            if gen["digits_b"] == 1 and want_carry is not None:
                has_carry = any(int(d) * b >= 10 for d in str(a))
                if has_carry != want_carry:
                    continue
            return {"key": ("mul", a, b), "stem": f"{a} × {b} =", "answer": str(a * b)}

    if t == "div_fact":
        lo, hi = gen["range"]
        divisor, quotient = rng.randint(lo, hi), rng.randint(lo, hi)
        dividend = divisor * quotient
        return {"key": ("div", dividend, divisor), "stem": f"{dividend} ÷ {divisor} =",
                "answer": str(quotient)}

    if t == "div":
        lo, hi = digit_range(gen["digits_dividend"])
        dlo, dhi = gen["divisor"]
        for _ in range(500):
            d = rng.randint(max(2, dlo), dhi)
            if gen.get("remainder", False):
                dividend = rng.randint(lo, hi)
            else:
                qlo, qhi = -(-lo // d), hi // d
                if qlo > qhi:
                    continue
                dividend = d * rng.randint(qlo, qhi)
            q, r = divmod(dividend, d)
            ans = str(q) if r == 0 else f"{q} R {r}"
            return {"key": ("div", dividend, d), "stem": f"{dividend} ÷ {d} =", "answer": ans}

    raise ValueError(f"unknown gen type: {t}")


def build_sheet(gen, count, rng=None):
    """Return `count` problems from a gen spec, avoiding duplicates where the
    problem space allows it, and never repeating the immediately-previous item."""
    rng = rng or random.Random()
    out, seen, last = [], set(), None
    attempts = 0
    while len(out) < count and attempts < count * 60:
        attempts += 1
        p = _one(gen, rng)
        if p["key"] == last:
            continue
        if p["key"] in seen and attempts < count * 30:
            continue
        out.append(p)
        seen.add(p["key"])
        last = p["key"]
    return out


if __name__ == "__main__":
    import json, os
    HERE = os.path.dirname(os.path.abspath(__file__))
    levels = json.load(open(os.path.join(HERE, "..", "data", "drill_levels.json")))
    rng = random.Random(7)
    for strand in levels["strands"]:
        print(f"\n=== {strand['name']} ===")
        for lvl in strand["levels"]:
            sheet = build_sheet(lvl["gen"], 8, rng)
            uniq = len({p["key"] for p in sheet})
            print(f"  {lvl['code']:<8} {lvl['title']:<42} unique {uniq}/8  e.g. {sheet[0]['stem']} {sheet[0]['answer']}")
