// Tests for the regression summary — the panel that reads predict.py's logistic
// regression against the no-ML baseline and states whether ML earned its keep.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:curia_augur_ui/models/analysis.dart';
import 'package:curia_augur_ui/theme/palette.dart';
import 'package:curia_augur_ui/widgets/regression_summary.dart';

import '../helpers.dart';

void main() {
  testWidgets('describes how the model was fit and scored', (tester) async {
    await tester.pumpWidget(
      harness(RegressionSummary(analysis: sampleAnalysis()), height: 520),
    );

    expect(find.text('Regression summary'), findsOneWidget);
    expect(find.textContaining('Logistic regression'), findsOneWidget);
    expect(find.textContaining('fit on 70 authorities'), findsOneWidget);
    expect(find.textContaining('30 held out'), findsOneWidget);
  });

  testWidgets('lists the model, baseline and per-year scores', (tester) async {
    await tester.pumpWidget(
      harness(RegressionSummary(analysis: sampleAnalysis()), height: 520),
    );

    expect(find.text('Model (held-out)'), findsOneWidget);
    expect(find.text('62.0%'), findsOneWidget);
    expect(find.text('Most common change factor'), findsOneWidget);
    expect(find.text('55.0%'), findsOneWidget);
    expect(find.text('Per-year best indices'), findsOneWidget);
  });

  testWidgets('reports a positive uplift with an upward icon', (tester) async {
    await tester.pumpWidget(
      harness(
        RegressionSummary(
          analysis: sampleAnalysis(
            prediction: predictionJson(holdoutAccuracy: 0.70, baselineAccuracy: 0.60),
          ),
        ),
        height: 520,
      ),
    );

    expect(find.textContaining('Uplift over baseline: +10.0 pp'), findsOneWidget);
    expect(find.byIcon(Icons.trending_up), findsOneWidget);
    expect(find.textContaining('carry some real signal'), findsOneWidget);
  });

  testWidgets('reports a negative uplift with a downward icon and a plain verdict', (
    tester,
  ) async {
    // This is the real result for the 2019/2025 pair: the model loses to guessing.
    await tester.pumpWidget(
      harness(
        RegressionSummary(
          analysis: sampleAnalysis(
            prediction: predictionJson(holdoutAccuracy: 0.517, baselineAccuracy: 0.575),
          ),
        ),
        height: 520,
      ),
    );

    expect(find.textContaining('Uplift over baseline: -5.8 pp'), findsOneWidget);
    expect(find.byIcon(Icons.trending_down), findsOneWidget);
    expect(find.textContaining('add nothing over simply predicting'), findsOneWidget);
  });

  testWidgets('the direction is stated by icon and sign, not colour alone', (
    tester,
  ) async {
    // WCAG 2.2 SC 1.4.1: the ink colour must only reinforce the verdict.
    await tester.pumpWidget(
      harness(
        RegressionSummary(
          analysis: sampleAnalysis(
            prediction: predictionJson(holdoutAccuracy: 0.70, baselineAccuracy: 0.60),
          ),
        ),
        height: 520,
      ),
    );

    final icon = tester.widget<Icon>(find.byIcon(Icons.trending_up));
    expect(icon.semanticLabel, 'better than baseline');
    expect(icon.color, Palette.positiveInk);
  });

  testWidgets('names the best single index', (tester) async {
    await tester.pumpWidget(
      harness(RegressionSummary(analysis: sampleAnalysis()), height: 520),
    );

    expect(
      find.textContaining('Best single index: Income at 61.0% held-out'),
      findsOneWidget,
    );
  });

  testWidgets('degrades gracefully before the prediction stage has run', (
    tester,
  ) async {
    final analysis = Analysis.fromJson(analysisJson(prediction: null));

    await tester.pumpWidget(
      harness(RegressionSummary(analysis: analysis), height: 300),
    );

    expect(find.textContaining('prediction stage has not run'), findsOneWidget);
  });
}
