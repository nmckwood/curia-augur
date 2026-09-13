import 'package:flutter/material.dart';

import '../models/analysis.dart';
import 'accuracy_donut.dart';

/// Pie chart of prediction accuracy (REQUIREMENTS_3 UI-3): percentage of constituencies
/// whose predicted change matched the actual outcome. Defaults to the cluster prediction
/// (REQUIREMENTS_4 UI-2), which is scored over every authority rather than a held-out
/// split because the clustering is unsupervised — it never saw change_factor.
class AccuracyPie extends StatelessWidget {
  const AccuracyPie({
    super.key,
    required this.analysis,
    this.source = PredictionSource.cluster,
  });

  final Analysis analysis;
  final PredictionSource source;

  @override
  Widget build(BuildContext context) {
    final pred = analysis.prediction;
    final isCluster = source == PredictionSource.cluster;
    final acc = switch (source) {
      PredictionSource.cluster => analysis.clusterAccuracy,
      PredictionSource.perYear => pred?.perYearHoldoutAccuracy ?? 0,
      PredictionSource.common => analysis.accuracy, // held-out where available
    };
    final total = isCluster
        ? analysis.constituencies.length
        : (pred?.testSize ?? analysis.constituencies.length);
    final correct = isCluster
        ? analysis.clusterCorrectCount
        : (acc * total).round();
    final scope = isCluster || pred == null ? 'all authorities' : 'held-out';
    final label = switch (source) {
      PredictionSource.cluster => 'Cluster prediction',
      PredictionSource.perYear => 'Per-year best indices',
      PredictionSource.common => 'Common indices',
    };

    return AccuracyDonut(
      title: 'Prediction accuracy',
      help: isCluster
          ? 'How often the cluster prediction matched the actual result, across '
                'every authority. The lines underneath break it down per cluster, '
                'ranked most accurate first — a cluster that predicts "change" is '
                'scored on the authorities that really did change, and vice versa. '
                'Judge this against the "no ML" pie beside it: if it is not higher, '
                'the clustering added nothing.'
          : 'How often this model\'s prediction matched the actual result on the '
                'held-out test split — authorities the model never saw while fitting.',
      headline:
          '$label: ${(acc * 100).toStringAsFixed(1)}% correct '
          '($correct / $total $scope)',
      accuracy: acc,
      notes: isCluster
          ? [
              for (final c in analysis.clustersByAccuracy)
                '#${c.accuracyRank} cluster ${c.clusterId} '
                    '(predicts ${c.predictedChangeFactor == 1 ? 'change' : 'no change'}): '
                    '${(c.accuracy * 100).toStringAsFixed(1)}% '
                    '(${c.nCorrect} / ${c.size})',
            ]
          : [
              if (pred != null)
                'Baseline (predict "no change"): '
                    '${(pred.baselineAccuracy * 100).toStringAsFixed(1)}%',
            ],
    );
  }
}
