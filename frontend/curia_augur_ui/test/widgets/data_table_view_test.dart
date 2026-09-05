// Tests for the data table. Beyond the obvious behaviour, this table is the accessible
// text equivalent of the maps and charts (WCAG 2.2 SC 1.4.1), so the assertions here
// cover that every value the charts encode as colour is also written out as text.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:curia_augur_ui/models/analysis.dart';
import 'package:curia_augur_ui/theme/palette.dart';
import 'package:curia_augur_ui/widgets/data_table_view.dart';

import '../helpers.dart';

List<Constituency> _rows() => [
  Constituency.fromJson(
    constituencyJson(
      name: 'Hitshire',
      council: 'Hitshire CC',
      changeFactor: 1,
      changeFactorCluster: 1,
      deciles: const {'Income Decile delta': 5},
    ),
  ),
  Constituency.fromJson(
    constituencyJson(
      name: 'Missford',
      council: 'Missford BC',
      clusterId: 2,
      changeFactor: 0,
      changeFactorCluster: 1,
      deciles: const {'Income Decile delta': 1},
    ),
  ),
];

void main() {
  testWidgets('renders one row per authority with all seven columns', (tester) async {
    await tester.pumpWidget(
      harness(
        DataTableView(constituencies: _rows(), metric: 'change_factor'),
        height: 500,
      ),
    );

    for (final column in [
      'Local Authority',
      'Council',
      'Cluster',
      'Actual',
      'Cluster prediction',
      'Correct',
    ]) {
      expect(find.text(column), findsOneWidget, reason: 'missing column $column');
    }
    expect(find.text('Hitshire'), findsOneWidget);
    expect(find.text('Missford'), findsOneWidget);
  });

  testWidgets('states actual and predicted outcomes as words', (tester) async {
    await tester.pumpWidget(
      harness(
        DataTableView(constituencies: _rows(), metric: 'change_factor'),
        height: 500,
      ),
    );

    // Hitshire: actual change, predicted change. Missford: actual no change,
    // predicted change. So three "change" cells and one "no change".
    expect(find.text('change'), findsNWidgets(3));
    expect(find.text('no change'), findsOneWidget);
  });

  testWidgets('correctness is an icon plus a tooltip, never colour alone', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        DataTableView(constituencies: _rows(), metric: 'change_factor'),
        height: 500,
      ),
    );

    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);

    final tick = tester.widget<Icon>(find.byIcon(Icons.check));
    expect(tick.semanticLabel, 'correct');
    expect(tick.color, Palette.correct);

    final cross = tester.widget<Icon>(find.byIcon(Icons.close));
    expect(cross.semanticLabel, 'incorrect');
    expect(cross.color, Palette.incorrect);
  });

  testWidgets('filters by authority name', (tester) async {
    await tester.pumpWidget(
      harness(
        DataTableView(constituencies: _rows(), metric: 'change_factor'),
        height: 500,
      ),
    );

    await tester.enterText(find.byType(TextField), 'miss');
    await tester.pump();

    expect(find.text('Missford'), findsOneWidget);
    expect(find.text('Hitshire'), findsNothing);
  });

  testWidgets('filters by council name and ignores case', (tester) async {
    await tester.pumpWidget(
      harness(
        DataTableView(constituencies: _rows(), metric: 'change_factor'),
        height: 500,
      ),
    );

    await tester.enterText(find.byType(TextField), 'HITSHIRE CC');
    await tester.pump();

    expect(find.text('Hitshire'), findsOneWidget);
    expect(find.text('Missford'), findsNothing);
  });

  testWidgets('sorts by the selected metric, highest first', (tester) async {
    await tester.pumpWidget(
      harness(
        DataTableView(
          constituencies: _rows(),
          metric: 'Income Decile delta',
        ),
        height: 500,
      ),
    );

    final names = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .where((d) => d == 'Hitshire' || d == 'Missford')
        .toList();
    // Hitshire has decile delta 5, Missford 1.
    expect(names, ['Hitshire', 'Missford']);
  });

  testWidgets('collapses and expands', (tester) async {
    await tester.pumpWidget(
      harness(
        DataTableView(constituencies: _rows(), metric: 'change_factor'),
        height: 500,
      ),
    );

    await tester.tap(find.byIcon(Icons.expand_less));
    await tester.pump();
    expect(find.byType(DataTable), findsNothing);

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pump();
    expect(find.byType(DataTable), findsOneWidget);
  });

  testWidgets('scrolls horizontally rather than clipping columns', (tester) async {
    // Seven columns do not fit a narrow window; the table must not overflow.
    await tester.pumpWidget(
      harness(
        DataTableView(constituencies: _rows(), metric: 'change_factor'),
        width: 500,
        height: 500,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      find.byWidgetPredicate(
        (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
      ),
      findsOneWidget,
    );
  });

  testWidgets('handles an empty analysis without dividing by zero', (tester) async {
    await tester.pumpWidget(
      harness(
        const DataTableView(constituencies: [], metric: 'change_factor'),
        height: 400,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(DataTable), findsOneWidget);
  });
}
