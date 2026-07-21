import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/drill_gen.dart';
import '../../domain/entities.dart';

const _kProblemsPerSheet = 20;

String _normalize(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

/// One timed worksheet: 20 problems generated on the spot, one running
/// stopwatch, self-checked against the mastery gate in Postgres — the client
/// never decides pass/fail (ADR-008 applies to a stopwatch too).
class DrillWorksheetScreen extends ConsumerStatefulWidget {
  final DrillLevel level;
  final String strandCode;
  const DrillWorksheetScreen({super.key, required this.level, required this.strandCode});

  @override
  ConsumerState<DrillWorksheetScreen> createState() => _DrillWorksheetScreenState();
}

class _DrillWorksheetScreenState extends ConsumerState<DrillWorksheetScreen> {
  late final List<DrillProblem> _problems =
      buildSheet(widget.level.gen, _kProblemsPerSheet, Random());
  late final List<TextEditingController> _ctrls =
      List.generate(_problems.length, (_) => TextEditingController());
  final _stopwatch = Stopwatch()..start();
  Timer? _ticker;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _stopwatch.stop();
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    _stopwatch.stop();
    _ticker?.cancel();

    var correct = 0;
    for (var i = 0; i < _problems.length; i++) {
      if (_normalize(_ctrls[i].text) == _normalize(_problems[i].answer)) correct++;
    }
    final seconds = _stopwatch.elapsedMilliseconds / 1000.0;

    try {
      final result = await ref.read(drillRepoProvider).recordAttempt(
            levelId: widget.level.id,
            total: _problems.length,
            correct: correct,
            secondsTaken: seconds,
          );
      ref.invalidate(drillProgressProvider(widget.strandCode));
      ref.invalidate(drillAttemptsProvider(widget.level.id));
      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ResultDialog(
          correct: correct,
          total: _problems.length,
          seconds: seconds,
          result: result,
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _stopwatch.start();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save that attempt: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = _stopwatch.elapsed;
    final m = (elapsed.inSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (elapsed.inSeconds % 60).toString().padLeft(2, '0');

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.level.title),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Center(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.timer_outlined, size: 18),
                const SizedBox(width: 6),
                Text('$m:$s',
                    style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()],
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    )),
              ]),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _problems.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 26,
                          child: Text('${i + 1}.',
                              style: TextStyle(color: Colors.grey.shade600)),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(_problems[i].stem,
                              style: const TextStyle(fontSize: 17)),
                        ),
                        SizedBox(
                          width: 100,
                          child: TextField(
                            controller: _ctrls[i],
                            enabled: !_submitting,
                            textAlign: TextAlign.center,
                            keyboardType: const TextInputType.numberWithOptions(),
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (_) {
                              if (i + 1 < _ctrls.length) {
                                FocusScope.of(context).nextFocus();
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Submit worksheet'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultDialog extends StatelessWidget {
  final int correct;
  final int total;
  final double seconds;
  final DrillAttemptResult result;
  const _ResultDialog({
    required this.correct,
    required this.total,
    required this.seconds,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    final isFirst = result.isFirst;
    final color = result.mastered
        ? Colors.green
        : result.passed
            ? Colors.teal
            : Colors.blueGrey;

    return AlertDialog(
      icon: Icon(
        result.mastered ? Icons.emoji_events : (result.passed ? Icons.check_circle : Icons.timer_outlined),
        color: color,
        size: 40,
      ),
      title: Text(
        result.mastered
            ? 'Level mastered!'
            : isFirst
                ? 'Baseline set'
                : result.passed
                    ? 'Nice — that\'s a pass'
                    : 'Keep going',
        textAlign: TextAlign.center,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$correct / $total correct  ·  ${seconds.toStringAsFixed(1)}s',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 10),
          if (isFirst)
            const Text(
              'This worksheet sets your baseline time. Beat 85% of it with 18+/20 '
              'correct, twice in a row, to master this level.',
              textAlign: TextAlign.center,
            )
          else ...[
            Text('Target: under ${result.targetSeconds.toStringAsFixed(1)}s with 18+/20 correct',
                textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              result.mastered
                  ? 'Two good worksheets in a row — the next level just unlocked.'
                  : result.passed
                      ? 'Pass ${result.consecutivePasses} of 2 needed to master this level.'
                      : 'Not quite this time — redo the whole worksheet, don\'t just fix the misses.',
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back to levels'),
        ),
      ],
    );
  }
}
