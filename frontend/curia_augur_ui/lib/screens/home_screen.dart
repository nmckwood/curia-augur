import 'package:flutter/material.dart';

import '../config.dart';
import '../models/analysis.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/accuracy_pie.dart';
import '../widgets/analysis_summary.dart';
import '../widgets/cluster_scatter.dart';
import '../widgets/data_table_view.dart';
import '../widgets/map_view.dart';
import '../widgets/prediction_scatter.dart';
import 'per_year_screen.dart';

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
  String _metric = 'change_factor';
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadFiles();
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
  String _geoFileFor(String filename) =>
      filename.contains('2026') ? 'boundaries_2025.geojson' : 'boundaries_2022.geojson';

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
        _metric = 'change_factor';
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _labelledMap(String title, Widget map) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(title,
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        Expanded(child: map),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final analysis = _analysis;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Curia Augur'),
        actions: [
          if (analysis != null && _geoJson != null)
            TextButton.icon(
              icon: const Icon(Icons.insights),
              label: const Text('Per-year predictiveness'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PerYearScreen(
                    filename: _selectedFile?.filename ?? '',
                    analysis: analysis,
                    geoJson: _geoJson!,
                  ),
                ),
              ),
            ),
          if (Config.requiresAuth)
            IconButton(
              icon: const Icon(Icons.logout),
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
                      .map((f) => DropdownMenuItem(
                            value: f,
                            child: Text(f.filename),
                          ))
                      .toList(),
                  onChanged: (f) => f == null ? null : _selectFile(f),
                ),
                const SizedBox(width: 24),
                if (analysis != null)
                  DropdownButton<String>(
                    value: _metric,
                    items: analysis.metrics
                        .map((m) =>
                            DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (m) =>
                        m == null ? null : setState(() => _metric = m),
                  ),
              ],
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            if (analysis != null && _geoJson != null)
              Expanded(
                child: Builder(
                  builder: (context) {
                    final byName = {
                      for (final c in analysis.constituencies)
                        MapView.normalize(c.name): c
                    };
                    return SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AnalysisSummary(analysis: analysis),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 420,
                            child: Row(
                              children: [
                                Expanded(
                                  child: _labelledMap(
                                    'Deprivation: $_metric',
                                    MapView(
                                      geoJson: _geoJson!,
                                      metric: _metric,
                                      byName: byName,
                                      colorMode: MapColorMode.metric,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _labelledMap(
                                    'Election result changed',
                                    MapView(
                                      geoJson: _geoJson!,
                                      metric: _metric,
                                      byName: byName,
                                      colorMode: MapColorMode.changed,
                                    ),
                                  ),
                                ),
                                if (analysis.hasPredictions) ...[
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _labelledMap(
                                      'Predicted change (key indices)',
                                      MapView(
                                        geoJson: _geoJson!,
                                        metric: _metric,
                                        byName: byName,
                                        colorMode: MapColorMode.predicted,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text('Cluster scatter (PCA projection)',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          SizedBox(
                            height: 360,
                            child: ClusterScatter(
                              constituencies: analysis.constituencies,
                            ),
                          ),
                          if (analysis.hasPredictions) ...[
                            const SizedBox(height: 12),
                            const Text('Predicted vs actual change',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            SizedBox(
                              height: 320,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: PredictionScatter(
                                      constituencies: analysis.constituencies,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: AccuracyPie(analysis: analysis),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 360,
                            child: DataTableView(
                              constituencies: analysis.constituencies,
                              metric: _metric,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
