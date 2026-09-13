import 'package:amazon_cognito_identity_dart_2/cognito.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config.dart';

/// Handles Cognito authentication and token persistence. Users must be
/// authenticated before any data is shown (REQ UI-8).
class AuthService {
  AuthService()
      : _userPool = CognitoUserPool(
          Config.cognitoUserPoolId,
          Config.cognitoClientId,
        );

  final CognitoUserPool _userPool;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  CognitoUserSession? _session;

  bool get isAuthenticated => _session?.isValid() ?? false;

  String? get idToken => _session?.getIdToken().getJwtToken();

  /// Attempt to restore a session from stored refresh token on startup.
  Future<bool> tryRestore() async {
    final email = await _storage.read(key: 'email');
    final refresh = await _storage.read(key: 'refreshToken');
    if (email == null || refresh == null) return false;
    try {
      final user = CognitoUser(email, _userPool);
      _session = await user.refreshSession(CognitoRefreshToken(refresh));
      return isAuthenticated;
    } catch (_) {
      await signOut();
      return false;
    }
  }

  Future<void> signIn(String email, String password) async {
    final user = CognitoUser(email, _userPool);
    final details =
        AuthenticationDetails(username: email, password: password);
    _session = await user.authenticateUser(details);
    await _storage.write(key: 'email', value: email);
    final refresh = _session?.getRefreshToken()?.getToken();
    if (refresh != null) {
      await _storage.write(key: 'refreshToken', value: refresh);
    }
  }

  Future<void> signOut() async {
    _session = null;
    await _storage.deleteAll();
  }
}
