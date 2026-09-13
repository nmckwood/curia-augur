import 'package:flutter/material.dart';

import '../config.dart';
import '../models/analysis.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/analysis_summary.dart';
import '../widgets/info_heading.dart';
import '../widgets/kmeans_widget.dart';
import '../widgets/lad_data_widget.dart';
import '../widgets/logistic_regression_widget.dart';

/// Clearance reserved down the right edge for the always-on page scrollbar:
/// Flutter draws an 8px thumb plus its track margin as an overlay, so without
/// a gutter it lands on top of the cards.
const double _scrollbarGutter = 16;

/// Main authenticated screen: banner, file dropdown, map and data table.
/// In local mode `auth` is null and the sign-out action is hidden.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.auth, required this.onSignOut});

  final AuthService? auth;
  final VoidCallback onSignOut;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final ApiService _api = ApiService(widget.auth);

  List<FileEntry> _files = [];
  FileEntry? _selectedFile;
  Analysis? _analysis;
  Map<String, dynamic>? _geoJson;
  String? _error;
  bool _loading = false;

  final ScrollController _pageScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  @override
  void dispose() {
    _pageScroll.dispose();
    super.dispose();
  }

  Future<void> _loadFiles() async {
    setState(() => _loading = true);
    try {
      _files = await _api.listFiles();
      // In local mode, preselect the requested file (LOCAL_FILENAME) or the first,
      // while the dropdown still lists every bundled analysis.
      if (Config.isLocal && _files.isNotEmpty) {
        final preferred = _files.firstWhere(
          (f) => f.filename == Config.localFilename,
          orElse: () => _files.first,
        );
        await _selectFile(preferred);
      }
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// REQ UI-4: pick the boundary set nearest the file's target year.
  String _geoFileFor(String filename) => filename.contains('2026')
      ? 'boundaries_2025.geojson'
      : 'boundaries_2022.geojson';

  Future<void> _selectFile(FileEntry file) async {
    setState(() {
      _loading = true;
      _selectedFile = file;
      _error = null;
    });
    try {
      final analysis = await _api.fetchAnalysis(file);
      final geo = await _api.fetchGeoJson(_geoFileFor(file.filename));
      setState(() {
        _analysis = analysis;
        _geoJson = geo;
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final analysis = _analysis;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Curia Augur'),
        actions: [
          if (Config.requiresAuth)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Sign out',
              onPressed: widget.onSignOut,
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DropdownButton<FileEntry>(
                  hint: const Text('Select an analysis file'),
                  value: _selectedFile,
                  items: _files
                      .map(
                        (f) =>
                            DropdownMenuItem(value: f, child: Text(f.filename)),
                      )
                      .toList(),
                  onChanged: (f) => f == null ? null : _selectFile(f),
                ),
                const SizedBox(width: 8),
                const InfoHint(
                  label: 'analysis file',
                  help:
                      'Each file is one comparison: two editions of the '
                      'deprivation indices paired with the two local elections '
                      'that followed them. Naming is d_<start>_d_<end>_'
                      'le_<start>_le_<end>. Changing it reloads every chart '
                      'and the map boundaries for that period.',
                ),
              ],
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            if (analysis != null && _geoJson != null)
              Expanded(
                // REQUIREMENTS_5: a permanent scrollbar down the right edge.
                // The cards are inset past it so the thumb never sits on top
                // of their content.
                child: Scrollbar(
                  controller: _pageScroll,
                  thumbVisibility: true,
                  trackVisibility: true,
                  child: SingleChildScrollView(
                    controller: _pageScroll,
                    padding: const EdgeInsets.only(right: _scrollbarGutter),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Widget 1: Analysis Summary
                        AnalysisSummary(analysis: analysis),
                        const SizedBox(height: 16),
                        // Widget 2: k-means (maps, scatter/pie, LAD table).
                        // Both cards size themselves from their contents — a
                        // fixed outer height here would have to be kept in sync
                        // with every inner row and overflows when it drifts.
                        KmeansWidget(analysis: analysis, geoJson: _geoJson!),
                        const SizedBox(height: 16),
                        // Widget 3: Logistic Regression Analysis
                        LogisticRegressionWidget(analysis: analysis),
                        const SizedBox(height: 16),
                        // Widget 4: the full local authority table
                        LadDataWidget(
                          constituencies: analysis.constituencies,
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
