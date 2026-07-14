import 'package:flutter/material.dart';

import 'config.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';

void main() {
  runApp(const CuriaAugurApp());
}

class CuriaAugurApp extends StatefulWidget {
  const CuriaAugurApp({super.key});

  @override
  State<CuriaAugurApp> createState() => _CuriaAugurAppState();
}

class _CuriaAugurAppState extends State<CuriaAugurApp> {
  // No auth when login isn't required (local asset mode or SKIP_AUTH).
  final AuthService? _auth = Config.requiresAuth ? AuthService() : null;
  bool _restoring = true;

  @override
  void initState() {
    super.initState();
    if (!Config.requiresAuth) {
      _restoring = false;
    } else {
      _auth!.tryRestore().whenComplete(() {
        if (mounted) setState(() => _restoring = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Curia Augur',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: Builder(
        builder: (context) {
          if (!Config.requiresAuth) {
            return HomeScreen(auth: null, onSignOut: () {});
          }
          if (_restoring) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          final auth = _auth!;
          if (auth.isAuthenticated) {
            return HomeScreen(
              auth: auth,
              onSignOut: () async {
                await auth.signOut();
                setState(() {});
              },
            );
          }
          return LoginScreen(
            auth: auth,
            onSignedIn: () => setState(() {}),
          );
        },
      ),
    );
  }
}
