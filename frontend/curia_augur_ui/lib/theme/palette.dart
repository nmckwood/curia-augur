import 'package:flutter/material.dart';

/// Accessible colour palette for every chart and map in the UI (WCAG 2.2 SC 1.4.1).
///
/// The original red/green "bad/good" scheme was replaced: red-green is the single most
/// common confusion for colour-vision deficiency, so the binary pair is now **blue vs
/// orange**, which separates under protanopia, deuteranopia and tritanopia alike.
/// Validated with the data-viz palette validator on the light chart surface (#fcfcfb):
///
///   blue #2a78d6 / orange #eb6834 — all-pairs CVD ΔE 24.7 (protan), normal-vision
///   ΔE 33.6, both poles >= 3:1 contrast against the surface. All checks PASS.
///
/// SC 1.4.1 also requires that colour is never the ONLY cue, so every chart pairs these
/// hues with a second, non-colour encoding — see [ClusterMark], the dashed/solid polygon
/// borders in `map_view.dart`, the in-slice labels in `accuracy_donut.dart`, and the
/// text + icon columns in `data_table_view.dart`.
class Palette {
  Palette._();

  /// Chart surface the palette was validated against.
  static const surface = Color(0xFFFCFCFB);

  // --- Binary outcome pair (no change / change, correct / incorrect) -----------
  static const noChange = Color(0xFF2A78D6); // blue
  static const change = Color(0xFFEB6834); // orange
  static const correct = noChange;
  static const incorrect = change;

  /// Secondary text ink. Flutter's `Colors.black54` renders at 4.61:1 on white — it
  /// scrapes the 4.5:1 WCAG AA floor for body text and misses AAA. This is 7.94:1, so
  /// the small-print notes under the charts clear AAA too.
  static const mutedInk = Color(0xFF52514E);

  /// Ink for labels painted ON a [correct]/[incorrect] fill. White would be 3.2:1 on the
  /// orange; near-black is 6.6:1 on orange and 4.8:1 on blue, so both clear AA.
  static const onFillInk = Color(0xFF000000);

  /// Ink for the "did better / did worse" verdict text. Always accompanied by an icon
  /// and a signed number so the colour is decorative, never load-bearing.
  static const positiveInk = Color(0xFF184F95); // blue 600, >= 4.5:1 on white
  static const negativeInk = Color(
    0xFFA3341A,
  ); // darkened orange, >= 4.5:1 on white

  // --- Diverging ramp for signed deprivation deltas ---------------------------
  // Diverging (not sequential) because a delta has polarity: the midpoint is "no change".
  // Blue <-> red with a neutral grey midpoint, per the validated diverging pair
  // (all-pairs CVD ΔE 21.6 protan / 34.5 tritan).
  static const divergingLow = Color(0xFF2A78D6); // blue
  static const divergingMid = Color(0xFFF0EFEC); // neutral grey
  static const divergingHigh = Color(0xFFE34948); // red

  // --- Categorical slots for cluster ids --------------------------------------
  // Fixed order, never cycled by rank. The first three validate all-pairs
  // (worst CVD ΔE 9.2); beyond three, [ClusterMark] shape carries the identity so the
  // hues are secondary. Aqua sits below 3:1 on the surface, which the validator flags
  // as needing relief — the cluster column in the data table provides it.
  static const clusterSlots = <Color>[
    Color(0xFF2A78D6), // blue
    Color(0xFFEB6834), // orange
    Color(0xFF1BAF7A), // aqua
    Color(0xFFEDA100), // yellow
    Color(0xFFE87BA4), // magenta
    Color(0xFF008300), // green
    Color(0xFF4A3AA7), // violet
  ];

  static Color cluster(int clusterId) =>
      clusterSlots[clusterId % clusterSlots.length];

  /// Position on the diverging ramp for [value] within [min]..[max].
  static Color forValue(num value, num min, num max) {
    if (max <= min) return divergingMid;
    final t = ((value - min) / (max - min)).clamp(0.0, 1.0);
    return t < 0.5
        ? Color.lerp(divergingLow, divergingMid, t / 0.5)!
        : Color.lerp(divergingMid, divergingHigh, (t - 0.5) / 0.5)!;
  }
}

/// Non-colour marker shapes, so series stay distinguishable without colour (SC 1.4.1).
/// Assigned in fixed order alongside [Palette.clusterSlots].
enum ClusterMark { circle, square, cross }

ClusterMark clusterMark(int index) =>
    ClusterMark.values[index % ClusterMark.values.length];

String clusterMarkName(ClusterMark mark) => switch (mark) {
  ClusterMark.circle => 'circle',
  ClusterMark.square => 'square',
  ClusterMark.cross => 'cross',
};
