import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/entities.dart';
import '../../widgets/math_text.dart';

/// One question, used by both Learn and Test mode.
///
/// Learn mode: untimed, worked solution one tap away.
/// Test mode: countdown (from the paper's own mark allocation), solution hidden
/// until answered.
class QuestionCard extends ConsumerStatefulWidget {
  final Question question;
  final Skill? skill;
  final bool timed;
  final bool showSolutionButton;
  final void Function(bool isCorrect, String? given, int seconds, bool timedOut) onAnswered;

  const QuestionCard({
    super.key,
    required this.question,
    required this.skill,
    required this.timed,
    required this.onAnswered,
    this.showSolutionButton = true,
  });

  @override
  ConsumerState<QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends ConsumerState<QuestionCard> {
  int? _picked;
  bool _answered = false;
  bool _revealed = false;
  bool _showSolution = false;
  final _textCtrl = TextEditingController();
  final _stopwatch = Stopwatch()..start();

  @override
  void dispose() {
    _textCtrl.dispose();
    _stopwatch.stop();
    super.dispose();
  }

  void _submit({bool timedOut = false}) {
    if (_answered) return;
    final q = widget.question;

    // Only MCQs can be auto-graded. For written answers Laya self-marks against
    // the worked solution — we never let the AI decide correctness (ADR-008).
    final bool correct;
    String? given;
    if (q.isMcq) {
      correct = _picked != null && _picked == q.correctOption;
      given = _picked == null ? null : String.fromCharCode(97 + _picked!);
    } else {
      correct = false; // provisional; self-marked in the reveal step below
      given = _textCtrl.text.trim().isEmpty ? null : _textCtrl.text.trim();
    }

    setState(() {
      _answered = true;
      _revealed = true;
      _showSolution = true;
    });

    if (q.isMcq || timedOut) {
      widget.onAnswered(correct, given, _stopwatch.elapsed.inSeconds, timedOut);
    }
  }

  void _selfMark(bool gotIt) {
    widget.onAnswered(gotIt, _textCtrl.text.trim(), _stopwatch.elapsed.inSeconds, false);
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (widget.skill != null) TierBadge(widget.skill!.tier, compact: true),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${widget.skill?.name ?? ''}  ·  ${q.sourceExam}  ·  ${q.marks} mark${q.marks > 1 ? 's' : ''}',
                    style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey.shade600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.timed && !_answered)
                  _Countdown(
                    seconds: q.timerSeconds,
                    onExpired: () => _submit(timedOut: true),
                  ),
              ],
            ),
            const Divider(height: 22),

            // Kannada questions ask in English and show the Kannada below, so
            // Laya always knows WHAT is being asked even if the word is new.
            if (q.stemEn != null && q.stemEn!.isNotEmpty)
              Text(q.stemEn!,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: Colors.grey.shade700)),
            if (q.stemLatex.isNotEmpty) ...[
              if (q.stemEn != null && q.stemEn!.isNotEmpty) const SizedBox(height: 8),
              MathText(q.stemLatex,
                  style: (theme.textTheme.titleMedium ?? const TextStyle())
                      .copyWith(fontSize: MathText.hasKannada(q.stemLatex) ? 22 : null)),
            ],
            const SizedBox(height: 16),

            if (q.isMatch)
              _MatchGrid(
                pairs: q.matchPairs,
                answered: _answered,
                onDone: (correct) {
                  if (_answered) return;
                  setState(() {
                    _answered = true;
                    _revealed = true;
                    _showSolution = true;
                  });
                  widget.onAnswered(correct, null, _stopwatch.elapsed.inSeconds, false);
                },
              )
            else if (q.isMcq)
              ...List.generate(q.optionsLatex.length, (i) {
                final isCorrect = i == q.correctOption;
                Color? bg;
                if (_revealed) {
                  if (isCorrect) bg = Colors.green.withValues(alpha: 0.15);
                  else if (i == _picked) bg = Colors.red.withValues(alpha: 0.12);
                }
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: RadioListTile<int>(
                    value: i,
                    groupValue: _picked,
                    onChanged: _answered ? null : (v) => setState(() => _picked = v),
                    title: MathText('(${String.fromCharCode(97 + i)})  ${q.optionsLatex[i]}'),
                    dense: true,
                  ),
                );
              })
            else
              TextField(
                controller: _textCtrl,
                enabled: !_answered,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Your answer (work it out on paper first)',
                  border: OutlineInputBorder(),
                ),
              ),

            const SizedBox(height: 14),

            if (!_answered && !q.isMatch)
              FilledButton(
                onPressed: _submit,
                child: Text(q.isMcq ? 'Check answer' : 'Reveal answer'),
              ),

            // Written answers: Laya marks herself against the real answer.
            if (_answered && !q.isMcq && !q.isMatch) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: MathText(q.answerLatex,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: const Color(0xFF1B5E20))),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _selfMark(false),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('I got it wrong'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _selfMark(true),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('I got it right'),
                  ),
                ),
              ]),
            ],

            if (_answered && q.isMcq)
              Row(children: [
                Icon(
                  _picked == q.correctOption ? Icons.check_circle : Icons.cancel,
                  color: _picked == q.correctOption ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  _picked == q.correctOption ? 'Correct' : 'Not quite',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _picked == q.correctOption ? Colors.green : Colors.red,
                  ),
                ),
              ]),

            if (_showSolution && q.explainEn != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: MathText(q.explainEn!,
                    style: const TextStyle(color: Color(0xFF1B5E20), height: 1.45)),
              ),
            ],

            if (_showSolution && widget.showSolutionButton && q.explainEn == null) ...[
              const SizedBox(height: 12),
              _Solution(questionId: q.id),
              const SizedBox(height: 8),
              _AiExplain(question: q),
            ],
          ],
        ),
      ),
    );
  }
}

class _Countdown extends StatefulWidget {
  final int seconds;
  final VoidCallback onExpired;
  const _Countdown({required this.seconds, required this.onExpired});

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  late int _left = widget.seconds;
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    _tick();
  }

  Future<void> _tick() async {
    while (mounted && _left > 0) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      setState(() => _left--);
    }
    if (mounted && !_fired) {
      _fired = true;
      widget.onExpired();
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = (_left ~/ 60).toString().padLeft(2, '0');
    final s = (_left % 60).toString().padLeft(2, '0');
    final danger = _left <= 15;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: (danger ? Colors.red : Colors.blueGrey).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.timer_outlined,
            size: 15, color: danger ? Colors.red : Colors.blueGrey),
        const SizedBox(width: 4),
        Text('$m:$s',
            style: TextStyle(
              fontFeatures: const [FontFeature.tabularFigures()],
              fontWeight: FontWeight.bold,
              color: danger ? Colors.red : Colors.blueGrey.shade700,
            )),
      ]),
    );
  }
}

class _Solution extends ConsumerWidget {
  final int questionId;
  const _Solution({required this.questionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ExpansionTile(
      title: const Text('Step-by-step solution',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(left: 8, bottom: 8),
      children: [
        ref.watch(solutionProvider(questionId)).when(
              loading: () => const Padding(
                padding: EdgeInsets.all(8),
                child: LinearProgressIndicator(),
              ),
              error: (e, _) => Text('Could not load the solution: $e'),
              data: (steps) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: steps.map((s) {
                  final isAnswer = s.startsWith('Answer:');
                  final isWarn = s.trimLeft().startsWith('⚠');
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: MathText(
                      s,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.45,
                        fontWeight: isAnswer ? FontWeight.bold : FontWeight.normal,
                        color: isAnswer
                            ? const Color(0xFF1B5E20)
                            : isWarn
                                ? const Color(0xFFB25E00)
                                : null,
                        fontStyle: isWarn ? FontStyle.italic : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
      ],
    );
  }
}

/// "Explain this differently" — the AI re-explains a question whose answer we
/// already know and have verified. It is never asked to decide correctness.
class _AiExplain extends ConsumerStatefulWidget {
  final Question question;
  const _AiExplain({required this.question});

  @override
  ConsumerState<_AiExplain> createState() => _AiExplainState();
}

class _AiExplainState extends ConsumerState<_AiExplain> {
  String? _explanation;
  bool _loading = false;
  String? _error;

  Future<void> _ask() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final text = await ref.read(aiRepoProvider).explain(
            questionLatex: widget.question.stemLatex,
            answerLatex: widget.question.answerLatex,
          );
      if (mounted) setState(() => _explanation = text);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: _loading ? null : _ask,
          icon: _loading
              ? const SizedBox(
                  width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.auto_awesome, size: 16),
          label: Text(_loading ? 'Thinking…' : 'Explain this differently'),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('AI unavailable: $_error',
                style: const TextStyle(color: Colors.red, fontSize: 12)),
          ),
        if (_explanation != null)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.deepPurple.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.2)),
            ),
            child: MathText(_explanation!, style: const TextStyle(fontSize: 13.5, height: 1.5)),
          ),
      ],
    );
  }
}

/// Tap-to-match: tap a word on the left, then its meaning on the right.
/// Deliberately no typing — Laya has no Kannada keyboard.
class _MatchGrid extends StatefulWidget {
  final List<({String left, String right})> pairs;
  final bool answered;
  final void Function(bool allCorrect) onDone;

  const _MatchGrid({
    required this.pairs,
    required this.answered,
    required this.onDone,
  });

  @override
  State<_MatchGrid> createState() => _MatchGridState();
}

class _MatchGridState extends State<_MatchGrid> {
  late final List<String> _rights =
      widget.pairs.map((p) => p.right).toList()..shuffle();
  final Map<String, String> _picked = {};   // left -> right chosen
  String? _selectedLeft;
  bool _wrongOnce = false;

  void _tapLeft(String l) {
    if (widget.answered || _picked.containsKey(l)) return;
    setState(() => _selectedLeft = l);
  }

  void _tapRight(String r) {
    if (widget.answered || _selectedLeft == null) return;
    if (_picked.containsValue(r)) return;

    final correct = widget.pairs.firstWhere((p) => p.left == _selectedLeft!).right == r;
    setState(() {
      _picked[_selectedLeft!] = r;
      if (!correct) _wrongOnce = true;
      _selectedLeft = null;
    });

    if (_picked.length == widget.pairs.length) {
      // Graded here in the client only to decide right/wrong for THIS widget;
      // the score itself is still recorded by record_attempt() in Postgres.
      widget.onDone(!_wrongOnce);
    }
  }

  bool _isRight(String l) =>
      widget.pairs.firstWhere((p) => p.left == l).right == _picked[l];

  @override
  Widget build(BuildContext context) {
    Color? tint(String l) {
      if (!_picked.containsKey(l)) return null;
      return (_isRight(l) ? Colors.green : Colors.red).withValues(alpha: 0.15);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            children: widget.pairs.map((p) {
              final sel = _selectedLeft == p.left;
              return _chip(
                p.left,
                onTap: () => _tapLeft(p.left),
                bg: tint(p.left) ??
                    (sel ? Theme.of(context).colorScheme.primaryContainer : null),
                border: sel,
                trailing: _picked.containsKey(p.left)
                    ? Icon(_isRight(p.left) ? Icons.check : Icons.close,
                        size: 16,
                        color: _isRight(p.left) ? Colors.green : Colors.red)
                    : null,
              );
            }).toList(),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            children: _rights.map((r) {
              final used = _picked.containsValue(r);
              return _chip(
                r,
                onTap: () => _tapRight(r),
                bg: used ? Colors.grey.withValues(alpha: 0.12) : null,
                faded: used,
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _chip(String text,
      {required VoidCallback onTap,
      Color? bg,
      bool border = false,
      bool faded = false,
      Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: border ? Theme.of(context).colorScheme.primary : Colors.grey.shade300,
              width: border ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Opacity(
                  opacity: faded ? 0.4 : 1,
                  child: MathText(text, style: const TextStyle(fontSize: 15)),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      ),
    );
  }
}
