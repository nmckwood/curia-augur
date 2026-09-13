import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/analysis.dart';
import '../theme/palette.dart';
import 'info_heading.dart';
import 'mark_swatch.dart';

/// Predicted-vs-actual chart (REQUIREMENTS_3 UI-2): for each constituency (x-axis index),
/// two 0/1 series — predicted change and actual change. Where prediction matches an actual
/// flip, both dots sit at y=1 and overlap. Tooltip shows the details.
/// The home screen plots the cluster prediction (REQUIREMENTS_4 UI-3).
class PredictionScatter extends StatelessWidget {
  const PredictionScatter({
    super.key,
    required this.constituencies,
    this.source = PredictionSource.cluster,
  });

  final List<Constituency> constituencies;
  final PredictionSource source;

  int _predicted(Constituency c) => c.predictionFor(source);

  bool _correct(Constituency c) => c.correctFor(source);

  // WCAG 2.2 SC 1.4.1: the two series differ by SHAPE as well as hue — actual results
  // are circles, predictions are crosses — so they stay separable without colour.
  static const Color _predictedColor = Palette.change; // orange
  static const Color _actual = Palette.noChange; // blue
  static const ClusterMark _actualMark = ClusterMark.circle;
  static const ClusterMark _predictedMark = ClusterMark.cross;

  @override
  Widget build(BuildContext context) {
    // Sort so flips group together, making agreement/disagreement easy to read.
    final items = [...constituencies]
      ..sort((a, b) => b.changeFactor.compareTo(a.changeFactor));

    final spots = <ScatterSpot>[];
    for (var i = 0; i < items.length; i++) {
      final c = items[i];
      // Actual series.
      spots.add(
        ScatterSpot(
          i.toDouble(),
          c.changeFactor.toDouble(),
          dotPainter: markDotPainter(
            _actualMark,
            _actual.withValues(alpha: 0.7),
            radius: 3,
          ),
        ),
      );
      // Predicted series (slightly offset in y so overlaps stay visible).
      final py = _predicted(c).clamp(0, 1).toDouble();
      spots.add(
        ScatterSpot(
          i.toDouble(),
          py + 0.04,
          dotPainter: markDotPainter(
            _predictedMark,
            _predictedColor.withValues(alpha: 0.8),
            radius: 3,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const InfoHeading(
          title: 'Predicted vs actual, authority by authority',
          help:
              'One column per authority, sorted so the ones that actually '
              'changed are on the left. The blue circle is the real result (1 = '
              'majority flipped, 0 = it did not) and the orange cross is the '
              'prediction, nudged up slightly so it stays visible when the two '
              'agree. A column with the marks at different heights is one the '
              'prediction got wrong. Hover a column for the authority name.',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 4),
        const Wrap(
          spacing: 12,
          children: [
            MarkLegend(
              mark: _actualMark,
              color: _actual,
              label: 'Actual change',
            ),
            MarkLegend(
              mark: _predictedMark,
              color: _predictedColor,
              label: 'Predicted change',
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ScatterChart(
            ScatterChartData(
              minY: -0.2,
              maxY: 1.3,
              scatterSpots: spots,
              titlesData: const FlTitlesData(
                leftTitles: AxisTitles(
                  axisNameWidget: Text('changed (0/1)'),
                  sideTitles: SideTitles(showTitles: true, reservedSize: 28),
                ),
                bottomTitles: AxisTitles(
                  axisNameWidget: Text('constituency'),
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              scatterTouchData: ScatterTouchData(
                enabled: true,
                touchTooltipData: ScatterTouchTooltipData(
                  getTooltipItems: (spot) {
                    final idx = spot.x.round();
                    final c = idx >= 0 && idx < items.length
                        ? items[idx]
                        : null;
                    if (c == null) return null;
                    return ScatterTooltipItem(
                      '${c.name}\n'
                      'Actual: ${c.changeFactor == 1 ? 'changed' : 'no change'}\n'
                      'Predicted: ${_predicted(c) == 1 ? 'change' : 'no change'}\n'
                      '${_correct(c) ? 'correct' : 'incorrect'}',
                      textStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
