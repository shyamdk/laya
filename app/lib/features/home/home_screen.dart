import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../widgets/math_text.dart';
import '../dashboard/dashboard_screen.dart';
import '../learn/learn_screen.dart';
import '../test/test_setup_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subject = ref.watch(currentSubjectProvider);
    if (subject == null) return const SizedBox.shrink();
    final chapters = ref.watch(chaptersProvider(subject.code));
    final due = ref.watch(dueTodayProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(subject.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: 'Change subject',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              due.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (n) => n == 0
                    ? const SizedBox.shrink()
                    : Card(
                        color: Colors.amber.withValues(alpha: 0.15),
                        child: ListTile(
                          leading: const Icon(Icons.event_repeat),
                          title: Text('$n question${n == 1 ? '' : 's'} due for review today'),
                          subtitle: const Text('Spaced repetition — do these first'),
                        ),
                      ),
              ),
              const SizedBox(height: 8),
              _ModeCard(
                icon: Icons.school_outlined,
                title: 'Learn',
                subtitle:
                    'Read the concepts, then practise. Untimed, with the worked solution one tap away.',
                color: Colors.indigo,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const LearnChapterPicker())),
              ),
              _ModeCard(
                icon: Icons.timer_outlined,
                title: 'Test',
                subtitle:
                    'Timed questions with a countdown, exactly like the real paper.',
                color: Colors.deepOrange,
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TestSetupScreen())),
              ),
              _ModeCard(
                icon: Icons.insights_outlined,
                title: 'Progress',
                subtitle: 'Mastery by skill — see what to work on next.',
                color: Colors.teal,
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DashboardScreen())),
              ),
              const SizedBox(height: 20),
              chapters.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Could not load chapters: $e'),
                data: (list) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Chapters',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    for (final c in list)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: MathText('${c.number}. ${c.title}',
                            style: TextStyle(color: Colors.grey.shade700)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: color.withValues(alpha: 0.14),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade600)),
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
