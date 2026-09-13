import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:curia_augur_ui/models/analysis.dart';
import 'package:curia_augur_ui/widgets/kmeans_widget.dart';
import 'package:curia_augur_ui/widgets/lad_data_widget.dart';
import 'package:curia_augur_ui/widgets/logistic_regression_widget.dart';

import '../helpers.dart';

Map<String, dynamic> _geoJson() => {
  'features': [
    {
      'properties': {'LAD22NM': 'A'},
      'geometry': {
        'type': 'Polygon',
        'coordinates': [
          [
            [-1.0, 53.0],
            [-1.0, 53.5],
            [-0.5, 53.5],
            [-0.5, 53.0],
            [-1.0, 53.0],
          ],
        ],
      },
    },
  ],
};

void main() {
  testWidgets('LAD table reads its columns from the deciles actually present', (
    tester,
  ) async {
    // Driving the columns off meta.features_used rendered a permanently-empty
    // "—" column for every feature the record did not carry.
    final analysis = sampleAnalysis();
    expect(
      analysis.featuresUsed,
      isNot(contains('Income Decile delta')),
      reason: 'fixture must keep features_used and the record keys distinct',
    );

    await tester.pumpWidget(
      harness(LadDataWidget(constituencies: analysis.constituencies)),
    );

    expect(find.text('Income'), findsOneWidget);
    expect(find.text('2'), findsNWidgets(analysis.constituencies.length));
    expect(find.text('—'), findsNothing);
  });

  testWidgets('LAD table shows one row per constituency', (tester) async {
    final analysis = sampleAnalysis();
    await tester.pumpWidget(
      harness(LadDataWidget(constituencies: analysis.constituencies)),
    );

    for (final c in analysis.constituencies) {
      expect(find.text(c.name), findsOneWidget);
    }
  });

  testWidgets('LAD table scrolls horizontally when the columns overflow', (
    tester,
  ) async {
    // Eight decile columns plus the fixed ones is wider than any sane window.
    final wide = Analysis.fromJson(
      analysisJson(
        constituencies: [
          for (final name in ['A', 'B'])
            constituencyJson(
              name: name,
              deciles: {
                for (var i = 0; i < 8; i++) 'Deprivation index $i delta': i,
              },
            ),
        ],
      ),
    );

    await tester.pumpWidget(
      harness(LadDataWidget(constituencies: wide.constituencies), width: 600),
    );

    final scroller = tester.widget<SingleChildScrollView>(
      find
          .descendant(
            of: find.byType(LadDataWidget),
            matching: find.byType(SingleChildScrollView),
          )
          .first,
    );
    expect(scroller.scrollDirection, Axis.horizontal);

    final position = scroller.controller!.position;
    expect(
      position.maxScrollExtent,
      greaterThan(0),
      reason: 'table must be wider than the 600px viewport',
    );

    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    expect(position.pixels, position.maxScrollExtent);
  });

  testWidgets('regression widget sizes to its contents without overflowing', (
    tester,
  ) async {
    // Previously wrapped in a fixed SizedBox(height: 350): the card's margin and
    // padding left 318px for a column needing 332, overflowing by 14 pixels.
    await tester.pumpWidget(
      harness(
        SingleChildScrollView(
          child: LogisticRegressionWidget(analysis: sampleAnalysis()),
        ),
        height: 400,
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('k-means card holds only the maps and charts, not the table', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        SingleChildScrollView(
          child: KmeansWidget(
            analysis: sampleAnalysis(),
            geoJson: _geoJson(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    // The table is its own card at the bottom of the page now.
    expect(find.byType(LadDataWidget), findsNothing);
  });

  testWidgets('LAD table sizes itself inside an unbounded scrolling column', (
    tester,
  ) async {
    // As the last card on the page it sits in a SingleChildScrollView, so it
    // must not rely on an outer box to bound its scrolling rows area.
    await tester.pumpWidget(
      harness(
        SingleChildScrollView(
          child: Column(
            children: [
              LadDataWidget(constituencies: sampleAnalysis().constituencies),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(DataTable), findsOneWidget);
  });
}
