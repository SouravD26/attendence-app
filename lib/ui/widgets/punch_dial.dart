import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The hero element: a progress ring around the live worked-hours readout.
class PunchDial extends StatelessWidget {
  const PunchDial({
    super.key,
    required this.progress,
    required this.label,
    required this.caption,
    required this.active,
  });

  /// 0..1 of the expected shift completed.
  final double progress;

  /// Big centre text, e.g. "06:12:40".
  final String label;

  /// Small text under it, e.g. "since 09:28 AM".
  final String caption;

  /// Checked in — drives the accent colour.
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = active ? scheme.primary : scheme.outline;

    return SizedBox(
      width: 232,
      height: 232,
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        tween: Tween(begin: 0, end: progress),
        builder: (context, value, _) => CustomPaint(
          painter: _DialPainter(
            progress: value,
            track: scheme.outlineVariant.withValues(alpha: 0.5),
            accent: accent,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  caption,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
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

class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.progress,
    required this.track,
    required this.accent,
  });

  final double progress;
  final Color track;
  final Color accent;

  static const _start = -math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 14.0;
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2 + 4);

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;

    canvas.drawArc(arc, _start, math.pi * 2, false, trackPaint);

    if (progress <= 0) return;

    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: _start,
        endAngle: _start + math.pi * 2,
        colors: [accent.withValues(alpha: 0.55), accent],
      ).createShader(arc);

    canvas.drawArc(arc, _start, math.pi * 2 * progress, false, progressPaint);
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.progress != progress || old.accent != accent;
}
