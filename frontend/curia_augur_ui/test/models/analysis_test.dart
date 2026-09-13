// Unit tests for the analysis data models — the JSON contract between the Python ML
// pipeline and the Flutter UI. A field renamed on either side should fail here.

import 'package:flutter_test/flutter_test.dart';

import 'package:curia_augur_ui/models/analysis.dart';

import '../helpers.dart';

void main() {
  group('FileEntry', () {
    test('parses the files API payload', () {
      final entry = FileEntry.fromJson({
        'filename': 'analysis-d_2015.json',
        'pre_signed_url': 'https://signed/x',
      });

      expect(entry.filename, 'analysis-d_2015.json');
      expect(entry.preSignedUrl, 'https://signed/x');
    });
  });

  group('Constituency', () {
    test('parses every field the pipeline emits', () {
      final c = Constituency.fromJson(
        constituencyJson(
          name: 'Testshire',
          council: 'Testshire CC',
          clusterId: 3,
          changeFactor: 1,
          changeFactorCluster: 1,
          predictedChange: 0,
          predictedChangePerYear: 1,
          pcaX: 1.5,
          pcaY: -2.5,
        ),
      );

      expect(c.name, 'Testshire');
      expect(c.council, 'Testshire CC');
      expect(c.clusterId, 3);
      expect(c.changeFactor, 1);
      expect(c.changeFactorCluster, 1);
      expect(c.predictedChange, 0);
      expect(c.predictedChangePerYear, 1);
      expect(c.pcaX, 1.5);
      expect(c.pcaY, -2.5);
      expect(c.deciles['Income Decile delta'], 2);
    });

    test('defaults the absent prediction fields to -1', () {
      // An analysis written before the prediction stage runs has no prediction fields;
      // -1 is the sentinel the UI uses to hide prediction-only widgets.
      final c = Constituency.fromJson(constituencyJson());

      expect(c.predictedChange, -1);
      expect(c.predictedChangePerYear, -1);
    });

    test('defaults change_factor_cluster to 0 when absent', () {
      final json = constituencyJson()..remove('change_factor_cluster');
      expect(Constituency.fromJson(json).changeFactorCluster, 0);
    });

    test('defaults a missing council and deciles rather than throwing', () {
      final json = constituencyJson()
        ..remove('council')
        ..remove('deprivation');
      final c = Constituency.fromJson(json);

      expect(c.council, '');
      expect(c.deciles, isEmpty);
    });

    test('correctness getters compare each prediction against the actual', () {
      final c = Constituency.fromJson(
        constituencyJson(
          changeFactor: 1,
          changeFactorCluster: 1,
          predictedChange: 0,
          predictedChangePerYear: 1,
        ),
      );

      expect(c.clusterPredictionCorrect, isTrue);
      expect(c.predictionCorrect, isFalse);
      expect(c.perYearPredictionCorrect, isTrue);
    });

    test('predictionFor and correctFor select the right series', () {
      final c = Constituency.fromJson(
        constituencyJson(
          changeFactor: 1,
          changeFactorCluster: 1,
          predictedChange: 0,
          predictedChangePerYear: 1,
        ),
      );

      expect(c.predictionFor(PredictionSource.cluster), 1);
      expect(c.predictionFor(PredictionSource.common), 0);
      expect(c.predictionFor(PredictionSource.perYear), 1);
      expect(c.correctFor(PredictionSource.cluster), isTrue);
      expect(c.correctFor(PredictionSource.common), isFalse);
    });
  });

  group('ClusterSummary', () {
    test('parses the REQUIREMENTS_4 scoring fields', () {
      final c = ClusterSummary.fromJson(
        clusterJson(
          clusterId: 1,
          size: 78,
          meanChangeFactor: 0.23,
          isHighChange: true,
          predictedChangeFactor: 1,
          accuracy: 0.231,
          nCorrect: 18,
          accuracyRank: 2,
        ),
      );

      expect(c.clusterId, 1);
      expect(c.size, 78);
      expect(c.isHighChange, isTrue);
      expect(c.predictedChangeFactor, 1);
      expect(c.accuracy, closeTo(0.231, 1e-9));
      expect(c.nCorrect, 18);
      expect(c.accuracyRank, 2);
    });

    test('tolerates an analysis written before the scoring fields existed', () {
      final c = ClusterSummary.fromJson({
        'cluster_id': 0,
        'size': 5,
        'mean_change_factor': 0.1,
      });

      expect(c.isHighChange, isFalse);
      expect(c.accuracy, 0);
      expect(c.accuracyRank, 0);
    });
  });

  group('PredictionMeta', () {
    test('parses the model scores and the no-ML baseline block', () {
      final p = PredictionMeta.fromJson(
        predictionJson(
          holdoutAccuracy: 0.517,
          baselineAccuracy: 0.575,
          majorityClass: 0,
          baselineAllAccuracy: 0.569,
          baselineCorrectAll: 165,
          baselineTotalAll: 290,
        ),
      );

      expect(p.method, 'logistic-regression');
      expect(p.holdoutAccuracy, closeTo(0.517, 1e-9));
      expect(p.baselineAccuracy, closeTo(0.575, 1e-9));
      expect(p.baselineMajorityClass, 0);
      expect(p.baselineAllAccuracy, closeTo(0.569, 1e-9));
      expect(p.baselineCorrectAll, 165);
      expect(p.baselineTotalAll, 290);
      expect(p.perYearIndexDetails, hasLength(2));
      expect(p.perYearIndexDetails.first.rank, 1);
    });

    test('uplift is the model minus the baseline in percentage points', () {
      final beats = PredictionMeta.fromJson(
        predictionJson(holdoutAccuracy: 0.70, baselineAccuracy: 0.60),
      );
      final loses = PredictionMeta.fromJson(
        predictionJson(holdoutAccuracy: 0.517, baselineAccuracy: 0.575),
      );

      expect(beats.upliftOverBaseline, closeTo(10.0, 1e-6));
      expect(loses.upliftOverBaseline, closeTo(-5.8, 1e-6));
    });

    test('defaults the baseline block when it is absent', () {
      final json = predictionJson()..remove('baseline');
      final p = PredictionMeta.fromJson(json);

      expect(p.baselineMajorityClass, 0);
      expect(p.baselineAllAccuracy, 0);
      expect(p.baselineTotalAll, 0);
    });
  });

  group('Analysis', () {
    test('feature importance is sorted by rank regardless of input order', () {
      final json = analysisJson();
      json['feature_importance'] = [
        {'feature': 'B', 'deviation_score': 0.1, 'rank': 2},
        {'feature': 'A', 'deviation_score': 0.9, 'rank': 1},
      ];

      final a = Analysis.fromJson(json);

      expect(a.featureImportance.map((f) => f.feature), ['A', 'B']);
    });

    test('metrics offers change_factor plus every deprivation feature', () {
      expect(sampleAnalysis().metrics, [
        'change_factor',
        'Income Rank delta',
        'Crime Rank delta',
      ]);
    });

    test('highChangeCluster finds the flagged cluster', () {
      expect(sampleAnalysis().highChangeCluster!.clusterId, 1);
    });

    test('highChangeCluster is null when nothing is flagged', () {
      final a = Analysis.fromJson(analysisJson(clusters: [clusterJson()]));
      expect(a.highChangeCluster, isNull);
    });

    test('clusterAccuracy counts the constituencies the clustering called right', () {
      // A and B: predict 0, actual 0 -> correct. C: predict 1, actual 1 -> correct.
      // D: predict 1, actual 0 -> wrong.
      final a = sampleAnalysis();

      expect(a.clusterCorrectCount, 3);
      expect(a.clusterAccuracy, closeTo(0.75, 1e-9));
    });

    test('clusterAccuracy of an empty analysis is zero, not NaN', () {
      final a = Analysis.fromJson(analysisJson(constituencies: []));
      expect(a.clusterAccuracy, 0);
    });

    test('clustersByAccuracy orders by rank and does not mutate clusters', () {
      final a = sampleAnalysis();

      expect(a.clustersByAccuracy.map((c) => c.clusterId), [0, 1]);
      expect(a.clusters.map((c) => c.clusterId), [0, 1]);
    });

    test('accuracy prefers the held-out score from the prediction meta', () {
      final a = sampleAnalysis(prediction: predictionJson(holdoutAccuracy: 0.42));
      expect(a.accuracy, closeTo(0.42, 1e-9));
    });

    test('accuracy falls back to in-sample when there is no prediction meta', () {
      final a = Analysis.fromJson(
        analysisJson(
          prediction: null,
          constituencies: [
            constituencyJson(name: 'A', changeFactor: 1, predictedChange: 1),
            constituencyJson(name: 'B', changeFactor: 0, predictedChange: 1),
          ],
        ),
      );

      expect(a.prediction, isNull);
      expect(a.accuracy, closeTo(0.5, 1e-9));
    });

    test('hasPredictions reflects whether the prediction stage has run', () {
      final without = Analysis.fromJson(analysisJson());
      final with_ = Analysis.fromJson(
        analysisJson(
          constituencies: [constituencyJson(predictedChange: 1)],
        ),
      );

      expect(without.hasPredictions, isFalse);
      expect(with_.hasPredictions, isTrue);
    });
  });
}
