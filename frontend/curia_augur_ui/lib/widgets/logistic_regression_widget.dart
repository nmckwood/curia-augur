import 'package:flutter/material.dart';

import '../models/analysis.dart';
import 'accuracy_pie.dart';
import 'baseline_accuracy.dart';
import 'info_heading.dart';
import 'regression_summary.dart';

/// Logistic Regression dedicated widget (REQUIREMENTS_5 Widget 3):
/// Pie chart for prediction accuracy, pie chart for baseline (most common change factor),
/// and regression summary.
class LogisticRegressionWidget extends StatelessWidget {
  const LogisticRegressionWidget({super.key, required this.analysis});

  final Analysis analysis;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const InfoHeading(
              title: 'Logistic Regression Analysis',
              help:
                  'Logistic regression trained on deprivation indices to predict '
                  'whether the majority party changed. Pie charts show prediction '
                  'accuracy vs baseline. Regression summary shows key metrics.',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 300,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Prediction Accuracy',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Expanded(
                          child: AccuracyPie(
                            analysis: analysis,
                            source: PredictionSource.common,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Baseline (No ML)',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Expanded(
                          child: BaselineAccuracy(analysis: analysis),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Regression Summary',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Expanded(
                          child: RegressionSummary(analysis: analysis),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
