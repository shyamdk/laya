import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/entities.dart';
import 'home_screen.dart';

/// First screen after sign-in: pick a subject.
class SubjectPicker extends ConsumerWidget {
  const SubjectPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subjects = ref.watch(subjectsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Laya'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(supabaseProvider).auth.signOut(),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: subjects.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Could not load subjects: $e')),
            data: (list) => ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('What are we studying today?',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                for (final s in list) _SubjectCard(subject: s),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SubjectCard extends ConsumerWidget {
  final Subject subject;
  const _SubjectCard({required this.subject});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kn = subject.isKannada;
    final (color, icon, blurb) = switch (subject.code) {
      'kannada' => (
          const Color(0xFF00695C),
          Icons.translate,
          'ಮಗ್ಗದ ಸಾಹೇಬ · ಕನ್ನಡಿಗರ ತಾಯಿ · ಸಂಧಿ · ಸಮಾಸ · ತತ್ಸಮ-ತದ್ಭವ',
        ),
      'science' => (
          const Color(0xFF6A1B9A),
          Icons.science_outlined,
          'Light · The Cell & organelles · Particulate nature of matter',
        ),
      _ => (
          const Color(0xFF1F3A5F),
          Icons.calculate_outlined,
          'A Square and A Cube · Power Play',
        ),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          ref.read(currentSubjectProvider.notifier).select(subject);
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const HomeScreen()));
        },
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: color.withValues(alpha: 0.14),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subject.name,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        // Kannada needs its own font — Flutter's default has no
                        // Kannada glyphs and would render tofu boxes.
                        fontFamily: kn ? 'NotoSansKannada' : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      blurb,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontFamily: kn ? 'NotoSansKannada' : null,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
