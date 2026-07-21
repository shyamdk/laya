import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/entities.dart';

/// Who opened what, and when — visible only to the parent/admin account.
/// The database enforces that (admin_activity_log() raises for anyone
/// else); this screen doesn't re-check, it just shows whatever comes back.
class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(activityLogProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: activity.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Could not load activity: $e')),
            data: (rows) {
              if (rows.isEmpty) {
                return const Center(child: Text('No activity recorded yet.'));
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) => _Row(entry: rows[i]),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final AccessLogEntry entry;
  const _Row({required this.entry});

  @override
  Widget build(BuildContext context) {
    final t = entry.createdAt.toLocal();
    final ts = '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2, right: 10),
            child: Icon(Icons.circle, size: 8, color: Colors.indigo),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.label,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                const SizedBox(height: 2),
                Text('${entry.displayName} · ${entry.userEmail}',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
              ],
            ),
          ),
          Text(ts, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}
