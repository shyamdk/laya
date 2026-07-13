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

final authStateProvider = StreamProvider<AuthState>(
    (ref) => ref.watch(supabaseProvider).auth.onAuthStateChange);

final chaptersProvider = FutureProvider<List<Chapter>>(
    (ref) => ref.watch(contentRepoProvider).chapters());

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
