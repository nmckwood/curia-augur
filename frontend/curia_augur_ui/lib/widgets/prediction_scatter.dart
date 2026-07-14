import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/analysis.dart';

/// Predicted-vs-actual chart (REQUIREMENTS_3 UI-2): for each constituency (x-axis index),
/// two 0/1 series — predicted change and actual change. Where prediction matches an actual
/// flip, both dots sit at y=1 and overlap. Tooltip shows the details.
class PredictionScatter extends StatelessWidget {
  const PredictionScatter({
    super.key,
    required this.constituencies,
    this.perYear = false,
  });

  final List<Constituency> constituencies;
  final bool perYear; // use the per-year best-indices prediction instead of common

  int _predicted(Constituency c) =>
      perYear ? c.predictedChangePerYear : c.predictedChange;

  bool _correct(Constituency c) =>
      perYear ? c.perYearPredictionCorrect : c.predictionCorrect;

  static const Color _predictedColor = Color(0xFF1565C0); // blue
  static const Color _actual = Color(0xFFEF6C00); // orange

  @override
  Widget build(BuildContext context) {
    // Sort so flips group together, making agreement/disagreement easy to read.
    final items = [...constituencies]
      ..sort((a, b) => b.changeFactor.compareTo(a.changeFactor));

    final spots = <ScatterSpot>[];
    for (var i = 0; i < items.length; i++) {
      final c = items[i];
      // Actual series.
      spots.add(ScatterSpot(i.toDouble(), c.changeFactor.toDouble(),
          dotPainter: FlDotCirclePainter(
              color: _actual.withValues(alpha: 0.6), radius: 3)));
      // Predicted series (slightly offset in y so overlaps stay visible).
      final py = _predicted(c).clamp(0, 1).toDouble();
      spots.add(ScatterSpot(i.toDouble(), py + 0.04,
          dotPainter: FlDotCirclePainter(
              color: _predictedColor.withValues(alpha: 0.6), radius: 3)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 12, children: [
          _legend(_actual, 'Actual change'),
          _legend(_predictedColor, 'Predicted change'),
        ]),
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
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              scatterTouchData: ScatterTouchData(
                enabled: true,
                touchTooltipData: ScatterTouchTooltipData(
                  getTooltipItems: (spot) {
                    final idx = spot.x.round();
                    final c = idx >= 0 && idx < items.length ? items[idx] : null;
                    if (c == null) return null;
                    return ScatterTooltipItem(
                      '${c.name}\n'
                      'Actual: ${c.changeFactor == 1 ? 'changed' : 'no change'}\n'
                      'Predicted: ${_predicted(c) == 1 ? 'change' : 'no change'}\n'
                      '${_correct(c) ? 'correct' : 'incorrect'}',
                      textStyle:
                          const TextStyle(color: Colors.white, fontSize: 12),
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

  Widget _legend(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 12, height: 12, color: color),
          const SizedBox(width: 4),
          Text(label),
        ],
      );
}
