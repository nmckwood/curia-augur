import 'dart:convert';

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/analysis.dart';
import 'auth_service.dart';

/// Calls the Cognito-secured files API and fetches analysis JSON from presigned URLs.
/// In local mode (Config.isLocal) it reads bundled assets instead, so the UI can be
/// run against the local pipeline output with no AWS backend.
class ApiService {
  ApiService(this._auth);

  final AuthService? _auth;

  Map<String, String> get _headers => {
        'Authorization': _auth?.idToken ?? '',
        'Content-Type': 'application/json',
      };

  /// GET /files -> list of {filename, pre_signed_url} (REQ APIs-1).
  /// Local mode enumerates the bundled analysis assets (no API call).
  Future<List<FileEntry>> listFiles() async {
    if (Config.isLocal) {
      return _listLocalFiles();
    }
    final resp = await http.get(Uri.parse(Config.filesEndpoint), headers: _headers);
    if (resp.statusCode != 200) {
      throw Exception('files API returned ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as List;
    return data
        .map((e) => FileEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Enumerate bundled analysis files (assets/analysis/*.json) via the asset manifest.
  Future<List<FileEntry>> _listLocalFiles() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final files = manifest
        .listAssets()
        .where((a) => a.startsWith('assets/analysis/') && a.endsWith('.json'))
        .map((a) => a.split('/').last)
        .toList()
      ..sort();
    return [
      for (final filename in files)
        FileEntry(filename: filename, preSignedUrl: 'asset://$filename'),
    ];
  }

  /// Fetch and parse an analysis file. Local mode reads assets/analysis/<filename>.
  Future<Analysis> fetchAnalysis(FileEntry file) async {
    if (Config.isLocal) {
      final body =
          await rootBundle.loadString('assets/analysis/${file.filename}');
      return Analysis.fromJson(jsonDecode(body) as Map<String, dynamic>);
    }
    final resp = await http.get(Uri.parse(file.preSignedUrl));
    if (resp.statusCode != 200) {
      throw Exception('analysis fetch returned ${resp.statusCode}');
    }
    return Analysis.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// Fetch the GeoJSON boundary set nearest the analysis year (REQ UI-4).
  /// Local mode reads assets/geo/<filename>.
  Future<Map<String, dynamic>> fetchGeoJson(String filename) async {
    if (Config.isLocal) {
      final body = await rootBundle.loadString('assets/geo/$filename');
      return jsonDecode(body) as Map<String, dynamic>;
    }
    final resp = await http.get(Uri.parse('${Config.geoBasePath}/$filename'));
    if (resp.statusCode != 200) {
      throw Exception('geojson fetch returned ${resp.statusCode}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }
}
