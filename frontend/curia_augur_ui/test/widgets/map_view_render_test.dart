// Rendering tests for MapView.
//
// The OpenStreetMap TileLayer cannot fetch tiles in a widget test; flutter_map logs the
// failures and carries on, so the polygon layer, legend and tooltip are all inspectable.
// These tests assert the WCAG 2.2 SC 1.4.1 guarantee that the two binary states differ by
// OUTLINE as well as by fill colour.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:curia_augur_ui/models/analysis.dart';
import 'package:curia_augur_ui/theme/palette.dart';
import 'package:curia_augur_ui/widgets/map_view.dart';

import '../helpers.dart';

Map<String, dynamic> _feature(String name, {String type = 'Polygon'}) {
  const ring = [
    [-1.0, 53.0],
    [-1.0, 53.5],
    [-0.5, 53.5],
    [-0.5, 53.0],
    [-1.0, 53.0],
  ];
  return {
    'properties': {'LAD22NM': name},
    'geometry': {
      'type': type,
      'coordinates': type == 'Polygon' ? [ring] : [
        [ring],
      ],
    },
  };
}

Map<String, dynamic> _geoJson(List<Map<String, dynamic>> features) => {
  'features': features,
};

Widget _map({
  required Map<String, dynamic> geoJson,
  required Map<String, Constituency> byName,
  MapColorMode mode = MapColorMode.changed,
  String metric = 'change_factor',
}) => harness(
  MapView(
    geoJson: geoJson,
    byName: byName,
    metric: metric,
    colorMode: mode,
  ),
  height: 420,
);

Map<String, Constituency> _byName(List<Map<String, dynamic>> json) => {
  for (final j in json)
    MapView.normalize(j['Local Authority District name'] as String):
        Constituency.fromJson(j),
};

// The layer is generic over the hit value, so the type must be spelled out in full.
List<Polygon<Constituency>> _polygons(WidgetTester tester) => tester
    .widget<PolygonLayer<Constituency>>(find.byType(PolygonLayer<Constituency>))
    .polygons;

void main() {
  final twoAuthorities = _byName([
    constituencyJson(name: 'Held', changeFactor: 0, changeFactorCluster: 0),
    constituencyJson(name: 'Flipped', changeFactor: 1, changeFactorCluster: 1),
  ]);
  final geo = _geoJson([_feature('Held'), _feature('Flipped')]);

  testWidgets('draws one polygon per matched GeoJSON feature', (tester) async {
    await tester.pumpWidget(_map(geoJson: geo, byName: twoAuthorities));
    await tester.pump();

    expect(_polygons(tester), hasLength(2));
  });

  testWidgets('skips features with no matching analysis row', (tester) async {
    await tester.pumpWidget(
      _map(
        geoJson: _geoJson([_feature('Held'), _feature('Not In The Analysis')]),
        byName: twoAuthorities,
      ),
    );
    await tester.pump();

    expect(_polygons(tester), hasLength(1));
  });

  testWidgets('skips features with no name property', (tester) async {
    final nameless = _feature('x')..['properties'] = {'CODE': 'E06000001'};
    await tester.pumpWidget(
      _map(geoJson: _geoJson([nameless]), byName: twoAuthorities),
    );
    await tester.pump();

    expect(_polygons(tester), isEmpty);
  });

  testWidgets('expands a MultiPolygon into its rings', (tester) async {
    await tester.pumpWidget(
      _map(
        geoJson: _geoJson([_feature('Held', type: 'MultiPolygon')]),
        byName: twoAuthorities,
      ),
    );
    await tester.pump();

    expect(_polygons(tester), hasLength(1));
    expect(_polygons(tester).first.points, hasLength(5));
  });

  testWidgets('ignores an unknown geometry type rather than throwing', (tester) async {
    await tester.pumpWidget(
      _map(
        geoJson: _geoJson([_feature('Held', type: 'Point')]),
        byName: twoAuthorities,
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(_polygons(tester), isEmpty);
  });

  testWidgets('no change is blue with a thin solid outline', (tester) async {
    await tester.pumpWidget(
      _map(geoJson: _geoJson([_feature('Held')]), byName: twoAuthorities),
    );
    await tester.pump();

    final polygon = _polygons(tester).single;
    expect(polygon.color, Palette.noChange.withValues(alpha: 0.6));
    expect(polygon.pattern, const StrokePattern.solid());
    expect(polygon.borderStrokeWidth, lessThan(1.0));
  });

  testWidgets('change is orange with a thicker dashed outline', (tester) async {
    // SC 1.4.1: the outline, not just the hue, distinguishes the two states.
    await tester.pumpWidget(
      _map(geoJson: _geoJson([_feature('Flipped')]), byName: twoAuthorities),
    );
    await tester.pump();

    final polygon = _polygons(tester).single;
    expect(polygon.color, Palette.change.withValues(alpha: 0.6));
    expect(polygon.pattern, isNot(const StrokePattern.solid()));
    expect(polygon.borderStrokeWidth, greaterThan(1.0));
  });

  testWidgets('the cluster map keeps the same convention as the actual map', (
    tester,
  ) async {
    // Both maps must read the same way, or a side-by-side comparison misleads.
    await tester.pumpWidget(
      _map(
        geoJson: _geoJson([_feature('Held')]),
        byName: _byName([
          constituencyJson(name: 'Held', changeFactor: 1, changeFactorCluster: 0),
        ]),
        mode: MapColorMode.clusterPredicted,
      ),
    );
    await tester.pump();

    // change_factor is 1 but change_factor_cluster is 0, so the cluster map shows blue.
    expect(_polygons(tester).single.color, Palette.noChange.withValues(alpha: 0.6));
  });

  testWidgets('the predicted modes fall back to "no change" for absent predictions', (
    tester,
  ) async {
    for (final mode in [
      MapColorMode.predicted,
      MapColorMode.predictedPerYear,
    ]) {
      await tester.pumpWidget(
        _map(
          geoJson: _geoJson([_feature('Held')]),
          byName: twoAuthorities,
          mode: mode,
        ),
      );
      await tester.pump();

      // The -1 sentinel must read as 0, not as a third state.
      expect(_polygons(tester).single.color, Palette.noChange.withValues(alpha: 0.6));
    }
  });

  testWidgets('metric mode uses the continuous ramp and a solid outline', (
    tester,
  ) async {
    await tester.pumpWidget(
      _map(
        geoJson: geo,
        byName: twoAuthorities,
        mode: MapColorMode.metric,
        metric: 'Income Decile delta',
      ),
    );
    await tester.pump();

    for (final polygon in _polygons(tester)) {
      expect(polygon.pattern, const StrokePattern.solid());
    }
  });

  group('legend', () {
    testWidgets('binary legends spell out the outline style, not just the colour', (
      tester,
    ) async {
      await tester.pumpWidget(_map(geoJson: geo, byName: twoAuthorities));
      await tester.pump();

      expect(find.text('Election result'), findsOneWidget);
      expect(find.text('No change (solid outline)'), findsOneWidget);
      expect(find.text('Changed (dashed outline)'), findsOneWidget);
    });

    testWidgets('each mode gets its own title', (tester) async {
      const expected = {
        MapColorMode.changed: 'Election result',
        MapColorMode.clusterPredicted: 'Cluster prediction',
        MapColorMode.predicted: 'Predicted (common)',
        MapColorMode.predictedPerYear: 'Predicted (per-year)',
      };

      for (final entry in expected.entries) {
        await tester.pumpWidget(
          _map(geoJson: geo, byName: twoAuthorities, mode: entry.key),
        );
        await tester.pump();
        expect(find.text(entry.value), findsOneWidget, reason: '${entry.key}');
      }
    });

    testWidgets('metric mode shows the ramp with its min and max', (tester) async {
      await tester.pumpWidget(
        _map(
          geoJson: geo,
          byName: twoAuthorities,
          mode: MapColorMode.metric,
          metric: 'Income Decile delta',
        ),
      );
      await tester.pump();

      expect(find.text('Income Decile delta'), findsOneWidget);
      expect(find.text('2'), findsNWidgets(2)); // min and max are both 2 here
    });
  });

  testWidgets('the map carries a semantics description of what it shows', (
    tester,
  ) async {
    await tester.pumpWidget(_map(geoJson: geo, byName: twoAuthorities));
    await tester.pump();

    final labels = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .map((s) => s.properties.label)
        .whereType<String>()
        .toList();

    expect(
      labels,
      contains(
        allOf(
          contains('local authority districts'),
          contains('whether the election result actually changed'),
        ),
      ),
    );
  });

  testWidgets('an empty geojson renders nothing and does not throw', (tester) async {
    await tester.pumpWidget(_map(geoJson: const {}, byName: twoAuthorities));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(_polygons(tester), isEmpty);
  });
}
