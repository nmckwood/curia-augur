// Tests for the per-year predictiveness page. It takes its analysis and GeoJSON as
// plain arguments, so it renders end-to-end with no API or auth involved.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:curia_augur_ui/models/analysis.dart';
import 'package:curia_augur_ui/screens/per_year_screen.dart';
import 'package:curia_augur_ui/widgets/accuracy_pie.dart';
import 'package:curia_augur_ui/widgets/most_predictive_indices.dart';
import 'package:curia_augur_ui/widgets/prediction_scatter.dart';

import '../helpers.dart';

const _geoJson = <String, dynamic>{'features': []};

Widget _page({Analysis? analysis}) => MaterialApp(
  home: PerYearScreen(
    filename: 'analysis-d_2015_d_2019_le_2018_le_2022.json',
    analysis: analysis ?? sampleAnalysis(),
    geoJson: _geoJson,
  ),
);

void main() {
  testWidgets('titles itself with the analysis filename', (tester) async {
    await tester.pumpWidget(_page());
    await tester.pump();

    expect(
      find.text(
        'Per-year predictiveness — analysis-d_2015_d_2019_le_2018_le_2022.json',
      ),
      findsOneWidget,
    );
  });

  testWidgets('states the per-year headline against the baseline', (tester) async {
    await tester.pumpWidget(_page());
    await tester.pump();

    expect(
      find.textContaining(
        'Per-year best-indices model: 60.0% held-out vs baseline 55.0%',
      ),
      findsOneWidget,
    );
  });

  testWidgets('warns that only bars past the baseline carry signal', (tester) async {
    await tester.pumpWidget(_page());
    await tester.pump();

    expect(
      find.textContaining('Only indices whose bar extends past the baseline marker'),
      findsOneWidget,
    );
  });

  testWidgets('shows the bar chart, map, scatter and pie', (tester) async {
    await tester.pumpWidget(_page());
    await tester.pump();

    expect(find.byType(MostPredictiveIndices), findsOneWidget);
    expect(find.byType(PredictionScatter), findsOneWidget);
    expect(find.byType(AccuracyPie), findsOneWidget);
  });

  testWidgets('the scatter and pie both use the per-year series', (tester) async {
    await tester.pumpWidget(_page());
    await tester.pump();

    expect(
      tester.widget<PredictionScatter>(find.byType(PredictionScatter)).source,
      PredictionSource.perYear,
    );
    expect(
      tester.widget<AccuracyPie>(find.byType(AccuracyPie)).source,
      PredictionSource.perYear,
    );
  });

  testWidgets('both section headings carry explanatory tooltips', (tester) async {
    await tester.pumpWidget(_page());
    await tester.pump();

    expect(
      find.text('Predicted change (per-year best indices)'),
      findsOneWidget,
    );
    expect(
      find.text('Predicted vs actual change (per-year best indices)'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.info_outline), findsWidgets);
  });

  testWidgets('renders before the prediction stage has run', (tester) async {
    final analysis = Analysis.fromJson(analysisJson(prediction: null));

    await tester.pumpWidget(_page(analysis: analysis));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.text('No per-year predictiveness data available.'),
      findsOneWidget,
    );
  });
}
