import 'package:flutter/material.dart';

import '../models/analysis.dart';
import 'info_heading.dart';

/// A written summary of the highest-value indices for the selected analysis
/// (REQUIREMENTS_2 UI-2): which deprivation indices most characterize the
/// high-change cluster, that cluster's majority-flip rate, and significance.
class AnalysisSummary extends StatelessWidget {
  const AnalysisSummary({super.key, required this.analysis});

  final Analysis analysis;

  String _short(String key) => key.split(' Decile').first.split(' Rank').first;

  /// One-paragraph readout of the supervised model, scored against the no-ML
  /// baseline. An uplift that rounds to zero is called a tie rather than a
  /// loss — "-0.0 points behind" reads as a defect.
  String _regressionSummary(PredictionMeta pred) {
    final uplift = pred.upliftOverBaseline;
    final verdict = uplift.abs() < 0.05
        ? 'matching the no-ML baseline exactly, so the deprivation indices '
              'added nothing over guessing the most common outcome'
        : uplift > 0
        ? 'beating the no-ML baseline of '
              '${(pred.baselineAccuracy * 100).toStringAsFixed(1)}% by '
              '${uplift.toStringAsFixed(1)} percentage points, so the '
              'deprivation indices carried some real signal'
        : 'falling ${(-uplift).toStringAsFixed(1)} percentage points short of '
              'the no-ML baseline of '
              '${(pred.baselineAccuracy * 100).toStringAsFixed(1)}%, so the '
              'deprivation indices added nothing over guessing the most '
              'common outcome';

    return 'Logistic regression, fit on ${pred.trainSize} authorities over '
        '${analysis.keyIndices.length} key indices and scored on the '
        '${pred.testSize} held out, called '
        '${(pred.holdoutAccuracy * 100).toStringAsFixed(1)}% correctly — '
        '$verdict.';
  }

  @override
  Widget build(BuildContext context) {
    final high = analysis.highChangeCluster;
    final pred = analysis.prediction;
    final topFeatures = analysis.featureImportance
        .take(5)
        .map((f) => _short(f.feature))
        .toList();

    final otherClusters = analysis.clusters
        .where((c) => !c.isHighChange)
        .toList();
    final otherSize = otherClusters.fold<int>(0, (s, c) => s + c.size);
    final otherFlip = otherSize == 0
        ? 0.0
        : otherClusters.fold<double>(
                0,
                (s, c) => s + c.meanChangeFactor * c.size,
              ) /
              otherSize;

    final highFlipPct = high == null
        ? '—'
        : (high.meanChangeFactor * 100).toStringAsFixed(0);
    final otherFlipPct = (otherFlip * 100).toStringAsFixed(0);


    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const InfoHeading(
              title: 'Summary',
              help:
                  'A plain-English readout of both models on this pair of '
                  'years. The k-means half says how many groups the clustering '
                  'found, how often the majority party flipped inside the '
                  'high-change group versus the rest, and how well each group '
                  'scored when read as a prediction. The logistic regression '
                  'half is the supervised contrast: a linear model on the '
                  'log-odds of a flip, fit on most of the authorities and '
                  'scored on the ones it never saw, reported against the '
                  'no-ML baseline of simply guessing the most common outcome. '
                  'Beating that baseline is the bar — below it, the '
                  'deprivation indices carried no usable signal. The indices '
                  'listed at the bottom are the ones that most set the '
                  'high-change cluster apart.',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              'K-means grouped ${analysis.constituencies.length} local authorities into '
              '${analysis.clusters.length} clusters using the deprivation change indices. '
              '${high == null ? '' : 'The high-change cluster contains ${high.size} authorities, '
                        'where the majority party flipped in $highFlipPct% of them, versus '
                        '$otherFlipPct% across the other clusters. '}',
              style: const TextStyle(height: 1.4),
            ),
            const SizedBox(height: 8),
            // REQUIREMENTS_4: score the clustering itself as a predictor.
            Text(
              'Scored as a prediction (change_factor_cluster), the clusters called '
              '${(analysis.clusterAccuracy * 100).toStringAsFixed(1)}% of authorities '
              'correctly (${analysis.clusterCorrectCount} of '
              '${analysis.constituencies.length}).',
              style: const TextStyle(height: 1.4),
            ),
            const SizedBox(height: 4),
            ...analysis.clustersByAccuracy.map(
              (c) => Text(
                '#${c.accuracyRank}  Cluster ${c.clusterId} '
                '(${c.size} authorities, predicts '
                '${c.predictedChangeFactor == 1 ? 'change' : 'no change'}): '
                '${(c.accuracy * 100).toStringAsFixed(1)}% accurate',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            // REQUIREMENTS_5 UI-1: the summary covers both models, so the
            // supervised contrast is readable without scrolling to widget 3.
            if (pred != null) ...[
              const SizedBox(height: 8),
              Text(_regressionSummary(pred), style: const TextStyle(height: 1.4)),
            ],
            const SizedBox(height: 8),
            const Text(
              'Indices most characterizing the high-change cluster:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            ...List.generate(topFeatures.length, (i) {
              return Text('${i + 1}. ${topFeatures[i]}');
            }),
          ],
        ),
      ),
    );
  }
}
