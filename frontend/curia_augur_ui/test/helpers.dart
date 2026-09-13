// Shared builders and helpers for the Curia Augur Dart tests.
//
// Everything here is plain data: no network, no platform channels, no AWS. Services that
// would need those (ApiService, AuthService) are not covered — see test/README.md.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:curia_augur_ui/models/analysis.dart';

/// One constituency's JSON, in the shape the ML pipeline actually emits.
Map<String, dynamic> constituencyJson({
  String name = 'Testshire',
  String council = 'Testshire Council',
  int clusterId = 0,
  int changeFactor = 0,
  int changeFactorCluster = 0,
  int? predictedChange,
  int? predictedChangePerYear,
  Map<String, num>? deciles,
  double pcaX = 0.1,
  double pcaY = 0.2,
}) => {
  'Local Authority District name': name,
  'council': council,
  'cluster_id': clusterId,
  'change_factor': changeFactor,
  'change_factor_cluster': changeFactorCluster,
  'deprivation': deciles ?? const {'Income Decile delta': 2},
  'pca_x': pcaX,
  'pca_y': pcaY,
  if (predictedChange != null)
    'change_factor_deprivation_key_indices': predictedChange,
  if (predictedChangePerYear != null)
    'change_factor_per_year_key_indices': predictedChangePerYear,
};

Map<String, dynamic> clusterJson({
  int clusterId = 0,
  int size = 10,
  double meanChangeFactor = 0.2,
  bool isHighChange = false,
  int predictedChangeFactor = 0,
  double accuracy = 0.8,
  int nCorrect = 8,
  int accuracyRank = 1,
}) => {
  'cluster_id': clusterId,
  'size': size,
  'mean_change_factor': meanChangeFactor,
  'is_high_change_cluster': isHighChange,
  'predicted_change_factor': predictedChangeFactor,
  'accuracy': accuracy,
  'n_correct': nCorrect,
  'accuracy_rank': accuracyRank,
};

Map<String, dynamic> predictionJson({
  double holdoutAccuracy = 0.62,
  double trainAccuracy = 0.65,
  int trainSize = 70,
  int testSize = 30,
  double baselineAccuracy = 0.55,
  int majorityClass = 0,
  double baselineAllAccuracy = 0.56,
  int baselineCorrectAll = 56,
  int baselineTotalAll = 100,
  double perYearHoldoutAccuracy = 0.60,
}) => {
  'method': 'logistic-regression',
  'holdout_accuracy': holdoutAccuracy,
  'train_accuracy': trainAccuracy,
  'train_size': trainSize,
  'test_size': testSize,
  'baseline_accuracy': baselineAccuracy,
  'baseline': {
    'majority_class': majorityClass,
    'holdout_accuracy': baselineAccuracy,
    'all_accuracy': baselineAllAccuracy,
    'n_correct_all': baselineCorrectAll,
    'n_total_all': baselineTotalAll,
  },
  'per_year_holdout_accuracy': perYearHoldoutAccuracy,
  'per_year_indices': const ['Income Rank delta'],
  'per_year_index_details': const [
    {'feature': 'Income Rank delta', 'holdout_accuracy': 0.61, 'rank': 1},
    {'feature': 'Crime Rank delta', 'holdout_accuracy': 0.40, 'rank': 2},
  ],
};

Map<String, dynamic> analysisJson({
  List<Map<String, dynamic>>? constituencies,
  List<Map<String, dynamic>>? clusters,
  Map<String, dynamic>? prediction,
  double pValue = 0.42,
  List<String> keyIndices = const ['Income Rank delta'],
}) => {
  'meta': {
    'k': 2,
    'features_used': const ['Income Rank delta', 'Crime Rank delta'],
    'n_constituencies': (constituencies ?? const []).length,
    'key_indices': keyIndices,
    if (prediction != null) 'prediction': prediction,
  },
  'clusters': clusters ?? [clusterJson()],
  'feature_importance': const [
    {'feature': 'Income Rank delta', 'deviation_score': 0.9, 'rank': 1},
    {'feature': 'Crime Rank delta', 'deviation_score': 0.3, 'rank': 2},
  ],
  'constituencies': constituencies ?? [constituencyJson()],
};

/// A two-cluster analysis where the cluster prediction is right 3 times in 4.
Analysis sampleAnalysis({Map<String, dynamic>? prediction}) => Analysis.fromJson(
  analysisJson(
    prediction: prediction ?? predictionJson(),
    clusters: [
      clusterJson(
        clusterId: 0,
        size: 2,
        isHighChange: false,
        predictedChangeFactor: 0,
        accuracy: 1.0,
        nCorrect: 2,
        accuracyRank: 1,
      ),
      clusterJson(
        clusterId: 1,
        size: 2,
        isHighChange: true,
        meanChangeFactor: 0.5,
        predictedChangeFactor: 1,
        accuracy: 0.5,
        nCorrect: 1,
        accuracyRank: 2,
      ),
    ],
    constituencies: [
      constituencyJson(name: 'A', changeFactor: 0, changeFactorCluster: 0),
      constituencyJson(name: 'B', changeFactor: 0, changeFactorCluster: 0),
      constituencyJson(
        name: 'C',
        clusterId: 1,
        changeFactor: 1,
        changeFactorCluster: 1,
      ),
      constituencyJson(
        name: 'D',
        clusterId: 1,
        changeFactor: 0,
        changeFactorCluster: 1,
      ),
    ],
  ),
);

/// Wraps a widget with Material scaffolding at a generous fixed size, so charts that use
/// Expanded have room and do not overflow the default 800x600 test surface.
Widget harness(Widget child, {double width = 1000, double height = 640}) =>
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, height: height, child: child),
        ),
      ),
    );

/// WCAG 2.x contrast ratio. [foreground] is composited over [background] first, so a
/// semi-transparent ink (Flutter's `Colors.black54`) is scored as it actually renders
/// rather than as pure black.
double contrastRatio(Color foreground, Color background) {
  final a = Color.from(
    alpha: 1,
    red: foreground.r * foreground.a + background.r * (1 - foreground.a),
    green: foreground.g * foreground.a + background.g * (1 - foreground.a),
    blue: foreground.b * foreground.a + background.b * (1 - foreground.a),
  );
  final b = background;

  double luminance(Color c) {
    double channel(double v) =>
        v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  }

  final first = luminance(a);
  final second = luminance(b);
  final hi = first > second ? first : second;
  final lo = first > second ? second : first;
  return (hi + 0.05) / (lo + 0.05);
}
