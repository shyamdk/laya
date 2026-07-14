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
