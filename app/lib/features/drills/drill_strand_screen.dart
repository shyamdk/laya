import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/entities.dart';
import 'drill_placement_screen.dart';
import 'drill_worksheet_screen.dart';

/// The ladder for one strand: locked levels greyed out, the active level
/// highlighted, mastered levels shown with a checkmark (still tappable —
/// extra practice never hurts, same as Kumon's own repetition philosophy).
class DrillStrandScreen extends ConsumerWidget {
  final DrillStrand strand;
  const DrillStrandScreen({super.key, required this.strand});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final levels = ref.watch(drillLevelsProvider(strand.code));
    final progress = ref.watch(drillProgressProvider(strand.code));

    return Scaffold(
      appBar: AppBar(title: Text(strand.name)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: levels.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Could not load levels: $e')),
            data: (levelList) => progress.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Could not load progress: $e')),
              data: (progressMap) => ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    color: Colors.indigo.withValues(alpha: 0.06),
                    child: ListTile(
                      leading: const Icon(Icons.explore_outlined, color: Colors.indigo),
                      title: const Text('Not sure where to start?'),
                      subtitle: const Text('A 2-minute placement quiz finds your level'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => DrillPlacementScreen(strand: strand, levels: levelList))),
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final level in levelList)
                    _LevelTile(
                      level: level,
                      status: effectiveDrillStatus(level.seq, progressMap[level.id]),
                      progressRow: progressMap[level.id],
                      strandCode: strand.code,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LevelTile extends ConsumerWidget {
  final DrillLevel level;
  final String status;
  final DrillProgress? progressRow;
  final String strandCode;

  const _LevelTile({
    required this.level,
    required this.status,
    required this.progressRow,
    required this.strandCode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locked = status == 'locked';
    final mastered = status == 'mastered';

    final (icon, color) = switch (status) {
      'mastered' => (Icons.check_circle, Colors.green),
      'active' => (Icons.play_circle_fill, Colors.indigo),
      _ => (Icons.lock_outline, Colors.grey),
    };

    String? subtitle;
    if (progressRow?.bestSeconds != null) {
      subtitle = 'Best: ${progressRow!.bestSeconds!.toStringAsFixed(1)}s'
          '${mastered ? '' : '  ·  ${progressRow!.consecutivePasses}/2 passes'}';
    } else if (!locked) {
      subtitle = 'Not attempted yet';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: mastered ? Colors.green.withValues(alpha: 0.05) : null,
      child: Column(
        children: [
          ListTile(
            enabled: !locked,
            leading: Icon(icon, color: locked ? Colors.grey.shade400 : color),
            title: Text(level.title,
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: locked ? Colors.grey.shade500 : null)),
            subtitle: Text('${level.code}${subtitle != null ? '  ·  $subtitle' : ''}',
                style: TextStyle(color: locked ? Colors.grey.shade400 : Colors.grey.shade600)),
            trailing: locked ? null : const Icon(Icons.chevron_right),
            onTap: locked
                ? null
                : () {
                    ref.read(trackingRepoProvider).logAccess(
                        module: 'drills_worksheet',
                        drillStrandCode: strandCode,
                        drillLevelCode: level.code);
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => DrillWorksheetScreen(level: level, strandCode: strandCode)));
                  },
          ),
          if (!locked) _RunHistory(levelId: level.id),
        ],
      ),
    );
  }
}

/// "Save the time for every run, show the last few plus best/avg/worst" —
/// pulled straight from drill_attempts, newest first.
class _RunHistory extends ConsumerWidget {
  final int levelId;
  const _RunHistory({required this.levelId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attempts = ref.watch(drillAttemptsProvider(levelId));
    return attempts.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        final times = list.map((a) => a.secondsTaken.toDouble()).toList();
        final last3 = times.take(3).map((t) => '${t.toStringAsFixed(1)}s').join(', ');
        final best = times.reduce((a, b) => a < b ? a : b);
        final worst = times.reduce((a, b) => a > b ? a : b);
        final avg = times.reduce((a, b) => a + b) / times.length;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Last runs: $last3',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
              Text(
                'Best ${best.toStringAsFixed(1)}s  ·  '
                'Avg ${avg.toStringAsFixed(1)}s  ·  '
                'Worst ${worst.toStringAsFixed(1)}s',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
              ),
            ],
          ),
        );
      },
    );
  }
}
