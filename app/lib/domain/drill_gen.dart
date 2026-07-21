import 'dart:math';

/// Procedural problem generator for the speed & accuracy drills — a Dart port
/// of content/tools/drill_gen.py. Kept in lock-step with that file so a
/// worksheet feels the same whether it's printed or answered in the app;
/// the level ladder itself (titles, sequence, these `gen` specs) lives in
/// Postgres (drill_levels), not duplicated here.
class DrillProblem {
  final String key; // for de-duplication within one sheet
  final String stem; // "47 + 26 ="
  final String answer; // "73" or "12 R 2"
  const DrillProblem({required this.key, required this.stem, required this.answer});
}

(int, int) _digitRange(int n) => switch (n) {
      1 => (1, 9),
      2 => (10, 99),
      3 => (100, 999),
      4 => (1000, 9999),
      _ => throw ArgumentError('unsupported digit count: $n'),
    };

int _randInt(Random rng, int lo, int hi) => rng.nextInt(hi - lo + 1) + lo;

bool _hasCarry(int a, int b, int width) {
  final da = a.toString().padLeft(width, '0');
  final db = b.toString().padLeft(width, '0');
  for (var i = 0; i < width; i++) {
    if ((int.parse(da[i]) + int.parse(db[i])) >= 10) return true;
  }
  return false;
}

bool _hasBorrow(int a, int b, int width) {
  final da = a.toString().padLeft(width, '0');
  final db = b.toString().padLeft(width, '0');
  for (var i = 0; i < width; i++) {
    if (int.parse(da[i]) < int.parse(db[i])) return true;
  }
  return false;
}

List<int> _range2(Object o) => (o as List).map((e) => e as int).toList();

DrillProblem _one(Map<String, dynamic> gen, Random rng) {
  final type = gen['type'] as String;

  switch (type) {
    case 'add':
      if (gen.containsKey('a') && gen.containsKey('b')) {
        final ar = _range2(gen['a']), br = _range2(gen['b']);
        final minSum = (gen['min_sum'] as int?) ?? 0;
        final maxSum = (gen['max_sum'] as int?) ?? (1 << 30);
        for (var i = 0; i < 500; i++) {
          final a = _randInt(rng, ar[0], ar[1]);
          final b = _randInt(rng, br[0], br[1]);
          final s = a + b;
          if (s < minSum || s > maxSum) continue;
          return DrillProblem(key: 'add:$a:$b', stem: '$a + $b =', answer: '$s');
        }
      }
      final ra = _digitRange(gen['digits_a'] as int);
      final rb = _digitRange(gen['digits_b'] as int);
      final width = max(gen['digits_a'] as int, gen['digits_b'] as int);
      final wantCarry = gen['carry'] as bool?;
      for (var i = 0; i < 500; i++) {
        final a = _randInt(rng, ra.$1, ra.$2);
        final b = _randInt(rng, rb.$1, rb.$2);
        if (wantCarry != null && _hasCarry(a, b, width) != wantCarry) continue;
        return DrillProblem(key: 'add:$a:$b', stem: '$a + $b =', answer: '${a + b}');
      }
      throw StateError('add: could not satisfy constraints');

    case 'add_column':
      final rd = _digitRange(gen['digits'] as int);
      final count = gen['count'] as int;
      final nums = List.generate(count, (_) => _randInt(rng, rd.$1, rd.$2));
      return DrillProblem(
        key: 'addcol:${nums.join(",")}',
        stem: '${nums.join(" + ")} =',
        answer: '${nums.fold(0, (s, n) => s + n)}',
      );

    case 'sub':
      final ra = _digitRange(gen['digits_a'] as int);
      final rb = _digitRange(gen['digits_b'] as int);
      final width = max(gen['digits_a'] as int, gen['digits_b'] as int);
      final wantBorrow = gen['borrow'] as bool?;
      final needZero = (gen['zeros'] as bool?) ?? false;
      for (var i = 0; i < 800; i++) {
        final a = _randInt(rng, ra.$1, ra.$2);
        final b = _randInt(rng, rb.$1, rb.$2);
        if (a < b) continue;
        if (wantBorrow != null && _hasBorrow(a, b, width) != wantBorrow) continue;
        if (needZero && !a.toString().substring(1).contains('0')) continue;
        return DrillProblem(key: 'sub:$a:$b', stem: '$a − $b =', answer: '${a - b}');
      }
      throw StateError('sub: could not satisfy constraints');

    case 'table':
      {
        final table = gen['table'] as int;
        final r = _range2(gen['range']);
        final n = _randInt(rng, r[0], r[1]);
        final swap = rng.nextDouble() < 0.5;
        final left = swap ? n : table, right = swap ? table : n;
        return DrillProblem(key: 'mul:$table:$n', stem: '$left × $right =', answer: '${table * n}');
      }

    case 'table_mixed':
      {
        final tables = _range2(gen['tables']);
        final table = tables[rng.nextInt(tables.length)];
        final r = _range2(gen['range']);
        final n = _randInt(rng, r[0], r[1]);
        final swap = rng.nextDouble() < 0.5;
        final left = swap ? n : table, right = swap ? table : n;
        return DrillProblem(key: 'mul:$table:$n', stem: '$left × $right =', answer: '${table * n}');
      }

    case 'mul':
      final ra = _digitRange(gen['digits_a'] as int);
      final rb = _digitRange(gen['digits_b'] as int);
      final digitsB = gen['digits_b'] as int;
      final wantCarry = gen['carry'] as bool?;
      for (var i = 0; i < 500; i++) {
        final a = _randInt(rng, ra.$1, ra.$2);
        final b = _randInt(rng, rb.$1, rb.$2);
        if (digitsB == 1 && wantCarry != null) {
          final hasCarry = a.toString().split('').any((d) => (int.parse(d) * b) >= 10);
          if (hasCarry != wantCarry) continue;
        }
        return DrillProblem(key: 'mul:$a:$b', stem: '$a × $b =', answer: '${a * b}');
      }
      throw StateError('mul: could not satisfy constraints');

    case 'div_fact':
      {
        final r = _range2(gen['range']);
        final divisor = _randInt(rng, r[0], r[1]);
        final quotient = _randInt(rng, r[0], r[1]);
        final dividend = divisor * quotient;
        return DrillProblem(
            key: 'div:$dividend:$divisor', stem: '$dividend ÷ $divisor =', answer: '$quotient');
      }

    case 'div':
      final rd = _digitRange(gen['digits_dividend'] as int);
      final dr = _range2(gen['divisor']);
      final wantRemainder = (gen['remainder'] as bool?) ?? false;
      for (var i = 0; i < 500; i++) {
        final d = _randInt(rng, max(2, dr[0]), dr[1]);
        int dividend;
        if (wantRemainder) {
          dividend = _randInt(rng, rd.$1, rd.$2);
        } else {
          final qlo = (rd.$1 + d - 1) ~/ d; // ceil
          final qhi = rd.$2 ~/ d;
          if (qlo > qhi) continue;
          dividend = d * _randInt(rng, qlo, qhi);
        }
        final q = dividend ~/ d, r = dividend % d;
        final ans = r == 0 ? '$q' : '$q R $r';
        return DrillProblem(key: 'div:$dividend:$d', stem: '$dividend ÷ $d =', answer: ans);
      }
      throw StateError('div: could not satisfy constraints');

    default:
      throw ArgumentError('unknown gen type: $type');
  }
}

/// Returns `count` problems from a gen spec, avoiding duplicates where the
/// problem space allows it, and never repeating the immediately-previous item
/// — same rules as the Python generator, so in-app and printed sheets match.
List<DrillProblem> buildSheet(Map<String, dynamic> gen, int count, [Random? rng]) {
  final r = rng ?? Random();
  final out = <DrillProblem>[];
  final seen = <String>{};
  String? last;
  var attempts = 0;
  while (out.length < count && attempts < count * 60) {
    attempts++;
    final p = _one(gen, r);
    if (p.key == last) continue;
    if (seen.contains(p.key) && attempts < count * 30) continue;
    out.add(p);
    seen.add(p.key);
    last = p.key;
  }
  return out;
}
