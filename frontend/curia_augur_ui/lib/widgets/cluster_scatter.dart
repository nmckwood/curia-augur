import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/analysis.dart';

/// Fixed palette for cluster ids (KMeans k is 2..7).
const List<Color> kClusterColors = [
  Color(0xFF1565C0), // blue
  Color(0xFFC62828), // red
  Color(0xFF2E7D32), // green
  Color(0xFF6A1B9A), // purple
  Color(0xFFEF6C00), // orange
  Color(0xFF00838F), // teal
  Color(0xFFAD1457), // pink
];

Color clusterColor(int clusterId) =>
    kClusterColors[clusterId % kClusterColors.length];

/// XY scatter of the clusters (REQUIREMENTS_2 UI-1): each constituency plotted at its
/// 2-component PCA coordinates, coloured by cluster, with a hover/tap tooltip.
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
          dotPainter: FlDotCirclePainter(
            color: clusterColor(c.clusterId).withValues(alpha: 0.75),
            radius: 4,
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
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 12, height: 12, color: clusterColor(id)),
                const SizedBox(width: 4),
                Text('Cluster $id'),
              ]),
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
                topTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
