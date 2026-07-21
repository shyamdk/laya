import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/drill_gen.dart';
import '../../domain/entities.dart';

const _kRoundSize = 5;
const _kCapSecondsPerProblem = 12; // generous — this is placement, not mastery timing

String _normalize(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

/// Quick placement diagnostic: binary-searches the strand's ladder with short
/// 5-problem rounds so a student starts at the level where her fluency
/// actually breaks, not at the bottom of everything — same idea Kumon uses
/// to place a student regardless of school grade.
class DrillPlacementScreen extends ConsumerStatefulWidget {
  final DrillStrand strand;
  final List<DrillLevel> levels;
  const DrillPlacementScreen({super.key, required this.strand, required this.levels});

  @override
  ConsumerState<DrillPlacementScreen> createState() => _DrillPlacementScreenState();
}

class _DrillPlacementScreenState extends ConsumerState<DrillPlacementScreen> {
  late final List<DrillLevel> _sorted = List.of(widget.levels)
    ..sort((a, b) => a.seq.compareTo(b.seq));
  late int _lo = 0;
  late int _hi = _sorted.length - 1;
  int _bestIndex = -1;
  late int _mid;

  List<DrillProblem> _problems = [];
  List<TextEditingController> _ctrls = [];
  Stopwatch _sw = Stopwatch();
  bool _finished = false;
  bool _saving = false;
  DrillLevel? _landing;

  @override
  void initState() {
    super.initState();
    _mid = (_lo + _hi) ~/ 2;
    _newRound();
  }

  void _newRound() {
    for (final c in _ctrls) {
      c.dispose();
    }
    _problems = buildSheet(_sorted[_mid].gen, _kRoundSize, Random());
    _ctrls = List.generate(_problems.length, (_) => TextEditingController());
    _sw = Stopwatch()..start();
  }

  Future<void> _submitRound() async {
    _sw.stop();
    var correct = 0;
    for (var i = 0; i < _problems.length; i++) {
      if (_normalize(_ctrls[i].text) == _normalize(_problems[i].answer)) correct++;
    }
    final passed = correct >= 4 && _sw.elapsed.inSeconds <= _kRoundSize * _kCapSecondsPerProblem;

    if (passed) {
      _bestIndex = _mid;
      _lo = _mid + 1;
    } else {
      _hi = _mid - 1;
    }

    if (_lo > _hi) {
      final landingIndex = _bestIndex + 1 < _sorted.length ? _bestIndex + 1 : _sorted.length - 1;
      _landing = _sorted[landingIndex];
      setState(() => _saving = true);
      try {
        await ref
            .read(drillRepoProvider)
            .setPlacement(strandCode: widget.strand.code, levelCode: _landing!.code);
        ref.invalidate(drillProgressProvider(widget.strand.code));
        setState(() {
          _finished = true;
          _saving = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save placement: $e')));
      }
      return;
    }

    setState(() {
      _mid = (_lo + _hi) ~/ 2;
      _newRound();
    });
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Placement · ${widget.strand.name}')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: _finished ? _buildDone(context) : _buildRound(context),
        ),
      ),
    );
  }

  Widget _buildDone(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.flag_circle, size: 56, color: Colors.indigo),
          const SizedBox(height: 16),
          Text('Starting you at ${_landing!.code}',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(_landing!.title, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 8),
          Text(
            _bestIndex >= 0
                ? 'Levels before this are marked mastered — you\'re already fast and accurate there.'
                : 'Starting from the very first level in this strand.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Go to the ladder'),
          ),
        ],
      ),
    );
  }

  Widget _buildRound(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Trying: ${_sorted[_mid].title}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Answer these ${_problems.length} — work at a normal pace.',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _problems.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(_problems[i].stem, style: const TextStyle(fontSize: 18)),
                  ),
                  SizedBox(
                    width: 100,
                    child: TextField(
                      controller: _ctrls[i],
                      enabled: !_saving,
                      textAlign: TextAlign.center,
                      keyboardType: const TextInputType.numberWithOptions(),
                      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
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
              onPressed: _saving ? null : _submitRound,
              child: _saving
                  ? const SizedBox(
                      height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Next'),
            ),
          ),
        ),
      ],
    );
  }
}
