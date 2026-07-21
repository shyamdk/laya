import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/supabase_repositories.dart';
import '../domain/entities.dart';
import '../domain/repositories.dart';

/// Supabase connection. Passed in at build time, never hard-coded:
///   flutter run -d chrome --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}

final supabaseProvider = Provider<SupabaseClient>((_) => Supabase.instance.client);

// The UI only ever sees these interfaces (ADR-014).
final contentRepoProvider = Provider<ContentRepository>(
    (ref) => SupabaseContentRepository(ref.watch(supabaseProvider)));
final learningRepoProvider = Provider<LearningRepository>(
    (ref) => SupabaseLearningRepository(ref.watch(supabaseProvider)));
final aiRepoProvider = Provider<AiRepository>(
    (ref) => EdgeAiRepository(ref.watch(supabaseProvider)));
final drillRepoProvider = Provider<DrillRepository>(
    (ref) => SupabaseDrillRepository(ref.watch(supabaseProvider)));
final trackingRepoProvider = Provider<TrackingRepository>(
    (ref) => SupabaseTrackingRepository(ref.watch(supabaseProvider)));

final authStateProvider = StreamProvider<AuthState>(
    (ref) => ref.watch(supabaseProvider).auth.onAuthStateChange);

/// Flipped true when Supabase reports AuthChangeEvent.passwordRecovery (the
/// student clicked a reset-password email link). LayaApp shows
/// ResetPasswordScreen instead of the normal home while this is true.
class PasswordRecoveryFlag extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) => state = v;
}

final passwordRecoveryProvider =
    NotifierProvider<PasswordRecoveryFlag, bool>(PasswordRecoveryFlag.new);

/// Whether the signed-in user is the parent/admin account — gates the
/// Activity screen. False (not an error) if not signed in or the query fails.
final isAdminProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(supabaseProvider);
  final uid = db.auth.currentUser?.id;
  if (uid == null) return false;
  final row = await db.from('profiles').select('is_admin').eq('id', uid).maybeSingle();
  return row?['is_admin'] as bool? ?? false;
});

final subjectsProvider = FutureProvider<List<Subject>>(
    (ref) => ref.watch(contentRepoProvider).subjects());

/// Which subject the student is currently in.
class CurrentSubject extends Notifier<Subject?> {
  @override
  Subject? build() => null;
  void select(Subject s) => state = s;
}

final currentSubjectProvider =
    NotifierProvider<CurrentSubject, Subject?>(CurrentSubject.new);

final chaptersProvider = FutureProvider.family<List<Chapter>, String>(
    (ref, subjectCode) => ref.watch(contentRepoProvider).chapters(subjectCode));

final skillsProvider = FutureProvider<List<Skill>>(
    (ref) => ref.watch(contentRepoProvider).skills());

final conceptsProvider = FutureProvider.family<List<ConceptSection>, String>(
    (ref, code) => ref.watch(contentRepoProvider).conceptSections(code));

final solutionProvider = FutureProvider.family<List<String>, int>(
    (ref, qid) => ref.watch(contentRepoProvider).solutionSteps(qid));

final masteryProvider = FutureProvider<List<SkillMastery>>(
    (ref) => ref.watch(learningRepoProvider).mastery());

final dueTodayProvider = FutureProvider<int>(
    (ref) => ref.watch(learningRepoProvider).dueTodayCount());

final drillStrandsProvider = FutureProvider<List<DrillStrand>>(
    (ref) => ref.watch(drillRepoProvider).strands());

final drillLevelsProvider = FutureProvider.family<List<DrillLevel>, String>(
    (ref, strandCode) => ref.watch(drillRepoProvider).levels(strandCode));

final drillProgressProvider = FutureProvider.family<Map<int, DrillProgress>, String>(
    (ref, strandCode) => ref.watch(drillRepoProvider).progress(strandCode));

final drillAttemptsProvider = FutureProvider.family<List<DrillAttemptRecord>, int>(
    (ref, levelId) => ref.watch(drillRepoProvider).recentAttempts(levelId));

final activityLogProvider = FutureProvider<List<AccessLogEntry>>(
    (ref) => ref.watch(trackingRepoProvider).activity());
