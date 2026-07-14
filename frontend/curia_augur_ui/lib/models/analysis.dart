/// Data models for the ML analysis output (mirrors the REQ ML-6 schema).

class FileEntry {
  FileEntry({required this.filename, required this.preSignedUrl});

  final String filename;
  final String preSignedUrl;

  factory FileEntry.fromJson(Map<String, dynamic> json) => FileEntry(
        filename: json['filename'] as String,
        preSignedUrl: json['pre_signed_url'] as String,
      );
}

class Constituency {
  Constituency({
    required this.name,
    required this.council,
    required this.clusterId,
    required this.changeFactor,
    required this.deciles,
    required this.pcaX,
    required this.pcaY,
    required this.predictedChange,
    required this.predictedChangePerYear,
  });

  final String name;
  final String council;
  final int clusterId;
  final int changeFactor; // 1 = majority party flipped, 0 = unchanged
  final Map<String, int> deciles;
  final double pcaX;
  final double pcaY;
  final int predictedChange; // change_factor_deprivation_key_indices: predicted 0/1 (-1 if absent)
  final int predictedChangePerYear; // change_factor_per_year_key_indices: predicted 0/1 (-1 if absent)

  factory Constituency.fromJson(Map<String, dynamic> json) => Constituency(
        name: json['Local Authority District name'] as String,
        council: (json['council'] ?? '') as String,
        clusterId: json['cluster_id'] as int,
        changeFactor: json['change_factor'] as int,
        deciles: ((json['deprivation_deciles'] ?? {}) as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, (v as num).toInt())),
        pcaX: ((json['pca_x'] ?? 0) as num).toDouble(),
        pcaY: ((json['pca_y'] ?? 0) as num).toDouble(),
        predictedChange:
            (json['change_factor_deprivation_key_indices'] ?? -1) as int,
        predictedChangePerYear:
            (json['change_factor_per_year_key_indices'] ?? -1) as int,
      );

  bool get predictionCorrect => predictedChange == changeFactor;
  bool get perYearPredictionCorrect => predictedChangePerYear == changeFactor;
}

/// One deprivation index's individual (univariate) held-out predictive accuracy.
class IndexPredictiveness {
  IndexPredictiveness({
    required this.feature,
    required this.holdoutAccuracy,
    required this.rank,
  });

  final String feature;
  final double holdoutAccuracy;
  final int rank;

  factory IndexPredictiveness.fromJson(Map<String, dynamic> json) =>
      IndexPredictiveness(
        feature: json['feature'] as String,
        holdoutAccuracy: ((json['holdout_accuracy'] ?? 0) as num).toDouble(),
        rank: json['rank'] as int,
      );
}

class FeatureImportance {
  FeatureImportance({
    required this.feature,
    required this.deviationScore,
    required this.rank,
  });

  final String feature;
  final double deviationScore;
  final int rank;

  factory FeatureImportance.fromJson(Map<String, dynamic> json) =>
      FeatureImportance(
        feature: json['feature'] as String,
        deviationScore: ((json['deviation_score'] ?? 0) as num).toDouble(),
        rank: json['rank'] as int,
      );
}

class ClusterSummary {
  ClusterSummary({
    required this.clusterId,
    required this.size,
    required this.meanChangeFactor,
    required this.isHighChange,
  });

  final int clusterId;
  final int size;
  final double meanChangeFactor; // proportion of authorities whose majority flipped
  final bool isHighChange;

  factory ClusterSummary.fromJson(Map<String, dynamic> json) => ClusterSummary(
        clusterId: json['cluster_id'] as int,
        size: json['size'] as int,
        meanChangeFactor: ((json['mean_change_factor'] ?? 0) as num).toDouble(),
        isHighChange: (json['is_high_change_cluster'] ?? false) as bool,
      );
}

class PredictionMeta {
  PredictionMeta({
    required this.method,
    required this.holdoutAccuracy,
    required this.trainAccuracy,
    required this.trainSize,
    required this.testSize,
    required this.baselineAccuracy,
    required this.perYearHoldoutAccuracy,
    required this.perYearIndices,
    required this.perYearIndexDetails,
  });

  final String method;
  final double holdoutAccuracy; // COMMON-indices model, accuracy on the unseen test split
  final double trainAccuracy;
  final int trainSize;
  final int testSize;
  final double baselineAccuracy; // majority-class held-out accuracy (the bar to beat)
  final double perYearHoldoutAccuracy; // per-year best-indices benchmark, held-out
  final List<String> perYearIndices;
  final List<IndexPredictiveness> perYearIndexDetails;

  factory PredictionMeta.fromJson(Map<String, dynamic> json) => PredictionMeta(
        method: (json['method'] ?? '') as String,
        holdoutAccuracy: ((json['holdout_accuracy'] ?? 0) as num).toDouble(),
        trainAccuracy: ((json['train_accuracy'] ?? 0) as num).toDouble(),
        trainSize: (json['train_size'] ?? 0) as int,
        testSize: (json['test_size'] ?? 0) as int,
        baselineAccuracy: ((json['baseline_accuracy'] ?? 0) as num).toDouble(),
        perYearHoldoutAccuracy:
            ((json['per_year_holdout_accuracy'] ?? 0) as num).toDouble(),
        perYearIndices:
            ((json['per_year_indices'] ?? []) as List).cast<String>(),
        perYearIndexDetails: ((json['per_year_index_details'] ?? []) as List)
            .map((e) => IndexPredictiveness.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class Analysis {
  Analysis({
    required this.featuresUsed,
    required this.constituencies,
    required this.featureImportance,
    required this.clusters,
    required this.significant,
    required this.pValue,
    required this.keyIndices,
    required this.prediction,
  });

  final List<String> featuresUsed;
  final List<Constituency> constituencies;
  final List<FeatureImportance> featureImportance;
  final List<ClusterSummary> clusters;
  final bool significant;
  final double pValue;
  final List<String> keyIndices; // REQUIREMENTS_3 common indices used for prediction
  final PredictionMeta? prediction;

  factory Analysis.fromJson(Map<String, dynamic> json) {
    final meta = json['meta'] as Map<String, dynamic>;
    final sig = (json['significance_test'] ?? {}) as Map<String, dynamic>;
    return Analysis(
      prediction: meta['prediction'] == null
          ? null
          : PredictionMeta.fromJson(meta['prediction'] as Map<String, dynamic>),
      keyIndices: ((meta['key_indices'] ?? []) as List).cast<String>(),
      featuresUsed: (meta['features_used'] as List).cast<String>(),
      constituencies: (json['constituencies'] as List)
          .map((e) => Constituency.fromJson(e as Map<String, dynamic>))
          .toList(),
      featureImportance: ((json['feature_importance'] ?? []) as List)
          .map((e) => FeatureImportance.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.rank.compareTo(b.rank)),
      clusters: ((json['clusters'] ?? []) as List)
          .map((e) => ClusterSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
      significant: (sig['significant'] ?? false) as bool,
      pValue: ((sig['p_value'] ?? 1) as num).toDouble(),
    );
  }

  /// Selectable colouring metrics: change_factor plus every deprivation feature.
  List<String> get metrics => ['change_factor', ...featuresUsed];

  ClusterSummary? get highChangeCluster {
    for (final c in clusters) {
      if (c.isHighChange) return c;
    }
    return null;
  }

  /// Whether prediction (change_factor_deprivation_key_indices) is available.
  bool get hasPredictions =>
      constituencies.isNotEmpty && constituencies.first.predictedChange >= 0;

  /// Held-out accuracy (fit on train, measured on the unseen test split). Falls back to
  /// in-sample accuracy over all constituencies only if no prediction metadata is present.
  double get accuracy {
    if (prediction != null) return prediction!.holdoutAccuracy;
    if (constituencies.isEmpty) return 0;
    final correct = constituencies.where((c) => c.predictionCorrect).length;
    return correct / constituencies.length;
  }
}
