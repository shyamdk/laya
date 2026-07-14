/// Domain entities. No Supabase types leak in here (ADR-014).

class Subject {
  final int id;
  final String code;      // 'maths' | 'kannada'
  final String name;
  final String script;    // 'latin' | 'kannada'
  const Subject({required this.id, required this.code, required this.name, required this.script});

  bool get isKannada => script == 'kannada';
}

class Chapter {
  final int id;
  final String code;
  final int number;
  final String title;
  const Chapter({
    required this.id,
    required this.code,
    required this.number,
    required this.title,
  });
}

class Skill {
  final int id;
  final String name;

  /// How many of the 17 real past papers this skill appeared in.
  final int examsSeenIn;
  final int totalExams;

  /// '***' = 7+ exams, '**' = 4-6, '*' = 2-3, '-' = once. Counted, not guessed.
  final String tier;

  const Skill({
    required this.id,
    required this.name,
    required this.examsSeenIn,
    required this.totalExams,
    required this.tier,
  });

  String get tierLabel => switch (tier) {
        '***' => 'MUST KNOW',
        '**' => 'IMPORTANT',
        '*' => 'SEEN SOMETIMES',
        _ => '',
      };
}

enum QuestionType { mcq, short, long, match }

class Question {
  final int id;
  final String code;
  final int skillId;
  final String sourceExam;
  final int marks;
  final String difficulty;
  final int timerSeconds;
  final QuestionType type;

  /// Text with `$...$` maths spans. Render with [MathText].
  final String stemLatex;
  final List<String> optionsLatex;
  final int? correctOption;
  final String answerLatex;

  /// Kannada questions carry an English instruction ("What does this word
  /// mean?") alongside the Kannada being asked about. Null for maths.
  final String? stemEn;

  /// Why the answer is right, in English. Kannada uses this; maths has
  /// solution_steps instead.
  final String? explainEn;

  /// Tap-to-match pairs. No Kannada typing is ever required.
  final List<({String left, String right})> matchPairs;

  const Question({
    required this.id,
    required this.code,
    required this.skillId,
    required this.sourceExam,
    required this.marks,
    required this.difficulty,
    required this.timerSeconds,
    required this.type,
    required this.stemLatex,
    required this.optionsLatex,
    required this.correctOption,
    required this.answerLatex,
    this.stemEn,
    this.explainEn,
    this.matchPairs = const [],
  });

  bool get isMcq => type == QuestionType.mcq;
  bool get isMatch => type == QuestionType.match;

  factory Question.fromMap(Map<String, dynamic> m) => Question(
        id: m['id'] as int,
        code: m['code'] as String,
        skillId: m['skill_id'] as int,
        sourceExam: m['source_exam'] as String,
        marks: m['marks'] as int,
        difficulty: m['difficulty'] as String,
        timerSeconds: m['timer_seconds'] as int,
        type: QuestionType.values.byName(m['type'] as String),
        stemLatex: m['stem_latex'] as String,
        optionsLatex:
            (m['options_latex'] as List).map((e) => e as String).toList(),
        correctOption: m['correct_option'] as int?,
        answerLatex: m['answer_latex'] as String,
        stemEn: m['stem_en'] as String?,
        explainEn: m['explain_en'] as String?,
        matchPairs: ((m['match_pairs'] ?? const []) as List)
            .map((e) => (
                  left: (e as Map)['left'] as String,
                  right: e['right'] as String,
                ))
            .toList(),
      );
}

class ConceptSection {
  final int idx;
  final String title;
  final String tier;
  final String why;

  /// Blocks: {kind: p|key|warn|eg|steps|bullets|tbl|check|real, ...}
  final List<Map<String, dynamic>> body;

  const ConceptSection({
    required this.idx,
    required this.title,
    required this.tier,
    required this.why,
    required this.body,
  });
}

/// What the database computed after an answer. The client never works this out
/// itself — see ADR-008.
class AttemptResult {
  final int box;
  final DateTime dueAt;
  final int skillId;

  const AttemptResult({
    required this.box,
    required this.dueAt,
    required this.skillId,
  });
}

class SkillMastery {
  final int skillId;
  final String skillName;
  final String tier;
  final int attempts;
  final int correct;
  final double mastery;

  const SkillMastery({
    required this.skillId,
    required this.skillName,
    required this.tier,
    required this.attempts,
    required this.correct,
    required this.mastery,
  });
}
