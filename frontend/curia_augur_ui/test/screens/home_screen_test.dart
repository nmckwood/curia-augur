// Tests for the main screen's chrome and its failure path.
//
// HomeScreen builds its own ApiService, which in a non-local build calls the files API
// over HTTP. The test binding fails every request with status 400, so what is covered
// here is the chrome plus the error path — which is worth covering in its own right,
// since a broken API must show a message rather than a blank page. Rendering the fully
// populated screen would mean injecting the service; that is noted as not covered in
// test/README.md.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:curia_augur_ui/screens/home_screen.dart';

void main() {
  testWidgets('renders the app bar and the file selector', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(auth: null, onSignOut: () {})),
    );
    await tester.pumpAndSettle();

    expect(find.text('Curia Augur'), findsOneWidget);
    expect(find.text('Select an analysis file'), findsOneWidget);
  });

  testWidgets('surfaces a message when the files API cannot be reached', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(auth: null, onSignOut: () {})),
    );
    await tester.pumpAndSettle();

    // A failed load must say so rather than leaving a blank page.
    expect(find.textContaining('Exception'), findsOneWidget);
  });

  testWidgets('hides the per-year button until an analysis is loaded', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(auth: null, onSignOut: () {})),
    );
    await tester.pumpAndSettle();

    expect(find.text('Per-year predictiveness'), findsNothing);
  });

  testWidgets('the file selector carries an explanatory hint', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(auth: null, onSignOut: () {})),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.info_outline), findsOneWidget);
  });
}
