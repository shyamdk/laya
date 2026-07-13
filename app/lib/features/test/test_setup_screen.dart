import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/entities.dart';
import '../practice/question_card.dart';

class TestSetupScreen extends ConsumerStatefulWidget {
  const TestSetupScreen({super.key});

  @override
  ConsumerState<TestSetupScreen> createState() => _TestSetupScreenState();
}

class _TestSetupScreenState extends ConsumerState<TestSetupScreen> {
  final Set<String> _chapters = {};
  String? _difficulty;
  int _count = 5;

  @override
  Widget build(BuildContext context) {
    final chapters = ref.watch(chaptersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Set up a test')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Chapters', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              chapters.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('$e'),
                data: (list) => Column(
                  children: [
                    for (final c in list)
                      CheckboxListTile(
                        dense: true,
                        title: Text('${c.number}. ${c.title}'),
                        value: _chapters.contains(c.code),
                        onChanged: (v) => setState(() => v == true
                            ? _chapters.add(c.code)
                            : _chapters.remove(c.code)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text('Difficulty', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final d in [null, 'easy', 'medium', 'hard', 'challenge'])
                    ChoiceChip(
                      label: Text(d == null ? 'Any' : d[0].toUpperCase() + d.substring(1)),
                      selected: _difficulty == d,
                      onSelected: (_) => setState(() => _difficulty = d),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'The countdown for each question comes from the marks it carried in the '
                'real paper: 1 mark = 60s, 2 = 2 min, 3 = 3½ min, 4 = 5 min.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              Text('Number of questions: $_count',
                  style: Theme.of(context).textTheme.titleSmall),
              Slider(
                value: _count.toDouble(),
                min: 3,
                max: 20,
                divisions: 17,
                label: '$_count',
                onChanged: (v) => setState(() => _count = v.round()),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _chapters.isEmpty
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => TestRunScreen(
                            chapters: _chapters.toList(),
                            difficulty: _difficulty,
                            count: _count,
                          ),
                        )),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start test'),
              ),
              if (_chapters.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Pick at least one chapter.',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class TestRunScreen extends ConsumerStatefulWidget {
  final List<String> chapters;
  final String? difficulty;
  final int count;

  const TestRunScreen({
    super.key,
    required this.chapters,
    required this.difficulty,
    required this.count,
  });

  @override
  ConsumerState<TestRunScreen> createState() => _TestRunScreenState();
}

class _TestRunScreenState extends ConsumerState<TestRunScreen> {
  List<Question>? _qs;
  int _i = 0;
  int _score = 0;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final qs = await ref.read(contentRepoProvider).testQuestions(
            chapterCodes: widget.chapters,
            difficulty: widget.difficulty,
            limit: widget.count,
          );
      if (mounted) setState(() => _qs = qs);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _answered(bool correct, String? given, int secs, bool timedOut) async {
    await ref.read(learningRepoProvider).recordAttempt(
          questionId: _qs![_i].id,
          mode: 'test',
          isCorrect: correct,
          answerGiven: given,
          secondsTaken: secs,
          timedOut: timedOut,
        );
    ref.invalidate(masteryProvider);
    ref.invalidate(dueTodayProvider);
    if (!mounted) return;
    setState(() {
      if (correct) _score++;
      if (_i + 1 < _qs!.length) {
        _i++;
      } else {
        _done = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
          appBar: AppBar(), body: Center(child: Text('Could not load: $_error')));
    }
    if (_qs == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_qs!.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Test')),
        body: const Center(child: Text('No questions match that combination.')),
      );
    }

    if (_done) {
      final pct = (_score / _qs!.length * 100).round();
      return Scaffold(
        appBar: AppBar(title: const Text('Test complete')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(pct >= 60 ? Icons.emoji_events : Icons.replay,
                  size: 64,
                  color: pct >= 60 ? Colors.amber.shade700 : Colors.blueGrey),
              const SizedBox(height: 12),
              Text('$_score / ${_qs!.length}',
                  style: const TextStyle(
                      fontSize: 40, fontWeight: FontWeight.bold)),
              Text('$pct%', style: TextStyle(color: Colors.grey.shade600)),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                child: const Text('Back to home'),
              ),
            ],
          ),
        ),
      );
    }

    final skills = ref.watch(skillsProvider).value;
    final q = _qs![_i];

    return Scaffold(
      appBar: AppBar(
        title: Text('Question ${_i + 1} of ${_qs!.length}'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: LinearProgressIndicator(value: (_i + 1) / _qs!.length),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            children: [
              QuestionCard(
                key: ValueKey(q.id),
                question: q,
                skill: skills?.where((s) => s.id == q.skillId).firstOrNull,
                timed: true,
                onAnswered: _answered,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
