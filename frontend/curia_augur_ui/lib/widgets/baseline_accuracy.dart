import 'package:flutter/material.dart';

import '../models/analysis.dart';
import 'accuracy_donut.dart';

/// The "no machine learning" bar, from `predict.py`'s `meta.prediction.baseline`: if you
/// skipped the model entirely and just guessed the most common change_factor for every
/// authority, how often would you have been right?
///
/// Shown next to the model's accuracy pie because a model only earns its keep by beating
/// this number — on a dataset where 78% of councils never flip, "predict no change" is
/// already 78% accurate.
class BaselineAccuracy extends StatelessWidget {
  const BaselineAccuracy({super.key, required this.analysis});

  final Analysis analysis;

  @override
  Widget build(BuildContext context) {
    final pred = analysis.prediction;
    if (pred == null) {
      return const Center(
        child: Text('No baseline available (prediction stage has not run).'),
      );
    }
    final guess = pred.baselineMajorityClass == 1 ? 'change' : 'no change';

    return AccuracyDonut(
      title: 'Most common change factor (no ML)',
      help:
          'The bar every model has to clear. If you skipped the analysis '
          'entirely and simply guessed the most common outcome for every '
          'authority — usually "no change", because most councils do not flip — '
          'this is how often you would have been right. A model is only worth '
          'anything if it scores higher than this.',
      headline:
          'Always guess "$guess": '
          '${(pred.baselineAllAccuracy * 100).toStringAsFixed(1)}% correct '
          '(${pred.baselineCorrectAll} / ${pred.baselineTotalAll})',
      accuracy: pred.baselineAllAccuracy,
      notes: [
        'Held-out: ${(pred.baselineAccuracy * 100).toStringAsFixed(1)}% — the bar '
            'the regression has to beat.',
      ],
    );
  }
}
