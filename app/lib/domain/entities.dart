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

/// Speed & accuracy drills — a Kumon-style track, separate from the Leitner
/// question banks above. A strand is an operation (Addition, Times Tables...);
/// a level is one single-step skill within it (see content/data/drill_levels.json).
class DrillStrand {
  final int id;
  final String code;
  final String name;
  const DrillStrand({required this.id, required this.code, required this.name});
}

class DrillLevel {
  final int id;
  final int strandId;
  final String code; // 'ADD-3'
  final int seq;
  final String title;

  /// The procedural generation spec — fed straight into [buildSheet].
  final Map<String, dynamic> gen;

  const DrillLevel({
    required this.id,
    required this.strandId,
    required this.code,
    required this.seq,
    required this.title,
    required this.gen,
  });
}

/// A student's progress on one level. Absent (no row yet) means she hasn't
/// touched it — the UI treats the first level of a strand as active and
/// everything after it as locked in that case (see [effectiveDrillStatus]).
class DrillProgress {
  final String status; // 'locked' | 'active' | 'mastered'
  final num? baselineSeconds;
  final num? bestSeconds;
  final int consecutivePasses;
  final int attemptsCount;

  const DrillProgress({
    required this.status,
    required this.consecutivePasses,
    required this.attemptsCount,
    this.baselineSeconds,
    this.bestSeconds,
  });
}

String effectiveDrillStatus(int seq, DrillProgress? p) =>
    p?.status ?? (seq == 1 ? 'active' : 'locked');

/// What record_drill_attempt() decided — the client never grades speed or
/// accuracy itself (same rule as [AttemptResult] for the MCQ engine).
class DrillAttemptResult {
  final bool passed;
  final bool mastered;
  final bool isFirst; // true if this attempt set the baseline time
  final num baselineSeconds;
  final num targetSeconds;
  final int consecutivePasses;

  const DrillAttemptResult({
    required this.passed,
    required this.mastered,
    required this.isFirst,
    required this.baselineSeconds,
    required this.targetSeconds,
    required this.consecutivePasses,
  });
}

/// One past worksheet attempt on a level — the raw material for the "last
/// few runs" / best-average-worst history shown on the ladder.
class DrillAttemptRecord {
  final num secondsTaken;
  final int correct;
  final int total;
  final bool passed;
  final DateTime createdAt;

  const DrillAttemptRecord({
    required this.secondsTaken,
    required this.correct,
    required this.total,
    required this.passed,
    required this.createdAt,
  });
}

/// One row from admin_activity_log() — who opened what, and when. Visible
/// only to the parent/admin account (ADR: no client can read another
/// student's rows directly; the database enforces that, not this class).
class AccessLogEntry {
  final String userEmail;
  final String displayName;
  final String module;
  final String? subjectCode;
  final String? chapterCode;
  final String? drillStrandCode;
  final String? drillLevelCode;
  final DateTime createdAt;

  const AccessLogEntry({
    required this.userEmail,
    required this.displayName,
    required this.module,
    required this.createdAt,
    this.subjectCode,
    this.chapterCode,
    this.drillStrandCode,
    this.drillLevelCode,
  });

  /// A short human label, e.g. "Maths → Test (ch1, ch2)" or
  /// "Drills → Addition → ADD-3".
  String get label {
    switch (module) {
      case 'subject_home':
        return 'Opened ${subjectCode ?? 'a subject'}';
      case 'learn_chapter':
        return 'Learn → ${subjectCode ?? ''} → ${chapterCode ?? ''}';
      case 'test_run':
        return 'Test → ${subjectCode ?? ''} → ${chapterCode ?? ''}';
      case 'progress':
        return 'Progress → ${subjectCode ?? ''}';
      case 'drills_home':
        return 'Speed Drills';
      case 'drills_strand':
        return 'Drills → ${drillStrandCode ?? ''}';
      case 'drills_worksheet':
        return 'Drills → ${drillStrandCode ?? ''} → ${drillLevelCode ?? ''}';
      default:
        return module;
    }
  }
}
