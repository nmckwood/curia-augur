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

  testWidgets('reports the significance verdict and p value', (tester) async {
    await tester.pumpWidget(
      harness(AnalysisSummary(analysis: sampleAnalysis()), height: 500),
    );

    expect(find.textContaining('not statistically significant'), findsOneWidget);
    expect(find.textContaining('p = 0.4200'), findsOneWidget);
  });

  testWidgets('says so when the difference IS significant', (tester) async {
    final analysis = Analysis.fromJson(
      analysisJson(significant: true, pValue: 0.001, prediction: predictionJson()),
    );

    await tester.pumpWidget(harness(AnalysisSummary(analysis: analysis), height: 500));

    final text = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join(' ');
    expect(text, contains('is statistically significant'));
    expect(text, isNot(contains('not statistically significant')));
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
}
