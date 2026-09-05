// Tests for MapView's pure logic.
//
// The map itself is NOT rendered here: flutter_map's TileLayer fetches OpenStreetMap
// tiles over HTTP, which a widget test cannot do, and stubbing the tile provider plus
// the layer hit-testing is more machinery than it earns. What is tested is the name
// normalisation that joins GeoJSON features to analysis rows — the part that silently
// drops authorities from the map when it goes wrong.

import 'package:flutter_test/flutter_test.dart';

import 'package:curia_augur_ui/widgets/map_view.dart';

void main() {
  group('MapView.normalize', () {
    test('lower-cases and collapses whitespace', () {
      expect(MapView.normalize('  Isle   Of   Wight '), 'isle of wight');
    });

    test('strips punctuation that differs between the two datasets', () {
      // ONS boundary files and the IoD tables disagree on commas and apostrophes.
      expect(
        MapView.normalize('Herefordshire, County of'),
        MapView.normalize('Herefordshire County of'),
      );
      expect(MapView.normalize("King's Lynn"), 'king s lynn');
    });

    test('keeps digits', () {
      expect(MapView.normalize('District 9'), 'district 9');
    });

    test('is idempotent', () {
      const raw = 'Bristol, City of';
      expect(
        MapView.normalize(MapView.normalize(raw)),
        MapView.normalize(raw),
      );
    });

    test('an empty or punctuation-only name normalises to empty', () {
      expect(MapView.normalize(''), '');
      expect(MapView.normalize('  ,.-  '), '');
    });

    test('names that differ only in case and punctuation collide as intended', () {
      expect(
        MapView.normalize('ST. HELENS'),
        MapView.normalize('St Helens'),
      );
    });
  });

  group('MapColorMode', () {
    test('covers the metric map and all four binary modes', () {
      expect(MapColorMode.values, hasLength(5));
      expect(MapColorMode.values, contains(MapColorMode.clusterPredicted));
    });
  });
}
