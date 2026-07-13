import 'package:flutter_test/flutter_test.dart';

import 'package:laya/domain/entities.dart';

void main() {
  test('MCQ question parses from a database row', () {
    final q = Question.fromMap({
      'id': 1,
      'code': 'ch2-q001',
      'skill_id': 3,
      'source_exam': '2025-26 Annual',
      'marks': 1,
      'difficulty': 'easy',
      'timer_seconds': 60,
      'type': 'mcq',
      'stem_latex': r'$\left(-3p^{-3}\right)^{2}$ = ________',
      'options_latex': [r'-3$p^{-6}$', r'9$p^{-6}$', r'-9$p^{6}$', r'6$p^{6}$'],
      'correct_option': 1,
      'answer_latex': r'(b) 9$p^{-6}$',
    });

    expect(q.isMcq, isTrue);
    expect(q.optionsLatex.length, 4);
    expect(q.correctOption, 1);
    expect(q.timerSeconds, 60);
  });

  test('skill tier maps to the study-priority label', () {
    const s = Skill(
      id: 1,
      name: 'Square roots of decimals',
      examsSeenIn: 7,
      totalExams: 11,
      tier: '***',
    );
    expect(s.tierLabel, 'MUST KNOW');
  });
}
