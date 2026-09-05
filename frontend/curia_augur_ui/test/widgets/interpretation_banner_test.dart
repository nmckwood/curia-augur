// The ecological-fallacy banner is an ethics-review requirement, so these tests assert
// that the caveats are actually on screen and cannot be permanently dismissed.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:curia_augur_ui/widgets/interpretation_banner.dart';

import '../helpers.dart';

void main() {
  testWidgets('shows the caveats expanded on first open', (tester) async {
    await tester.pumpWidget(harness(const InterpretationBanner(), height: 400));

    expect(find.textContaining('How to read these results'), findsOneWidget);
    expect(
      find.textContaining('do not read individual voting behaviour'),
      findsOneWidget,
    );
    expect(find.textContaining('ecological fallacy'), findsOneWidget);
  });

  testWidgets('names the factors the model leaves out', (tester) async {
    await tester.pumpWidget(harness(const InterpretationBanner(), height: 400));

    expect(find.textContaining('immigration'), findsOneWidget);
    expect(find.textContaining('national sentiment'), findsOneWidget);
  });

  testWidgets('states that cluster naming is deliberately neutral', (
    tester,
  ) async {
    await tester.pumpWidget(harness(const InterpretationBanner(), height: 400));
    expect(find.textContaining('cluster-n'), findsOneWidget);
  });

  testWidgets('detail collapses but the headline warning stays', (
    tester,
  ) async {
    await tester.pumpWidget(harness(const InterpretationBanner(), height: 400));

    await tester.tap(find.text('Hide detail'));
    await tester.pump();

    expect(find.textContaining('ecological fallacy'), findsNothing);
    // The warning itself is never dismissable — only the detail collapses.
    expect(find.textContaining('How to read these results'), findsOneWidget);
    expect(find.text('Read more'), findsOneWidget);
  });

  testWidgets('the detail is bounded and scrolls on a short viewport', (
    tester,
  ) async {
    // The banner is above every screen, so it must never push the app off-screen.
    await tester.pumpWidget(harness(const InterpretationBanner(), height: 200));

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('detail reopens after collapsing', (tester) async {
    await tester.pumpWidget(harness(const InterpretationBanner(), height: 400));

    await tester.tap(find.text('Hide detail'));
    await tester.pump();
    await tester.tap(find.text('Read more'));
    await tester.pump();

    expect(find.textContaining('ecological fallacy'), findsOneWidget);
  });
}
