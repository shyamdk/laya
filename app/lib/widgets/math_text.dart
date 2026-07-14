import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

/// Renders our content strings: plain text with `$...$` maths spans.
///
/// The bank uses 213 superscripts, 18 square roots, 10 cube roots and 56
/// fractions, so the maths has to be real LaTeX — Unicode cannot stack a
/// fraction or draw a radical bar (ADR-013).
///
/// Every span in the seed data is validated against KaTeX at build time
/// (content/tools/validate_latex.mjs), but if one ever fails to parse we show
/// the raw LaTeX rather than crashing the screen.
class MathText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign textAlign;

  const MathText(this.text, {super.key, this.style, this.textAlign = TextAlign.start});

  /// Kannada codepoints (U+0C80..U+0CFF). Flutter's default font has none of
  /// these glyphs, so any string containing them must be drawn in
  /// NotoSansKannada or it renders as tofu boxes.
  static final _kannada = RegExp(r'[\u0C80-\u0CFF]');
  static bool hasKannada(String s) => _kannada.hasMatch(s);

  @override
  Widget build(BuildContext context) {
    var base = style ?? DefaultTextStyle.of(context).style;
    if (hasKannada(text)) base = base.copyWith(fontFamily: 'NotoSansKannada');
    final spans = <InlineSpan>[];

    // Split on $...$, keeping the delimiters out of the payload.
    final re = RegExp(r'\$([^$]+)\$');
    var cursor = 0;

    for (final m in re.allMatches(text)) {
      if (m.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, m.start), style: base));
      }
      final tex = m.group(1)!;
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Math.tex(
            tex,
            textStyle: base,
            mathStyle: MathStyle.text,
            onErrorFallback: (err) => Text(
              tex,
              style: base.copyWith(
                fontFamily: 'monospace',
                backgroundColor: Colors.red.withValues(alpha: 0.12),
              ),
            ),
          ),
        ),
      );
      cursor = m.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: base));
    }

    return RichText(
      text: TextSpan(children: spans, style: base),
      textAlign: textAlign,
    );
  }
}

/// The ***/**/* frequency badge. Not decoration — it tells Laya where the marks
/// actually are, counted from 17 real papers.
class TierBadge extends StatelessWidget {
  final String tier;
  final bool compact;

  const TierBadge(this.tier, {super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    if (tier.isEmpty || tier == '-') return const SizedBox.shrink();

    // 'BASICS' marks a foundation section — not examined directly, but everything
    // else rests on it. It is not a frequency tier, so it gets its own label.
    final (color, label) = switch (tier) {
      '***' => (const Color(0xFFC62828), 'MUST KNOW'),
      '**' => (const Color(0xFFB25E00), 'IMPORTANT'),
      '*' => (const Color(0xFF6B7280), 'SEEN SOMETIMES'),
      'BASICS' => (const Color(0xFF0D47A1), 'FOUNDATION'),
      _ => (const Color(0xFF6B7280), ''),
    };
    final text = tier == 'BASICS'
        ? label
        : compact
            ? tier
            : '$tier  $label';

    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: compact ? 11 : 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
