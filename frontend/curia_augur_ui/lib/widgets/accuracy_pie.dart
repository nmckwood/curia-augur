import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/analysis.dart';

/// Pie chart of prediction accuracy (REQUIREMENTS_3 UI-3): percentage of constituencies
/// whose predicted change matched the actual outcome.
class AccuracyPie extends StatelessWidget {
  const AccuracyPie({super.key, required this.analysis, this.perYear = false});

  final Analysis analysis;
  final bool perYear; // show the per-year best-indices model instead of common

  static const Color _correct = Color(0xFF2E7D32); // green
  static const Color _incorrect = Color(0xFFC62828); // red

  @override
  Widget build(BuildContext context) {
    final pred = analysis.prediction;
    final acc = perYear
        ? (pred?.perYearHoldoutAccuracy ?? 0)
        : analysis.accuracy; // held-out where available
    final total = pred?.testSize ?? analysis.constituencies.length;
    final correctPct = acc * 100;
    final incorrectPct = 100 - correctPct;
    final correct = (acc * total).round();
    final scope = pred != null ? 'held-out' : 'in-sample';
    final label = perYear ? 'Per-year best indices' : 'Common indices';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Prediction accuracy',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('$label: ${correctPct.toStringAsFixed(1)}% correct '
            '($correct / $total $scope)'),
        if (pred != null)
          Text(
            'Baseline (predict "no change"): '
            '${(pred.baselineAccuracy * 100).toStringAsFixed(1)}%',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 40,
              sections: [
                PieChartSectionData(
                  value: correctPct,
                  color: _correct,
                  title: '${correctPct.toStringAsFixed(0)}%',
                  radius: 60,
                  titleStyle: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
                PieChartSectionData(
                  value: incorrectPct,
                  color: _incorrect,
                  title: '${incorrectPct.toStringAsFixed(0)}%',
                  radius: 60,
                  titleStyle: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
        Row(mainAxisSize: MainAxisSize.min, children: [
          _legend(_correct, 'Correct'),
          const SizedBox(width: 12),
          _legend(_incorrect, 'Incorrect'),
        ]),
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
