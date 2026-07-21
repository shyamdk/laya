import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/entities.dart';
import '../domain/repositories.dart';

class SupabaseContentRepository implements ContentRepository {
  final SupabaseClient _db;
  SupabaseContentRepository(this._db);

  @override
  Future<List<Subject>> subjects() async {
    final rows = await _db.from('subjects').select().order('id', ascending: true);
    return rows
        .map((m) => Subject(
              id: m['id'] as int,
              code: m['code'] as String,
              name: m['name'] as String,
              script: m['script'] as String,
            ))
        .toList();
  }

  @override
  Future<List<Chapter>> chapters(String subjectCode) async {
    final rows = await _db
        .from('chapters')
        .select('*, subjects!inner(code)')
        .eq('subjects.code', subjectCode)
        .order('number', ascending: true);
    return rows
        .map((m) => Chapter(
              id: m['id'] as int,
              code: m['code'] as String,
              number: m['number'] as int,
              title: m['title'] as String,
            ))
        .toList();
  }

  @override
  Future<List<Skill>> skills() async {
    final rows = await _db.from('skills').select().order('exams_seen_in', ascending: false);
    return rows.map(_skill).toList();
  }

  static Skill _skill(Map<String, dynamic> m) => Skill(
        id: m['id'] as int,
        name: m['name'] as String,
        examsSeenIn: m['exams_seen_in'] as int,
        totalExams: m['total_exams'] as int,
        tier: m['tier'] as String,
      );

  @override
  Future<List<ConceptSection>> conceptSections(String chapterCode) async {
    final rows = await _db
        .from('concept_sections')
        .select('idx, title, tier, why, body, chapters!inner(code)')
        .eq('chapters.code', chapterCode)
        .order('idx', ascending: true);
    return rows
        .map((m) => ConceptSection(
              idx: m['idx'] as int,
              title: m['title'] as String,
              tier: m['tier'] as String,
              why: (m['why'] ?? '') as String,
              body: (m['body'] as List).cast<Map<String, dynamic>>(),
            ))
        .toList();
  }

  @override
  Future<List<String>> solutionSteps(int questionId) async {
    final rows = await _db
        .from('solution_steps')
        .select('text_latex')
        .eq('question_id', questionId)
        .order('step_no', ascending: true);
    return rows.map((m) => m['text_latex'] as String).toList();
  }

  @override
  Future<List<Question>> testQuestions({
    required List<String> chapterCodes,
    String? difficulty,
    int limit = 10,
  }) async {
    var q = _db
        .from('questions')
        .select('*, chapters!inner(code)')
        .inFilter('chapters.code', chapterCodes);
    if (difficulty != null) q = q.eq('difficulty', difficulty);

    final rows = await q.limit(limit * 4);
    final list = rows.map((m) => Question.fromMap(m)).toList()..shuffle();
    return list.take(limit).toList();
  }
}

class SupabaseLearningRepository implements LearningRepository {
  final SupabaseClient _db;
  SupabaseLearningRepository(this._db);

  @override
  Future<List<Question>> nextQuestions({
    List<String>? chapterCodes,
    String? subjectCode,
    int limit = 10,
  }) async {
    // The queue is computed in Postgres, not here: overdue first, then unseen,
    // biased toward high-frequency skills (ADR-009).
    final rows = await _db.rpc('next_questions', params: {
      'p_chapters': chapterCodes,
      'p_limit': limit,
      'p_subject': subjectCode,
    });
    return (rows as List)
        .map((m) => Question.fromMap(m as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<AttemptResult> recordAttempt({
    required int questionId,
    required String mode,
    required bool isCorrect,
    String? answerGiven,
    int? secondsTaken,
    bool timedOut = false,
  }) async {
    // The ONLY write path for attempts. There is no INSERT policy on the table,
    // so this cannot be bypassed from the client.
    final res = await _db.rpc('record_attempt', params: {
      'p_question_id': questionId,
      'p_mode': mode,
      'p_is_correct': isCorrect,
      'p_answer_given': answerGiven,
      'p_seconds_taken': secondsTaken,
      'p_timed_out': timedOut,
    }) as Map<String, dynamic>;

    return AttemptResult(
      box: res['box'] as int,
      dueAt: DateTime.parse(res['due_at'] as String),
      skillId: res['skill_id'] as int,
    );
  }

  @override
  Future<List<SkillMastery>> mastery() async {
    final rows = await _db
        .from('skill_mastery')
        .select('skill_id, attempts, correct, mastery, skills!inner(name, tier)');
    return rows
        .map((m) => SkillMastery(
              skillId: m['skill_id'] as int,
              skillName: m['skills']['name'] as String,
              tier: m['skills']['tier'] as String,
              attempts: m['attempts'] as int,
              correct: m['correct'] as int,
              mastery: (m['mastery'] as num).toDouble(),
            ))
        .toList()
      ..sort((a, b) => a.mastery.compareTo(b.mastery)); // weakest first
  }

  @override
  Future<int> dueTodayCount() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final rows = await _db.from('leitner_state').select('question_id').lte('due_at', today);
    return rows.length;
  }
}

class EdgeAiRepository implements AiRepository {
  final SupabaseClient _db;
  EdgeAiRepository(this._db);

  @override
  Future<String> explain({
    required String questionLatex,
    required String answerLatex,
    String? studentQuestion,
  }) async {
    // Calls a Supabase Edge Function. The OpenAI key lives there as a server-side
    // secret — it is never shipped in this app, where anyone could extract it.
    final res = await _db.functions.invoke('ai-explain', body: {
      'question': questionLatex,
      'answer': answerLatex,
      if (studentQuestion != null) 'ask': studentQuestion,
    });
    final data = res.data as Map<String, dynamic>;
    if (data['error'] != null) throw Exception(data['error']);
    return data['explanation'] as String;
  }
}

class SupabaseDrillRepository implements DrillRepository {
  final SupabaseClient _db;
  SupabaseDrillRepository(this._db);

  @override
  Future<List<DrillStrand>> strands() async {
    final rows = await _db.from('drill_strands').select().order('seq', ascending: true);
    return rows
        .map((m) => DrillStrand(id: m['id'] as int, code: m['code'] as String, name: m['name'] as String))
        .toList();
  }

  @override
  Future<List<DrillLevel>> levels(String strandCode) async {
    final rows = await _db
        .from('drill_levels')
        .select('*, drill_strands!inner(code)')
        .eq('drill_strands.code', strandCode)
        .order('seq', ascending: true);
    return rows
        .map((m) => DrillLevel(
              id: m['id'] as int,
              strandId: m['strand_id'] as int,
              code: m['code'] as String,
              seq: m['seq'] as int,
              title: m['title'] as String,
              gen: (m['gen'] as Map).cast<String, dynamic>(),
            ))
        .toList();
  }

  @override
  Future<Map<int, DrillProgress>> progress(String strandCode) async {
    final rows = await _db
        .from('drill_progress')
        .select('level_id, status, baseline_seconds, best_seconds, consecutive_passes, '
            'attempts_count, drill_levels!inner(strand_id, drill_strands!inner(code))')
        .eq('drill_levels.drill_strands.code', strandCode);
    return {
      for (final m in rows)
        m['level_id'] as int: DrillProgress(
          status: m['status'] as String,
          baselineSeconds: m['baseline_seconds'] as num?,
          bestSeconds: m['best_seconds'] as num?,
          consecutivePasses: m['consecutive_passes'] as int,
          attemptsCount: m['attempts_count'] as int,
        ),
    };
  }

  @override
  Future<DrillAttemptResult> recordAttempt({
    required int levelId,
    required int total,
    required int correct,
    required num secondsTaken,
  }) async {
    // The ONLY write path — mirrors record_attempt() for the MCQ engine.
    // There is no INSERT policy on drill_attempts/drill_progress.
    final res = await _db.rpc('record_drill_attempt', params: {
      'p_level_id': levelId,
      'p_total': total,
      'p_correct': correct,
      'p_seconds_taken': secondsTaken,
    }) as Map<String, dynamic>;

    return DrillAttemptResult(
      passed: res['passed'] as bool,
      mastered: res['mastered'] as bool,
      isFirst: res['is_first'] as bool,
      baselineSeconds: res['baseline_seconds'] as num,
      targetSeconds: res['target_seconds'] as num,
      consecutivePasses: res['consecutive_passes'] as int,
    );
  }

  @override
  Future<void> setPlacement({required String strandCode, required String levelCode}) async {
    await _db.rpc('set_drill_placement', params: {
      'p_strand': strandCode,
      'p_level_code': levelCode,
    });
  }
}
