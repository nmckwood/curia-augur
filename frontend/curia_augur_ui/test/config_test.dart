// Unit tests for the derived Config getters.
//
// The raw values come from `String.fromEnvironment`, so they are compile-time constants
// and cannot be varied per test. What IS testable — and what actually gates behaviour —
// is how the derived getters combine them. In a default `flutter test` build every
// dart-define is unset, which is the cloud (authenticated) configuration.

import 'package:flutter_test/flutter_test.dart';

import 'package:curia_augur_ui/config.dart';

void main() {
  test('an unconfigured build is neither local nor auth-skipping', () {
    expect(Config.local, isFalse);
    expect(Config.localFilename, isEmpty);
    expect(Config.skipAuth, isFalse);
  });

  test('isLocal is false without LOCAL or LOCAL_FILENAME', () {
    expect(Config.isLocal, isFalse);
  });

  test('requiresAuth is true unless local mode or SKIP_AUTH is set', () {
    // This is the security-relevant default: a plain production build demands Cognito.
    expect(Config.requiresAuth, isTrue);
  });

  test('filesEndpoint hangs /files off the API base URL', () {
    expect(Config.filesEndpoint, '${Config.apiBaseUrl}/files');
    expect(Config.filesEndpoint, endsWith('/files'));
  });

  test('the geo base path has no trailing slash so joins stay well formed', () {
    expect(Config.geoBasePath, isNot(endsWith('/')));
  });
}
