import 'package:flutter/material.dart';

import '../models/analysis.dart';
import '../widgets/accuracy_pie.dart';
import '../widgets/map_view.dart';
import '../widgets/most_predictive_indices.dart';
import '../widgets/prediction_scatter.dart';

/// Second page (REQUIREMENTS_3 follow-up): since no common indices generalize, this page
/// explores per-year predictiveness — the most predictive individual indices for THIS
/// analysis, and the map/scatter/pie for a model trained on that year's best indices.
class PerYearScreen extends StatelessWidget {
  const PerYearScreen({
    super.key,
    required this.filename,
    required this.analysis,
    required this.geoJson,
  });

  final String filename;
  final Analysis analysis;
  final Map<String, dynamic> geoJson;

  @override
  Widget build(BuildContext context) {
    final byName = {
      for (final c in analysis.constituencies) MapView.normalize(c.name): c
    };
    final pred = analysis.prediction;
    final headline = pred == null
        ? ''
        : 'Per-year best-indices model: '
            '${(pred.perYearHoldoutAccuracy * 100).toStringAsFixed(1)}% held-out '
            'vs baseline ${(pred.baselineAccuracy * 100).toStringAsFixed(1)}%.';

    return Scaffold(
      appBar: AppBar(title: Text('Per-year predictiveness — $filename')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Can deprivation indices predict a change of majority in this year? '
                'Only indices whose bar extends past the baseline marker carry real signal. '
                '$headline',
                style: const TextStyle(height: 1.4),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 380,
                child: MostPredictiveIndices(analysis: analysis),
              ),
              const SizedBox(height: 16),
              const Text('Predicted change (per-year best indices)',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(
                height: 420,
                child: MapView(
                  geoJson: geoJson,
                  metric: 'change_factor',
                  byName: byName,
                  colorMode: MapColorMode.predictedPerYear,
                ),
              ),
              const SizedBox(height: 16),
              const Text('Predicted vs actual change (per-year best indices)',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(
                height: 320,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: PredictionScatter(
                        constituencies: analysis.constituencies,
                        perYear: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AccuracyPie(analysis: analysis, perYear: true),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
