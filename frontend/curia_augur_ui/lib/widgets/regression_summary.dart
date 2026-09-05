import 'package:flutter/material.dart';

import '../models/analysis.dart';
import '../theme/palette.dart';
import 'info_heading.dart';

/// Written summary of the regression stage (`predict.py`), read against the no-ML
/// baseline shown beside it. Everything here comes from `meta.prediction`: the model is a
/// logistic regression — a linear model on the log-odds of a majority flip — fit on the
/// train split over the common key indices, and scored on the unseen test split.
class RegressionSummary extends StatelessWidget {
  const RegressionSummary({super.key, required this.analysis});

  final Analysis analysis;

  String _short(String key) => key.split(' Decile').first.split(' Rank').first;

  @override
  Widget build(BuildContext context) {
    final pred = analysis.prediction;
    if (pred == null) {
      return const Center(
        child: Text('No regression summary (prediction stage has not run).'),
      );
    }

    final uplift = pred.upliftOverBaseline;
    final beatsBaseline = uplift > 0;
    final best = pred.perYearIndexDetails.isEmpty
        ? null
        : pred.perYearIndexDetails.first;

    final verdict = beatsBaseline
        ? 'The regression beats the no-ML guess by '
              '${uplift.toStringAsFixed(1)} percentage points, so the deprivation '
              'indices carry some real signal for this pair of years.'
        : 'The regression does not beat the no-ML guess '
              '(${uplift.toStringAsFixed(1)} points), so on this pair of years the '
              'deprivation indices add nothing over simply predicting the most common '
              'outcome.';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const InfoHeading(
                title: 'Regression summary',
                help:
                    'A supervised model run alongside the clustering, for '
                    'contrast. Logistic regression is a linear model that '
                    'weights each deprivation index and outputs the odds of a '
                    'majority flip. It is fit on a random 70% of authorities and '
                    'scored on the unseen 30%, so the held-out number is an '
                    'honest estimate. The uplift line is that score minus the '
                    'no-ML baseline: positive means deprivation data carried '
                    'real signal, zero or negative means it did not.',
              ),
              const SizedBox(height: 6),
              Text(
                'Logistic regression (a linear model on the log-odds of a majority '
                'flip) fit on ${pred.trainSize} authorities over '
                '${analysis.keyIndices.length} key indices, scored on '
                '${pred.testSize} held out.',
                style: const TextStyle(height: 1.35),
              ),
              const SizedBox(height: 6),
              _row('Model (held-out)', pred.holdoutAccuracy),
              _row('Model (train)', pred.trainAccuracy),
              _row('Most common change factor', pred.baselineAccuracy),
              _row('Per-year best indices', pred.perYearHoldoutAccuracy),
              const Divider(height: 16),
              // SC 1.4.1: the arrow icon and the signed number both state the
              // direction, so the ink colour only reinforces it.
              Row(
                children: [
                  Icon(
                    beatsBaseline ? Icons.trending_up : Icons.trending_down,
                    size: 18,
                    semanticLabel: beatsBaseline
                        ? 'better than baseline'
                        : 'worse than baseline',
                    color: beatsBaseline
                        ? Palette.positiveInk
                        : Palette.negativeInk,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Uplift over baseline: ${uplift >= 0 ? '+' : ''}'
                      '${uplift.toStringAsFixed(1)} pp',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: beatsBaseline
                            ? Palette.positiveInk
                            : Palette.negativeInk,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(verdict, style: const TextStyle(height: 1.35)),
              if (best != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Best single index: ${_short(best.feature)} at '
                  '${(best.holdoutAccuracy * 100).toStringAsFixed(1)}% held-out.',
                  style: const TextStyle(fontSize: 12, color: Palette.mutedInk),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, double value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(child: Text(label, style: const TextStyle(fontSize: 13))),
        Text(
          '${(value * 100).toStringAsFixed(1)}%',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}
