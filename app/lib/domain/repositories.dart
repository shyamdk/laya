import 'entities.dart';

/// Repository interfaces. The UI depends only on these — never on Supabase.
///
/// This is how we honour the "loosely coupled backend" requirement from
/// data/notes.txt while still using Supabase for speed: swapping in a FastAPI
/// tier later means writing new implementations of these three, and touching
/// nothing else (ADR-014).

abstract class ContentRepository {
  Future<List<Subject>> subjects();
  Future<List<Chapter>> chapters(String subjectCode);
  Future<List<Skill>> skills();
  Future<List<ConceptSection>> conceptSections(String chapterCode);
  Future<List<String>> solutionSteps(int questionId);

  /// Questions for a timed test: filtered by chapter and difficulty.
  Future<List<Question>> testQuestions({
    required List<String> chapterCodes,
    String? difficulty,
    int limit = 10,
  });
}

abstract class LearningRepository {
  /// The adaptive queue: overdue items first, then unseen, biased toward the
  /// skills that come up most often in real exams. Computed in the database.
  Future<List<Question>> nextQuestions({
    List<String>? chapterCodes,
    String? subjectCode,
    int limit = 10,
  });

  /// Records an answer. The database advances the Leitner box and the skill
  /// mastery; we just read back what it decided.
  Future<AttemptResult> recordAttempt({
    required int questionId,
    required String mode, // 'learn' | 'test'
    required bool isCorrect,
    String? answerGiven,
    int? secondsTaken,
    bool timedOut = false,
  });

  Future<List<SkillMastery>> mastery();
  Future<int> dueTodayCount();
}

abstract class AiRepository {
  /// Re-explains a question a different way. Never used to decide correctness —
  /// we already know the answer (ADR-008a).
  Future<String> explain({
    required String questionLatex,
    required String answerLatex,
    String? studentQuestion,
  });
}

abstract class DrillRepository {
  Future<List<DrillStrand>> strands();
  Future<List<DrillLevel>> levels(String strandCode);

  /// Keyed by level id. A level with no entry hasn't been attempted yet.
  Future<Map<int, DrillProgress>> progress(String strandCode);

  /// Records a worksheet attempt. The database — not the client — decides
  /// pass/fail and whether the next level unlocks (ADR-008 applies to a
  /// stopwatch just as much as to a Leitner box).
  Future<DrillAttemptResult> recordAttempt({
    required int levelId,
    required int total,
    required int correct,
    required num secondsTaken,
  });

  /// Placement diagnostic: marks everything before [levelCode] as mastered
  /// (already fluent, skip it) and unlocks [levelCode] itself.
  Future<void> setPlacement({required String strandCode, required String levelCode});

  /// Recent worksheet attempts on a level, newest first — the "last few
  /// runs" / best-average-worst history shown on the ladder.
  Future<List<DrillAttemptRecord>> recentAttempts(int levelId, {int limit = 10});
}

abstract class TrackingRepository {
  /// Fire-and-forget: records that this user opened a module, down to the
  /// chapter/drill-level, for the parent's activity view. Never blocks or
  /// surfaces errors to the student — it's telemetry, not a feature.
  Future<void> logAccess({
    required String module,
    String? subjectCode,
    String? chapterCode,
    String? drillStrandCode,
    String? drillLevelCode,
  });

  /// Every user's activity, newest first. Only resolves for the admin
  /// account — the database rejects anyone else (see admin_activity_log()).
  Future<List<AccessLogEntry>> activity({int limit = 200});
}
