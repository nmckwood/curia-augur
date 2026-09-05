// Tooltips only help if users know they are there, so these tests assert the visible
// affordance as well as the tooltip content and its screen-reader label.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:curia_augur_ui/widgets/info_heading.dart';

import '../helpers.dart';

void main() {
  testWidgets('renders the title next to a visible hint icon', (tester) async {
    await tester.pumpWidget(
      harness(
        const InfoHeading(title: 'Some chart', help: 'What it means.'),
        height: 100,
      ),
    );

    expect(find.text('Some chart'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
  });

  testWidgets('tapping the hint reveals the help text', (tester) async {
    await tester.pumpWidget(
      harness(
        const InfoHeading(title: 'Some chart', help: 'What it means.'),
        height: 100,
      ),
    );

    expect(find.text('What it means.'), findsNothing);
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('What it means.'), findsOneWidget);
  });

  testWidgets('the hint carries the help text as a semantics label', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        const InfoHint(help: 'Explains things.', label: 'thing'),
        height: 100,
      ),
    );

    final icon = tester.widget<Icon>(find.byIcon(Icons.info_outline));
    expect(icon.semanticLabel, contains('About thing'));
    expect(icon.semanticLabel, contains('Explains things.'));
  });

  testWidgets('a long title ellipsises rather than overflowing', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        InfoHeading(title: 'A very long heading ' * 10, help: 'h'),
        width: 200,
        height: 100,
      ),
    );

    expect(tester.takeException(), isNull);
    final text = tester.widget<Text>(
      find.textContaining('A very long heading'),
    );
    expect(text.overflow, TextOverflow.ellipsis);
  });

  testWidgets('a caller-supplied style is honoured', (tester) async {
    await tester.pumpWidget(
      harness(
        const InfoHeading(
          title: 'Big',
          help: 'h',
          style: TextStyle(fontSize: 22),
        ),
        height: 100,
      ),
    );

    expect(tester.widget<Text>(find.text('Big')).style!.fontSize, 22);
  });
}
