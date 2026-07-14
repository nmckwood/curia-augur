import 'package:flutter/material.dart';

import '../models/analysis.dart';

/// Ranks each deprivation index by its individual (univariate) held-out predictive
/// accuracy, drawn as horizontal bars against the majority-class baseline. Indices that
/// beat the baseline are green; those that don't are grey (they carry no real signal).
class MostPredictiveIndices extends StatelessWidget {
  const MostPredictiveIndices({super.key, required this.analysis});

  final Analysis analysis;

  String _short(String key) =>
      key.split(' Decile').first.split(' Rank').first;

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
        Text(
          'Most predictive deprivation indices (individual held-out accuracy). '
          'Baseline "predict no change" = ${(baseline * 100).toStringAsFixed(1)}%.',
          style: const TextStyle(fontSize: 13),
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
                      child: Text(_short(d.feature),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12)),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final w = constraints.maxWidth;
                          return Stack(
                            children: [
                              Container(height: 16, color: const Color(0xFFECEFF1)),
                              Container(
                                height: 16,
                                width: w * (d.holdoutAccuracy / maxAcc),
                                color: beatsBaseline
                                    ? const Color(0xFF2E7D32)
                                    : const Color(0xFFB0BEC5),
                              ),
                              // Baseline marker.
                              Positioned(
                                left: w * (baseline / maxAcc),
                                child: Container(
                                    height: 16, width: 2, color: Colors.black54),
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
