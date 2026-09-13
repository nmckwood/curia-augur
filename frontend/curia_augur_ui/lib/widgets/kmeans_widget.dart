import 'package:flutter/material.dart';

import '../models/analysis.dart';
import 'cluster_correctness_pie.dart';
import 'cluster_scatter.dart';
import 'info_heading.dart';
import 'map_view.dart';

/// K-Means dedicated widget (REQUIREMENTS_5 Widget 2):
/// Row A: Two maps (actual election results vs cluster prediction)
/// Row B: PCA projection scatter and cluster correctness pie
class KmeansWidget extends StatelessWidget {
  const KmeansWidget({
    super.key,
    required this.analysis,
    required this.geoJson,
  });

  final Analysis analysis;
  final Map<String, dynamic> geoJson;

  /// Both maps colour by a binary outcome, so MapView's continuous-ramp metric
  /// never applies — it only needs a value to suppress the extra tooltip line.
  static const String _metric = 'change_factor';

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
    final byName = {
      for (final c in analysis.constituencies)
        MapView.normalize(c.name): c,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Row A: Two maps
            SizedBox(
              height: 420,
              child: Row(
                children: [
                  Expanded(
                    child: _labelledMap(
                      'Actual: election result changed',
                      'What actually happened. An authority is '
                          'shaded orange with a dashed outline if '
                          'the largest party on the council changed '
                          'between the two elections, and blue with '
                          'a solid outline if it did not.',
                      MapView(
                        geoJson: geoJson,
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
                        geoJson: geoJson,
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
            // Row B: Scatter and pie charts
            const InfoHeading(
              title: 'K-Means Analysis: PCA Projection & Correctness',
              help: 'PCA projection shows deprivation profiles. '
                  'Correctness pie shows prediction accuracy distribution.',
            ),
            SizedBox(
              height: 360,
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Cluster scatter (PCA projection)',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Expanded(
                          child: ClusterScatter(
                            constituencies: analysis.constituencies,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Cluster prediction correctness',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Expanded(
                          child: ClusterCorrectnessPie(
                            constituencies: analysis.constituencies,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
