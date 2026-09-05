import 'package:flutter/material.dart';

import '../config.dart';
import '../models/analysis.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/accuracy_pie.dart';
import '../widgets/analysis_summary.dart';
import '../widgets/baseline_accuracy.dart';
import '../widgets/cluster_scatter.dart';
import '../widgets/data_table_view.dart';
import '../widgets/info_heading.dart';
import '../widgets/map_view.dart';
import '../widgets/prediction_scatter.dart';
import '../widgets/regression_summary.dart';
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
        _metric = 'change_factor';
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _labelledMap(String title, String help, Widget map) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: InfoHeading(title: title, help: help),
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
            Tooltip(
              message:
                  'Open a second page ranking each deprivation index on its '
                  'own predictive power for this pair of years, with its own map, '
                  'scatter and accuracy pie.',
              child: TextButton.icon(
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
            ),
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
                const SizedBox(width: 24),
                if (analysis != null) ...[
                  DropdownButton<String>(
                    value: _metric,
                    items: analysis.metrics
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (m) =>
                        m == null ? null : setState(() => _metric = m),
                  ),
                  const SizedBox(width: 8),
                  const InfoHint(
                    label: 'deprivation index',
                    help:
                        'Picks which deprivation index the data table is '
                        'sorted and shaded by. "delta" means the change in that '
                        'index between the two editions: a positive value means '
                        'the area moved towards less deprivation. It does not '
                        'change the two maps, which always show actual result '
                        'versus cluster prediction.',
                  ),
                ],
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
                        MapView.normalize(c.name): c,
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
                                // REQUIREMENTS_4 UI-1: exactly two projections, both
                                // using green = no change, so a disagreement between
                                // actual and cluster prediction shows as a colour flip.
                                Expanded(
                                  child: _labelledMap(
                                    'Actual: election result changed',
                                    'What actually happened. An authority is '
                                        'shaded orange with a dashed outline if '
                                        'the largest party on the council changed '
                                        'between the two elections, and blue with '
                                        'a solid outline if it did not.',
                                    MapView(
                                      geoJson: _geoJson!,
                                      metric: _metric,
                                      byName: byName,
                                      colorMode: MapColorMode.changed,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _labelledMap(
                                    'Cluster prediction (change_factor_cluster)',
                                    'What the k-means clustering would have '
                                        'predicted from deprivation data alone. '
                                        'Authorities in the cluster with the '
                                        'highest flip rate are marked "change" '
                                        '(orange, dashed). Compare it with the map '
                                        'on the left: every authority whose colour '
                                        'differs between the two maps is one the '
                                        'clustering got wrong.',
                                    MapView(
                                      geoJson: _geoJson!,
                                      metric: _metric,
                                      byName: byName,
                                      colorMode: MapColorMode.clusterPredicted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          const InfoHeading(
                            title: 'Cluster scatter (PCA projection)',
                            help:
                                'Every authority plotted by its deprivation '
                                'profile, squashed from 16 dimensions down to 2 '
                                'by principal component analysis so it can be '
                                'drawn. The axes have no units — what matters is '
                                'which points sit together. Colour AND marker '
                                'shape both show the cluster; hover a point for '
                                'its name and result.',
                          ),
                          SizedBox(
                            height: 360,
                            child: ClusterScatter(
                              constituencies: analysis.constituencies,
                            ),
                          ),
                          const SizedBox(height: 12),
                          // REQUIREMENTS_4 UI-2/UI-3: both scored on the cluster
                          // prediction, which every analysis now carries.
                          const InfoHeading(
                            title: 'Cluster prediction vs actual change',
                            help:
                                'Scores the clustering as if it were a '
                                'predictor, against the actual results and '
                                'against doing no machine learning at all.',
                          ),
                          SizedBox(
                            height: 340,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: PredictionScatter(
                                    constituencies: analysis.constituencies,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 2,
                                  child: AccuracyPie(analysis: analysis),
                                ),
                                const SizedBox(width: 12),
                                // The "no ML" bar, so the pie beside it has something to
                                // be judged against, plus the regression read against it.
                                Expanded(
                                  flex: 2,
                                  child: BaselineAccuracy(analysis: analysis),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 3,
                                  child: RegressionSummary(analysis: analysis),
                                ),
                              ],
                            ),
                          ),
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
