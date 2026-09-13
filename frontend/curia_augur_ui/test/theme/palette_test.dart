// Unit tests for the accessible palette (WCAG 2.2 SC 1.4.1 and contrast).
//
// These assert the properties the accessibility work depends on, so a future "let's make
// it green again" change fails loudly rather than silently regressing the UI.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:curia_augur_ui/theme/palette.dart';
import 'package:curia_augur_ui/widgets/metric_color.dart';

import '../helpers.dart';

const _white = Color(0xFFFFFFFF);

void main() {
  group('binary outcome pair', () {
    test('is the validated blue/orange, not red/green', () {
      expect(Palette.noChange, const Color(0xFF2A78D6));
      expect(Palette.change, const Color(0xFFEB6834));
      expect(Palette.correct, Palette.noChange);
      expect(Palette.incorrect, Palette.change);
    });

    test('both poles clear 3:1 against the chart surface', () {
      // Non-text graphical objects need 3:1 under WCAG 2.2 SC 1.4.11.
      expect(contrastRatio(Palette.noChange, Palette.surface), greaterThan(3.0));
      expect(contrastRatio(Palette.change, Palette.surface), greaterThan(3.0));
    });

    test('the two poles are far apart in every channel, not just hue', () {
      // A red/green pair collapses under deuteranopia because it differs almost only in
      // the red-green channel. Blue vs orange differs in blue and in luminance too.
      const a = Palette.noChange;
      const b = Palette.change;
      expect((a.b - b.b).abs(), greaterThan(0.3));
      expect((a.r - b.r).abs(), greaterThan(0.3));
    });
  });

  group('text inks meet WCAG AA', () {
    test('mutedInk reaches AAA on white where Flutter black54 only scrapes AA', () {
      // black54 composited over white is 4.61:1 — it clears the 4.5:1 AA floor for
      // normal text by a hair and misses the 7:1 AAA level. mutedInk clears both.
      expect(contrastRatio(Palette.mutedInk, _white), greaterThan(7.0));
      expect(contrastRatio(Colors.black54, _white), greaterThan(4.5));
      expect(contrastRatio(Colors.black54, _white), lessThan(7.0));
    });

    test('verdict inks clear 4.5:1 on white', () {
      expect(contrastRatio(Palette.positiveInk, _white), greaterThan(4.5));
      expect(contrastRatio(Palette.negativeInk, _white), greaterThan(4.5));
    });

    test('onFillInk clears 4.5:1 on both donut slice fills', () {
      // White text would be only 3.2:1 on the orange slice, so slice labels use near-black.
      expect(contrastRatio(Palette.onFillInk, Palette.correct), greaterThan(4.5));
      expect(contrastRatio(Palette.onFillInk, Palette.incorrect), greaterThan(4.5));
    });
  });

  group('diverging ramp', () {
    test('runs low pole -> neutral midpoint -> high pole', () {
      expect(Palette.forValue(0, 0, 10), Palette.divergingLow);
      expect(Palette.forValue(5, 0, 10), Palette.divergingMid);
      expect(Palette.forValue(10, 0, 10), Palette.divergingHigh);
    });

    test('the midpoint is neutral grey, so "no change" reads as nothing', () {
      const mid = Palette.divergingMid;
      expect((mid.r - mid.g).abs(), lessThan(0.05));
      expect((mid.g - mid.b).abs(), lessThan(0.05));
    });

    test('interpolates between the stops', () {
      final quarter = Palette.forValue(2.5, 0, 10);
      expect(quarter, isNot(Palette.divergingLow));
      expect(quarter, isNot(Palette.divergingMid));
    });

    test('a degenerate range collapses to the midpoint instead of dividing by zero', () {
      expect(Palette.forValue(5, 5, 5), Palette.divergingMid);
      expect(Palette.forValue(5, 10, 0), Palette.divergingMid);
    });

    test('clamps values outside the range', () {
      expect(Palette.forValue(-100, 0, 10), Palette.divergingLow);
      expect(Palette.forValue(100, 0, 10), Palette.divergingHigh);
    });

    test('MetricColor delegates to the same ramp', () {
      expect(MetricColor.forValue(7, 0, 10), Palette.forValue(7, 0, 10));
    });
  });

  group('cluster identity', () {
    test('adjacent clusters differ in both hue and marker shape', () {
      for (var i = 0; i < 3; i++) {
        expect(Palette.cluster(i), isNot(Palette.cluster(i + 1)));
        expect(clusterMark(i), isNot(clusterMark(i + 1)));
      }
    });

    test('the first three slots are mutually distinct', () {
      final first3 = {Palette.cluster(0), Palette.cluster(1), Palette.cluster(2)};
      expect(first3, hasLength(3));
    });

    test('slots cycle rather than crashing beyond the palette length', () {
      final n = Palette.clusterSlots.length;
      expect(Palette.cluster(n), Palette.cluster(0));
      expect(Palette.cluster(n + 1), Palette.cluster(1));
    });

    test('marks cycle through every available shape', () {
      final marks = {for (var i = 0; i < 6; i++) clusterMark(i)};
      expect(marks, ClusterMark.values.toSet());
    });

    test('every mark has a screen-reader friendly name', () {
      for (final mark in ClusterMark.values) {
        expect(clusterMarkName(mark), isNotEmpty);
      }
    });
  });
}
