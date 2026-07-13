import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../widgets/math_text.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mastery = ref.watch(masteryProvider);
    final due = ref.watch(dueTodayProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Progress')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: mastery.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (rows) {
              if (rows.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No practice yet.\nAnswer a few questions and your mastery will show up here.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              final answered = rows.fold<int>(0, (s, r) => s + r.attempts);
              final correct = rows.fold<int>(0, (s, r) => s + r.correct);
              final overall = answered == 0 ? 0 : (correct / answered * 100).round();

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(children: [
                    _Stat(label: 'Answered', value: '$answered'),
                    _Stat(label: 'Correct', value: '$correct'),
                    _Stat(label: 'Overall', value: '$overall%'),
                    _Stat(
                      label: 'Due today',
                      value: '${due.value ?? '—'}',
                    ),
                  ]),
                  const SizedBox(height: 20),
                  Text('Weakest skills first',
                      style: Theme.of(context).textTheme.titleSmall),
                  Text(
                    'Mastery is tracked per skill, not per question — so this tells you what to revise.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 10),
                  for (final r in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            TierBadge(r.tier, compact: true),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(r.skillName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600, fontSize: 13.5),
                                  overflow: TextOverflow.ellipsis),
                            ),
                            Text('${r.mastery.round()}%',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _colorFor(r.mastery),
                                )),
                          ]),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: r.mastery / 100,
                              minHeight: 7,
                              backgroundColor: Colors.grey.shade200,
                              valueColor:
                                  AlwaysStoppedAnimation(_colorFor(r.mastery)),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text('${r.correct} of ${r.attempts} correct',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  static Color _colorFor(double m) {
    if (m >= 80) return const Color(0xFF1B5E20);
    if (m >= 50) return const Color(0xFFB25E00);
    return const Color(0xFFC62828);
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style:
                  const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          Text(label,
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}
