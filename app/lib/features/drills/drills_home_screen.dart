import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/entities.dart';
import 'drill_strand_screen.dart';

const _strandStyle = {
  'addition': (Icons.add, Color(0xFF1F7A3F)),
  'subtraction': (Icons.remove, Color(0xFFC62828)),
  'mult_tables': (Icons.grid_3x3, Color(0xFF6A1B9A)),
  'multiplication': (Icons.close, Color(0xFF1F3A5F)),
  'division': (Icons.percent, Color(0xFFB25E00)),
};

/// Entry point for the Kumon-style speed & accuracy drills — a track
/// separate from the exam question banks, aimed at rebuilding fluency from
/// wherever it actually breaks, regardless of school grade.
class DrillsHomeScreen extends ConsumerWidget {
  const DrillsHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strands = ref.watch(drillStrandsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Speed & Accuracy Drills')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: strands.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Could not load drills: $e')),
            data: (list) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Short, timed worksheets. Mastery = good speed AND good accuracy — '
                  'redo a whole sheet rather than just fixing the misses.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
                const SizedBox(height: 16),
                for (final s in list) _StrandCard(strand: s),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StrandCard extends ConsumerWidget {
  final DrillStrand strand;
  const _StrandCard({required this.strand});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (icon, color) = _strandStyle[strand.code] ?? (Icons.functions, Colors.blueGrey);
    final levels = ref.watch(drillLevelsProvider(strand.code));
    final progress = ref.watch(drillProgressProvider(strand.code));

    String subtitle = 'Loading…';
    levels.whenData((levelList) {
      progress.whenData((progressMap) {
        final mastered =
            levelList.where((l) => effectiveDrillStatus(l.seq, progressMap[l.id]) == 'mastered').length;
        subtitle = '$mastered of ${levelList.length} levels mastered';
      });
    });

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => DrillStrandScreen(strand: strand))),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: color.withValues(alpha: 0.14),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(strand.name,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 3),
                    Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
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
