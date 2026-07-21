import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/entities.dart';
import '../../widgets/math_text.dart';
import '../practice/question_card.dart';

class LearnChapterPicker extends ConsumerWidget {
  const LearnChapterPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subject = ref.watch(currentSubjectProvider);
    final chapters = ref.watch(chaptersProvider(subject?.code ?? 'maths'));
    return Scaffold(
      appBar: AppBar(title: const Text('Learn')),
      body: chapters.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final c in list)
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(child: Text('${c.number}')),
                      title: Text(c.title),
                      subtitle: const Text('Concepts, then practice'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        ref.read(trackingRepoProvider).logAccess(
                            module: 'learn_chapter',
                            subjectCode: subject?.code,
                            chapterCode: c.code);
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => LearnChapterScreen(chapter: c),
                        ));
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LearnChapterScreen extends ConsumerWidget {
  final Chapter chapter;
  const LearnChapterScreen({super.key, required this.chapter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(chapter.title),
          bottom: const TabBar(tabs: [
            Tab(text: 'Concepts', icon: Icon(Icons.menu_book_outlined, size: 18)),
            Tab(text: 'Practice', icon: Icon(Icons.edit_outlined, size: 18)),
          ]),
        ),
        body: TabBarView(children: [
          _Concepts(code: chapter.code),
          _Practice(code: chapter.code),
        ]),
      ),
    );
  }
}

class _Concepts extends ConsumerWidget {
  final String code;
  const _Concepts({required this.code});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(conceptsProvider(code)).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (sections) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: sections.length,
                itemBuilder: (_, i) => _SectionTile(section: sections[i]),
              ),
            ),
          ),
        );
  }
}

class _SectionTile extends StatelessWidget {
  final ConceptSection section;
  const _SectionTile({required this.section});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: MathText('${section.idx}.  ${section.title}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: section.tier == '-' || section.tier.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  TierBadge(section.tier),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(section.why,
                        style: TextStyle(
                            fontSize: 11.5,
                            fontStyle: FontStyle.italic,
                            color: Colors.grey.shade600),
                        overflow: TextOverflow.ellipsis),
                  ),
                ]),
              ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: section.body.map(_block).toList(),
      ),
    );
  }

  Widget _block(Map<String, dynamic> b) {
    final kind = b['kind'] as String;
    final pad = const EdgeInsets.only(bottom: 8);

    switch (kind) {
      case 'p':
        return Padding(
            padding: pad,
            child: MathText(b['text'] as String,
                style: const TextStyle(height: 1.5)));
      case 'key':
        return _box(b['text'] as String, const Color(0xFF1B5E20), 'KEY IDEA');
      case 'warn':
        return _box(b['text'] as String, const Color(0xFFB25E00), '⚠');
      case 'real':
        return _box(b['text'] as String, const Color(0xFF00695C),
            'WHERE YOU ACTUALLY SEE THIS');
      case 'eg':
      case 'steps':
      case 'bullets':
        final lines = (b['lines'] as List).cast<String>();
        return Padding(
          padding: pad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: lines
                .map((l) => Padding(
                      padding: const EdgeInsets.only(left: 10, bottom: 3),
                      child: MathText(
                        kind == 'bullets' ? '•  $l' : l,
                        style: TextStyle(
                          height: 1.45,
                          color: kind == 'eg' ? const Color(0xFF0D47A1) : null,
                        ),
                      ),
                    ))
                .toList(),
          ),
        );
      case 'check':
        final items = (b['items'] as List).cast<Map<String, dynamic>>();
        return Padding(
          padding: pad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                MathText('Q${i + 1}. ${items[i]['q']}'),
                Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 6),
                  child: MathText('→ ${items[i]['a']}',
                      style: const TextStyle(
                          color: Color(0xFF1B5E20),
                          fontStyle: FontStyle.italic,
                          fontSize: 13)),
                ),
              ],
            ],
          ),
        );
      case 'tbl':
        final head = (b['head'] as List).cast<String>();
        final rows = (b['rows'] as List)
            .map((r) => (r as List).cast<String>())
            .toList();
        return Padding(
          padding: pad,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 34,
              dataRowMinHeight: 30,
              dataRowMaxHeight: 38,
              columns: head.map((h) => DataColumn(label: MathText(h))).toList(),
              rows: rows
                  .map((r) => DataRow(
                      cells: r.map((c) => DataCell(MathText(c))).toList()))
                  .toList(),
            ),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _box(String text, Color color, String label) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(6),
          border: Border(left: BorderSide(color: color, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4)),
            const SizedBox(height: 3),
            MathText(text, style: TextStyle(color: color, height: 1.45)),
          ],
        ),
      );
}

/// Adaptive practice: the queue comes from next_questions() — overdue first,
/// then unseen, weighted toward the skills that come up most in real exams.
class _Practice extends ConsumerStatefulWidget {
  final String code;
  const _Practice({required this.code});

  @override
  ConsumerState<_Practice> createState() => _PracticeState();
}

class _PracticeState extends ConsumerState<_Practice> {
  List<Question>? _queue;
  int _i = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final subject = ref.read(currentSubjectProvider);
      final qs = await ref.read(learningRepoProvider).nextQuestions(
            chapterCodes: [widget.code],
            subjectCode: subject?.code,
            limit: 10,
          );
      if (mounted) setState(() {
            _queue = qs;
            _i = 0;
          });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _answered(bool correct, String? given, int secs, bool timedOut) async {
    final q = _queue![_i];
    await ref.read(learningRepoProvider).recordAttempt(
          questionId: q.id,
          mode: 'learn',
          isCorrect: correct,
          answerGiven: given,
          secondsTaken: secs,
        );
    ref.invalidate(masteryProvider);
    ref.invalidate(dueTodayProvider);
    if (!mounted) return;
    if (_i + 1 < _queue!.length) {
      setState(() => _i++);
    } else {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Text('Could not load: $_error'));
    if (_queue == null) return const Center(child: CircularProgressIndicator());
    if (_queue!.isEmpty) {
      return const Center(child: Text('Nothing due. Come back tomorrow!'));
    }

    final skills = ref.watch(skillsProvider).value;
    final q = _queue![_i];

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          key: ValueKey(q.id),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text('Question ${_i + 1} of ${_queue!.length}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            ),
            QuestionCard(
              key: ValueKey(q.id),
              question: q,
              skill: skills?.where((s) => s.id == q.skillId).firstOrNull,
              timed: false,
              onAnswered: _answered,
            ),
          ],
        ),
      ),
    );
  }
}
