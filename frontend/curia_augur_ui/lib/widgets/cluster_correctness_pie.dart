import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/analysis.dart';
import '../theme/palette.dart';

/// Cluster correctness pie chart (REQUIREMENTS_5 Widget 2 Row B):
/// Shows the distribution of correct vs incorrect cluster predictions.
class ClusterCorrectnessPie extends StatelessWidget {
  const ClusterCorrectnessPie({super.key, required this.constituencies});

  final List<Constituency> constituencies;

  @override
  Widget build(BuildContext context) {
    final correct =
        constituencies.where((c) => c.clusterPredictionCorrect).length;
    final incorrect = constituencies.length - correct;

    return PieChart(
      PieChartData(
        sections: [
          PieChartSectionData(
            value: correct.toDouble(),
            title: '$correct\nCorrect',
            color: Palette.noChange, // green
            radius: 60,
            titleStyle: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          PieChartSectionData(
            value: incorrect.toDouble(),
            title: '$incorrect\nWrong',
            color: Palette.change, // orange/red
            radius: 60,
            titleStyle: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
        centerSpaceRadius: 30,
        sectionsSpace: 2,
      ),
    );
  }
}
