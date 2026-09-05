// Tests for the chart widgets and the shared marker helpers.
//
// fl_chart renders to a canvas, so these assert the things that are actually inspectable
// and that carry the accessibility guarantees: legends, shapes, labels and the absence
// of layout overflow. Pixel output is out of scope.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:curia_augur_ui/models/analysis.dart';
import 'package:curia_augur_ui/theme/palette.dart';
import 'package:curia_augur_ui/widgets/cluster_scatter.dart';
import 'package:curia_augur_ui/widgets/mark_swatch.dart';
import 'package:curia_augur_ui/widgets/most_predictive_indices.dart';
import 'package:curia_augur_ui/widgets/prediction_scatter.dart';

import '../helpers.dart';

void main() {
  group('markDotPainter', () {
    test('maps each mark to a distinct fl_chart painter', () {
      expect(
        markDotPainter(ClusterMark.circle, Palette.noChange),
        isA<FlDotCirclePainter>(),
      );
      expect(
        markDotPainter(ClusterMark.square, Palette.noChange),
        isA<FlDotSquarePainter>(),
      );
      expect(
        markDotPainter(ClusterMark.cross, Palette.noChange),
        isA<FlDotCrossPainter>(),
      );
    });

    test('honours the requested colour and radius', () {
      final painter =
          markDotPainter(ClusterMark.circle, Palette.change, radius: 7)
              as FlDotCirclePainter;

      expect(painter.color, Palette.change);
      expect(painter.radius, 7);
    });
  });

  group('MarkLegend', () {
    testWidgets('shows the label and names the shape for screen readers', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(
          const MarkLegend(
            mark: ClusterMark.cross,
            color: Palette.change,
            label: 'Predicted change',
          ),
          height: 100,
        ),
      );

      expect(find.text('Predicted change'), findsOneWidget);
      final semantics = tester.widget<Semantics>(
        find.ancestor(
          of: find.text('Predicted change'),
          matching: find.byType(Semantics),
        ).first,
      );
      expect(semantics.properties.label, contains('cross'));
    });

    testWidgets('draws a swatch for every mark without throwing', (tester) async {
      for (final mark in ClusterMark.values) {
        await tester.pumpWidget(
          harness(
            MarkSwatch(mark: mark, color: Palette.cluster(0)),
            height: 100,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('ClusterScatter', () {
    testWidgets('legends every cluster present in the data', (tester) async {
      await tester.pumpWidget(
        harness(
          ClusterScatter(constituencies: sampleAnalysis().constituencies),
          height: 420,
        ),
      );

      expect(find.text('Cluster 0'), findsOneWidget);
      expect(find.text('Cluster 1'), findsOneWidget);
      expect(find.byType(ScatterChart), findsOneWidget);
    });

    testWidgets('renders with no constituencies at all', (tester) async {
      await tester.pumpWidget(
        harness(const ClusterScatter(constituencies: []), height: 420),
      );
      expect(tester.takeException(), isNull);
    });

    test('clusterColor delegates to the validated palette', () {
      expect(clusterColor(0), Palette.cluster(0));
      expect(clusterColor(1), Palette.cluster(1));
    });
  });

  group('PredictionScatter', () {
    testWidgets('legends both series by shape as well as colour', (tester) async {
      await tester.pumpWidget(
        harness(
          PredictionScatter(constituencies: sampleAnalysis().constituencies),
          height: 420,
        ),
      );

      expect(find.text('Actual change'), findsOneWidget);
      expect(find.text('Predicted change'), findsOneWidget);
      expect(find.byType(MarkSwatch), findsNWidgets(2));
    });

    testWidgets('explains itself via the heading tooltip', (tester) async {
      await tester.pumpWidget(
        harness(
          PredictionScatter(constituencies: sampleAnalysis().constituencies),
          height: 420,
        ),
      );

      expect(
        find.text('Predicted vs actual, authority by authority'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });

    testWidgets('renders each prediction source without throwing', (tester) async {
      for (final source in PredictionSource.values) {
        await tester.pumpWidget(
          harness(
            PredictionScatter(
              constituencies: sampleAnalysis().constituencies,
              source: source,
            ),
            height: 420,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'failed for $source');
      }
    });

    testWidgets('renders with no constituencies', (tester) async {
      await tester.pumpWidget(
        harness(const PredictionScatter(constituencies: []), height: 420),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('MostPredictiveIndices', () {
    testWidgets('lists each index with its held-out accuracy', (tester) async {
      await tester.pumpWidget(
        harness(MostPredictiveIndices(analysis: sampleAnalysis()), height: 420),
      );

      expect(find.text('Most predictive deprivation indices'), findsOneWidget);
      expect(find.textContaining('Baseline "predict no change" = 55.0%'), findsOneWidget);
      expect(find.text('61.0%'), findsOneWidget);
      expect(find.text('40.0%'), findsOneWidget);
    });

    testWidgets('a tick or dash states whether each index beats the baseline', (
      tester,
    ) async {
      // WCAG 2.2 SC 1.4.1: the bar colour must not be the only signal.
      await tester.pumpWidget(
        harness(MostPredictiveIndices(analysis: sampleAnalysis()), height: 420),
      );

      // 61% beats the 55% baseline; 40% does not.
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget);
    });

    testWidgets('degrades gracefully with no prediction data', (tester) async {
      final analysis = Analysis.fromJson(analysisJson(prediction: null));

      await tester.pumpWidget(
        harness(MostPredictiveIndices(analysis: analysis), height: 300),
      );

      expect(
        find.text('No per-year predictiveness data available.'),
        findsOneWidget,
      );
    });
  });
}
