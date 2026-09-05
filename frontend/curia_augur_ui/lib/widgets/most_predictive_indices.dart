import 'package:flutter/material.dart';

import '../models/analysis.dart';
import '../theme/palette.dart';
import 'info_heading.dart';

/// Ranks each deprivation index by its individual (univariate) held-out predictive
/// accuracy, drawn as horizontal bars against the majority-class baseline. Indices that
/// beat the baseline are blue and carry a tick; those that don't are grey with a dash
/// (WCAG 2.2 SC 1.4.1 — the tick, not the hue, is what states the verdict).
class MostPredictiveIndices extends StatelessWidget {
  const MostPredictiveIndices({super.key, required this.analysis});

  final Analysis analysis;

  String _short(String key) => key.split(' Decile').first.split(' Rank').first;

  @override
  Widget build(BuildContext context) {
    final pred = analysis.prediction;
    if (pred == null || pred.perYearIndexDetails.isEmpty) {
      return const Text('No per-year predictiveness data available.');
    }
    final baseline = pred.baselineAccuracy;
    final details = pred.perYearIndexDetails;
    final maxAcc = details.first.holdoutAccuracy.clamp(0.01, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const InfoHeading(
          title: 'Most predictive deprivation indices',
          help:
              'Each bar is one deprivation index used entirely on its own to '
              'predict a majority flip, scored on the held-out split. The '
              'vertical marker is the no-ML baseline — always guessing the most '
              'common outcome. Only bars that reach past that marker (ticked) '
              'carry any real signal; the rest are noise dressed up as a number.',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 2),
        Text(
          'Individual held-out accuracy. Baseline "predict no change" = '
          '${(baseline * 100).toStringAsFixed(1)}%.',
          style: const TextStyle(fontSize: 13, color: Palette.mutedInk),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: details.length,
            itemBuilder: (context, i) {
              final d = details[i];
              final beatsBaseline = d.holdoutAccuracy > baseline + 1e-9;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 200,
                      child: Text(
                        _short(d.feature),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final w = constraints.maxWidth;
                          return Stack(
                            children: [
                              Container(
                                height: 16,
                                color: const Color(0xFFECEFF1),
                              ),
                              Container(
                                height: 16,
                                width: w * (d.holdoutAccuracy / maxAcc),
                                // SC 1.4.1: "beats the baseline" is also stated by the
                                // bar crossing the marker and by the ✓/– glyph below,
                                // so the hue is not the only signal.
                                color: beatsBaseline
                                    ? Palette.noChange
                                    : const Color(0xFFB0BEC5),
                              ),
                              // Baseline marker.
                              Positioned(
                                left: w * (baseline / maxAcc),
                                child: Container(
                                  height: 16,
                                  width: 2,
                                  color: Palette.mutedInk,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    SizedBox(
                      width: 52,
                      child: Text(
                        '${(d.holdoutAccuracy * 100).toStringAsFixed(1)}%',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    // Non-colour restatement of the same fact (SC 1.4.1).
                    SizedBox(
                      width: 28,
                      child: Tooltip(
                        message: beatsBaseline
                            ? 'Beats the no-ML baseline'
                            : 'Does not beat the no-ML baseline',
                        child: Icon(
                          beatsBaseline
                              ? Icons.check_circle_outline
                              : Icons.remove_circle_outline,
                          size: 16,
                          color: beatsBaseline
                              ? Palette.positiveInk
                              : Palette.mutedInk,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
