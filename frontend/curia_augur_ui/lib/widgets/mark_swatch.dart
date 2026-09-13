import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../theme/palette.dart';

/// Builds the fl_chart dot painter for a [ClusterMark], so a series is identified by
/// SHAPE as well as colour (WCAG 2.2 SC 1.4.1 — colour is never the only cue).
FlDotPainter markDotPainter(
  ClusterMark mark,
  Color color, {
  double radius = 4,
}) => switch (mark) {
  ClusterMark.circle => FlDotCirclePainter(color: color, radius: radius),
  ClusterMark.square => FlDotSquarePainter(
    color: color,
    size: radius * 2,
    strokeWidth: 0,
    strokeColor: color,
  ),
  ClusterMark.cross => FlDotCrossPainter(
    color: color,
    size: radius * 2.4,
    width: 2,
  ),
};

/// The same shape drawn as a small legend swatch, so the legend shows the shape the
/// reader is looking for on the chart rather than a colour chip alone.
class MarkSwatch extends StatelessWidget {
  const MarkSwatch({
    super.key,
    required this.mark,
    required this.color,
    this.size = 14,
  });

  final ClusterMark mark;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _MarkPainter(mark, color)),
  );
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.mark, this.color);

  final ClusterMark mark;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..color = color;
    switch (mark) {
      case ClusterMark.circle:
        canvas.drawCircle(center, size.width / 2, paint);
      case ClusterMark.square:
        canvas.drawRect(Offset.zero & size, paint);
      case ClusterMark.cross:
        final stroke = paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5;
        canvas.drawLine(Offset.zero, Offset(size.width, size.height), stroke);
        canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), stroke);
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.mark != mark || old.color != color;
}

/// A legend entry: shape swatch + text label, laid out inline.
class MarkLegend extends StatelessWidget {
  const MarkLegend({
    super.key,
    required this.mark,
    required this.color,
    required this.label,
  });

  final ClusterMark mark;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label, shown as a ${clusterMarkName(mark)}',
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MarkSwatch(mark: mark, color: color),
        const SizedBox(width: 6),
        Text(label),
      ],
    ),
  );
}
