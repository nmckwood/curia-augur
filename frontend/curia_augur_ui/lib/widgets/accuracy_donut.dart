import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../theme/palette.dart';
import 'info_heading.dart';

/// A correct/incorrect donut with a heading, a headline count line and any number of
/// supporting notes. Shared by the model accuracy pie and the no-ML baseline pie so the
/// two sit side by side on the same scale and read as one comparison.
///
/// WCAG 2.2 SC 1.4.1: the slices are blue/orange rather than green/red, each slice is
/// labelled in words AND as a percentage inside the slice itself, and the headline line
/// states the same numbers as text — so nothing here needs colour to be read.
class AccuracyDonut extends StatelessWidget {
  const AccuracyDonut({
    super.key,
    required this.title,
    required this.help,
    required this.headline,
    required this.accuracy,
    this.notes = const [],
  });

  final String title;
  final String help;
  final String headline;
  final double accuracy; // 0..1
  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    final correctPct = accuracy * 100;
    final incorrectPct = 100 - correctPct;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoHeading(title: title, help: help),
        const SizedBox(height: 4),
        Text(headline),
        ...notes.map(
          (n) => Text(
            n,
            style: const TextStyle(fontSize: 12, color: Palette.mutedInk),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 40,
              sections: [
                _section('Correct', correctPct, Palette.correct),
                _section('Incorrect', incorrectPct, Palette.incorrect),
              ],
            ),
          ),
        ),
        // Wrap, not Row: in a narrow column (the per-year page puts this pie beside a
        // scatter) the two legend entries do not fit on one line.
        Wrap(
          spacing: 12,
          children: [
            _legend(Palette.correct, 'Correct'),
            _legend(Palette.incorrect, 'Incorrect'),
          ],
        ),
      ],
    );
  }

  /// Slices carry their own word label as well as the percentage, so the donut is
  /// readable with the colours removed entirely.
  PieChartSectionData _section(String label, double value, Color color) =>
      PieChartSectionData(
        value: value,
        color: color,
        title: '$label\n${value.toStringAsFixed(0)}%',
        radius: 60,
        titleStyle: const TextStyle(
          color: Palette.onFillInk,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      );

  Widget _legend(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 12, height: 12, color: color),
      const SizedBox(width: 4),
      Text(label),
    ],
  );
}
