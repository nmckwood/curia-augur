import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/analysis.dart';
import '../theme/palette.dart';
import 'mark_swatch.dart';

Color clusterColor(int clusterId) => Palette.cluster(clusterId);

/// XY scatter of the clusters (REQUIREMENTS_2 UI-1): each constituency plotted at its
/// 2-component PCA coordinates, with a hover/tap tooltip.
///
/// WCAG 2.2 SC 1.4.1: each cluster gets both a validated categorical hue AND a marker
/// shape (circle / square / cross), assigned in the same fixed order, so clusters remain
/// distinguishable under any colour-vision deficiency and in greyscale. The legend shows
/// the shape, and the tooltip names the cluster in text.
class ClusterScatter extends StatelessWidget {
  const ClusterScatter({super.key, required this.constituencies});

  final List<Constituency> constituencies;

  @override
  Widget build(BuildContext context) {
    // Lookup from rounded (x,y) back to the constituency for tooltip text.
    final byPoint = <String, Constituency>{
      for (final c in constituencies) _key(c.pcaX, c.pcaY): c,
    };
    final clusterIds = constituencies.map((c) => c.clusterId).toSet().toList()
      ..sort();

    final spots = [
      for (final c in constituencies)
        ScatterSpot(
          c.pcaX,
          c.pcaY,
          dotPainter: markDotPainter(
            clusterMark(c.clusterId),
            clusterColor(c.clusterId).withValues(alpha: 0.8),
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          children: [
            for (final id in clusterIds)
              MarkLegend(
                mark: clusterMark(id),
                color: clusterColor(id),
                label: 'Cluster $id',
              ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ScatterChart(
            ScatterChartData(
              scatterSpots: spots,
              titlesData: const FlTitlesData(
                leftTitles: AxisTitles(
                  axisNameWidget: Text('PCA component 2'),
                  sideTitles: SideTitles(showTitles: true, reservedSize: 32),
                ),
                bottomTitles: AxisTitles(
                  axisNameWidget: Text('PCA component 1'),
                  sideTitles: SideTitles(showTitles: true, reservedSize: 24),
                ),
                topTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              scatterTouchData: ScatterTouchData(
                enabled: true,
                touchTooltipData: ScatterTouchTooltipData(
                  getTooltipItems: (spot) {
                    final c = byPoint[_key(spot.x, spot.y)];
                    if (c == null) return null;
                    return ScatterTooltipItem(
                      '${c.name}\n'
                      'Cluster ${c.clusterId}\n'
                      '${c.changeFactor == 1 ? 'Majority changed' : 'No change'}',
                      textStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _key(num x, num y) =>
      '${x.toStringAsFixed(6)},${y.toStringAsFixed(6)}';
}
