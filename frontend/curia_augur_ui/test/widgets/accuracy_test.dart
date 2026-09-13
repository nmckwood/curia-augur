// Tests for the accuracy row: the model pie, the no-ML baseline pie, and the shared
// donut they are both built from.

import 'package:flutter_test/flutter_test.dart';

import 'package:curia_augur_ui/models/analysis.dart';
import 'package:curia_augur_ui/theme/palette.dart';
import 'package:curia_augur_ui/widgets/accuracy_donut.dart';
import 'package:curia_augur_ui/widgets/accuracy_pie.dart';
import 'package:curia_augur_ui/widgets/baseline_accuracy.dart';

import '../helpers.dart';

void main() {
  group('AccuracyDonut', () {
    testWidgets('renders the title, headline and every note', (tester) async {
      await tester.pumpWidget(
        harness(
          const AccuracyDonut(
            title: 'Prediction accuracy',
            help: 'help text',
            headline: '75.0% correct (3 / 4)',
            accuracy: 0.75,
            notes: ['note one', 'note two'],
          ),
          height: 420,
        ),
      );

      expect(find.text('Prediction accuracy'), findsOneWidget);
      expect(find.text('75.0% correct (3 / 4)'), findsOneWidget);
      expect(find.text('note one'), findsOneWidget);
      expect(find.text('note two'), findsOneWidget);
    });

    testWidgets('legend names both slices in words', (tester) async {
      // WCAG 2.2 SC 1.4.1 — the slices must be identifiable without colour.
      await tester.pumpWidget(
        harness(
          const AccuracyDonut(
            title: 't',
            help: 'h',
            headline: 'x',
            accuracy: 0.5,
          ),
          height: 420,
        ),
      );

      expect(find.text('Correct'), findsOneWidget);
      expect(find.text('Incorrect'), findsOneWidget);
    });
  });

  group('AccuracyPie', () {
    testWidgets('scores the cluster prediction over every authority', (tester) async {
      await tester.pumpWidget(
        harness(AccuracyPie(analysis: sampleAnalysis()), height: 460),
      );

      expect(find.text('Prediction accuracy'), findsOneWidget);
      expect(
        find.textContaining('Cluster prediction: 75.0% correct (3 / 4 all authorities)'),
        findsOneWidget,
      );
    });

    testWidgets('lists each cluster ranked by accuracy', (tester) async {
      await tester.pumpWidget(
        harness(AccuracyPie(analysis: sampleAnalysis()), height: 460),
      );

      expect(
        find.textContaining('#1 cluster 0 (predicts no change): 100.0% (2 / 2)'),
        findsOneWidget,
      );
      expect(
        find.textContaining('#2 cluster 1 (predicts change): 50.0% (1 / 2)'),
        findsOneWidget,
      );
    });

    testWidgets('uses the held-out score for the common-indices model', (tester) async {
      await tester.pumpWidget(
        harness(
          AccuracyPie(
            analysis: sampleAnalysis(
              prediction: predictionJson(holdoutAccuracy: 0.62, testSize: 30),
            ),
            source: PredictionSource.common,
          ),
          height: 460,
        ),
      );

      expect(
        find.textContaining('Common indices: 62.0% correct (19 / 30 held-out)'),
        findsOneWidget,
      );
    });

    testWidgets('shows the per-year benchmark when asked', (tester) async {
      await tester.pumpWidget(
        harness(
          AccuracyPie(
            analysis: sampleAnalysis(),
            source: PredictionSource.perYear,
          ),
          height: 460,
        ),
      );

      expect(find.textContaining('Per-year best indices: 60.0%'), findsOneWidget);
    });
  });

  group('BaselineAccuracy', () {
    testWidgets('answers "what if we just guessed the most common outcome"', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(BaselineAccuracy(analysis: sampleAnalysis()), height: 460),
      );

      expect(find.text('Most common change factor (no ML)'), findsOneWidget);
      expect(
        find.textContaining('Always guess "no change": 56.0% correct (56 / 100)'),
        findsOneWidget,
      );
      expect(find.textContaining('Held-out: 55.0%'), findsOneWidget);
    });

    testWidgets('names the guess correctly when the majority is "change"', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(
          BaselineAccuracy(
            analysis: sampleAnalysis(prediction: predictionJson(majorityClass: 1)),
          ),
          height: 460,
        ),
      );

      expect(find.textContaining('Always guess "change"'), findsOneWidget);
    });

    testWidgets('degrades gracefully before the prediction stage has run', (
      tester,
    ) async {
      final analysis = Analysis.fromJson(analysisJson(prediction: null));

      await tester.pumpWidget(
        harness(BaselineAccuracy(analysis: analysis), height: 300),
      );

      expect(
        find.textContaining('prediction stage has not run'),
        findsOneWidget,
      );
    });
  });

  test('the donut uses the accessible pair, not red/green', () {
    expect(Palette.correct, Palette.noChange);
    expect(Palette.incorrect, Palette.change);
  });
}
