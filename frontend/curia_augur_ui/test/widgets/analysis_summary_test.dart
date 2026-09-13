// Tests for the written summary card, including the REQUIREMENTS_4 cluster ranking.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:curia_augur_ui/models/analysis.dart';
import 'package:curia_augur_ui/widgets/analysis_summary.dart';

import '../helpers.dart';

void main() {
  testWidgets('summarises the clustering in plain English', (tester) async {
    await tester.pumpWidget(
      harness(AnalysisSummary(analysis: sampleAnalysis()), height: 500),
    );

    expect(find.text('Summary'), findsOneWidget);
    expect(
      find.textContaining('grouped 4 local authorities into 2 clusters'),
      findsOneWidget,
    );
  });

  testWidgets('contrasts the high-change cluster flip rate with the rest', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(AnalysisSummary(analysis: sampleAnalysis()), height: 500),
    );

    expect(
      find.textContaining('The high-change cluster contains 2 authorities'),
      findsOneWidget,
    );
  });

  testWidgets('scores the clustering as a prediction and ranks the clusters', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(AnalysisSummary(analysis: sampleAnalysis()), height: 500),
    );

    expect(
      find.textContaining('the clusters called 75.0% of authorities correctly (3 of 4)'),
      findsOneWidget,
    );
    expect(
      find.textContaining('#1  Cluster 0 (2 authorities, predicts no change): 100.0%'),
      findsOneWidget,
    );
    expect(
      find.textContaining('#2  Cluster 1 (2 authorities, predicts change): 50.0%'),
      findsOneWidget,
    );
  });

  testWidgets('lists the indices characterising the high-change cluster', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(AnalysisSummary(analysis: sampleAnalysis()), height: 500),
    );

    expect(find.text('1. Income'), findsOneWidget);
    expect(find.text('2. Crime'), findsOneWidget);
  });

  testWidgets('renders when no cluster is flagged as high change', (tester) async {
    final analysis = Analysis.fromJson(analysisJson());

    await tester.pumpWidget(harness(AnalysisSummary(analysis: analysis), height: 500));

    expect(tester.takeException(), isNull);
    expect(find.text('Summary'), findsOneWidget);
  });

  testWidgets('carries an explanatory tooltip', (tester) async {
    await tester.pumpWidget(
      harness(AnalysisSummary(analysis: sampleAnalysis()), height: 500),
    );
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
  });

  group('regression half (REQUIREMENTS_5 UI-1)', () {
    Future<void> pumpWith(WidgetTester tester, Analysis analysis) =>
        tester.pumpWidget(
          harness(AnalysisSummary(analysis: analysis), height: 700),
        );

    Analysis withUplift({
      required double holdout,
      required double baseline,
    }) => Analysis.fromJson(
      analysisJson(
        prediction: predictionJson(
          holdoutAccuracy: holdout,
          baselineAccuracy: baseline,
        ),
      ),
    );

    testWidgets('reports the model score and its training split', (
      tester,
    ) async {
      await pumpWith(tester, sampleAnalysis());

      expect(
        find.textContaining('Logistic regression'),
        findsOneWidget,
        reason: 'the summary must cover both models, not just k-means',
      );
      expect(find.textContaining('62.0% correctly'), findsOneWidget);
      expect(find.textContaining('fit on 70 authorities'), findsOneWidget);
    });

    testWidgets('says the indices carried signal when it beats the baseline', (
      tester,
    ) async {
      await pumpWith(tester, withUplift(holdout: 0.70, baseline: 0.55));

      expect(find.textContaining('beating the no-ML baseline'), findsOneWidget);
      expect(find.textContaining('15.0 percentage points'), findsOneWidget);
      expect(find.textContaining('carried some real signal'), findsOneWidget);
    });

    testWidgets('says the indices added nothing when it falls short', (
      tester,
    ) async {
      await pumpWith(tester, withUplift(holdout: 0.483, baseline: 0.575));

      // The real 2019->2025 analysis sits here, at -9.2pp.
      expect(find.textContaining('falling 9.2 percentage points'), findsOneWidget);
      expect(find.textContaining('added nothing'), findsOneWidget);
    });

    testWidgets('calls an exact tie a tie, not a negative-zero loss', (
      tester,
    ) async {
      // The real 2015->2019 analysis: holdout and baseline are identical, so a
      // naive sign check renders "falling -0.0 percentage points short".
      await pumpWith(tester, withUplift(holdout: 0.779, baseline: 0.779));

      expect(find.textContaining('matching the no-ML baseline'), findsOneWidget);
      expect(find.textContaining('falling'), findsNothing);
      expect(find.textContaining('-0.0'), findsNothing);
    });

    testWidgets('omits the regression half before the stage has run', (
      tester,
    ) async {
      await pumpWith(tester, Analysis.fromJson(analysisJson()));

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Logistic regression'), findsNothing);
      expect(find.textContaining('K-means grouped'), findsOneWidget);
    });
  });
}
