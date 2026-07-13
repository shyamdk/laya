#!/usr/bin/env python3
"""Tag every question in the bank with the skill it tests, then measure how
often each skill actually appears across the 17 past papers (2021-22 .. 2025-26)."""
import collections

# skill tag for each question, in the same order as CH1 / CH2
T1 = [
 "Identify a perfect square", "Cube roots of decimals", "Cube root basics",
 "Identify a perfect square", "Make a perfect square (multiply/divide)", "Properties of cubes",
 "Square roots of decimals", "Properties of squares", "Cubes of decimals", "Cube root basics",
 "Pythagorean triplets", "Make a perfect square (multiply/divide)", "Properties of squares",
 "Square root basics", "Cube root by estimation", "Square patterns (odd nos, gaps, digits)",
 "Cube = sum of odd numbers", "Cube root by prime factorisation", "Cube root by estimation",
 "Cube root by estimation", "Square roots of decimals", "Cube root by estimation",
 "Identify a perfect square", "Cube root by estimation", "Square patterns (odd nos, gaps, digits)",
 "Pythagorean triplets", "Pythagorean triplets", "Pythagorean triplets", "Cube root by estimation",
 "Make a perfect cube (multiply/divide)", "Cube root basics", "Make a perfect square (multiply/divide)",
 "Nearest perfect square (add/subtract)", "Cube roots of decimals",
 "Make a perfect square (multiply/divide)", "Square roots of decimals", "Cube root basics",
 "Cube root by estimation", "Square roots of decimals", "Cube root by prime factorisation",
 "Square root by estimation", "Square roots of decimals", "Square roots of decimals",
 "Square roots of decimals", "Square roots of decimals", "Square roots of decimals",
 "Square roots of decimals", "Smallest square/cube divisible by … (LCM)",
 "Make a perfect cube (multiply/divide)", "Smallest square/cube divisible by … (LCM)",
 "Smallest square/cube divisible by … (LCM)", "Make a perfect cube (multiply/divide)",
 "Nearest perfect square (add/subtract)", "Square patterns (odd nos, gaps, digits)",
 "Square patterns (odd nos, gaps, digits)", "Make a perfect cube (multiply/divide)",
 "Ratio + sum of cubes", "Ratio + sum of cubes", "Square arrangement (rows = columns)",
 "Square arrangement (rows = columns)", "Square arrangement (rows = columns)",
 "Square arrangement (rows = columns)", "Square root by prime factorisation",
]
T2 = [
 "Laws of exponents (simplify)", "Laws of exponents (simplify)", "Negative exponents",
 "Laws of exponents (simplify)", "Reciprocal / multiplicative inverse", "Zero exponent",
 "Negative exponents", "Evaluating powers (signs)", "Negative exponents", "Standard form (convert)",
 "Reciprocal / multiplicative inverse", "Evaluating powers (signs)", "Standard form (convert)",
 "Standard form (convert)", "Laws of exponents (simplify)", "Negative exponents",
 "Standard form (arithmetic)", "Solve for x (same base)", "Zero exponent",
 "Laws of exponents (simplify)", "Negative exponents", "Laws of exponents (simplify)",
 "Laws of exponents (simplify)", "Laws of exponents (simplify)", "Solve for x (same base)",
 "Solve for x (same base)", "Solve for x (same base)", "Solve for x (same base)",
 "Negative exponents", "Solve for x (same base)", "Solve for x (same base)",
 "Laws of exponents (simplify)", "Laws of exponents (simplify)", "Laws of exponents (simplify)",
 "Laws of exponents (simplify)", "Solve for x (same base)", "Laws of exponents (simplify)",
 "Fractional exponents (beyond book)", "Standard form (arithmetic)", "Standard form (arithmetic)",
 "Standard form (arithmetic)", "Standard form (arithmetic)", "Standard form (arithmetic)",
 "Standard form (convert)",
]


TIER_NAME = {"***": "MUST KNOW", "**": "IMPORTANT", "*": "SEEN SOMETIMES", "": ""}


def analyse(items, tags):
    n = collections.Counter()
    papers = collections.defaultdict(set)
    for (q, src, marks), tag in zip(items, tags):
        n[tag] += 1
        papers[tag].add(src)
    rows = [(t, n[t], len(papers[t]), sorted(papers[t])) for t in n]
    return sorted(rows, key=lambda r: (-r[2], -r[1]))


def stars(exams):
    if exams >= 7: return "***"
    if exams >= 4: return "**"
    if exams >= 2: return "*"
    return ""


if __name__ == "__main__":
    from build_doc import CH1, CH2
    assert len(T1) == len(CH1) and len(T2) == len(CH2)
    for name, items, tags in (("CHAPTER 1", CH1, T1), ("CHAPTER 2", CH2, T2)):
        total_papers = len({s for _, s, _ in items})
        print(f"\n{name}  ({len(items)} questions across {total_papers} different exams)")
        print(f"{'skill':<44} {'Qs':>3} {'exams':>6}  tier")
        print("-" * 70)
        for t, cnt, ex, _ in analyse(items, tags):
            print(f"{t:<44} {cnt:>3} {ex:>6}  {stars(ex)}")
