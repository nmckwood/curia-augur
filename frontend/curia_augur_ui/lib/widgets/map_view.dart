import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/analysis.dart';
import '../theme/palette.dart';
import 'metric_color.dart';

/// How polygons are coloured. Every binary mode paints "no change" blue with a thin
/// solid outline and "change" orange with a thicker dashed outline, so the two states are
/// separable by shape alone (WCAG 2.2 SC 1.4.1).
/// - metric: continuous diverging ramp by the selected metric value (REQ UI-6).
/// - changed: binary, by the actual election result.
/// - clusterPredicted: binary, by change_factor_cluster (REQUIREMENTS_4 UI-1).
///   Deliberately shares the "changed" map's convention - blue is no change on both -
///   so the two maps sit side by side and disagreements read as differences.
/// - predicted: binary, by the common-indices predicted majority flip.
/// - predictedPerYear: binary, by the per-year best-indices predicted flip.
enum MapColorMode {
  metric,
  changed,
  clusterPredicted,
  predicted,
  predictedPerYear,
}

// WCAG 2.2 SC 1.4.1: blue/orange rather than green/red, and every binary mode also
// varies the polygon BORDER (solid vs dashed) so the two states stay distinguishable
// without relying on hue at all.
const Color _noChange = Palette.noChange;
const Color _change = Palette.change;
final StrokePattern _changePattern = StrokePattern.dashed(
  segments: const [4, 3],
);

/// Renders Local Authority District polygons over OpenStreetMap tiles, with a hover
/// tooltip and a legend. Used twice side-by-side (metric map + changed map).
class MapView extends StatefulWidget {
  const MapView({
    super.key,
    required this.geoJson,
    required this.byName,
    required this.metric,
    required this.colorMode,
  });

  final Map<String, dynamic> geoJson;
  final Map<String, Constituency> byName; // normalized LAD name -> constituency
  final String metric;
  final MapColorMode colorMode;

  static String normalize(String name) => name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  final LayerHitNotifier<Constituency> _hitNotifier = ValueNotifier(null);
  Constituency? _hovered;
  Offset _cursor = Offset.zero;

  num _metricValue(Constituency c) => widget.metric == 'change_factor'
      ? c.changeFactor
      : (c.deciles[widget.metric] ?? 0);

  /// The 0/1 state a binary mode is showing, or null in continuous metric mode.
  int? _binaryState(Constituency c) => switch (widget.colorMode) {
    MapColorMode.changed => c.changeFactor,
    MapColorMode.clusterPredicted => c.changeFactorCluster,
    MapColorMode.predicted => c.predictedChange <= 0 ? 0 : 1,
    MapColorMode.predictedPerYear => c.predictedChangePerYear <= 0 ? 0 : 1,
    MapColorMode.metric => null,
  };

  Color _colorFor(Constituency c, num minV, num maxV) {
    final state = _binaryState(c);
    if (state == null) return MetricColor.forValue(_metricValue(c), minV, maxV);
    return state == 0 ? _noChange : _change;
  }

  /// Redundant, non-colour encoding of the same binary state (SC 1.4.1).
  StrokePattern _patternFor(Constituency c) =>
      _binaryState(c) == 1 ? _changePattern : const StrokePattern.solid();

  List<Polygon<Constituency>> _buildPolygons(num minV, num maxV) {
    final polygons = <Polygon<Constituency>>[];
    final features = (widget.geoJson['features'] as List?) ?? [];
    for (final feature in features) {
      final props =
          (feature['properties'] as Map?)?.cast<String, dynamic>() ?? {};
      final name = _featureName(props);
      if (name == null) continue;
      final c = widget.byName[MapView.normalize(name)];
      if (c == null) continue;
      final color = _colorFor(c, minV, maxV);
      final isBinary = widget.colorMode != MapColorMode.metric;
      for (final ring in _rings(feature['geometry'] as Map<String, dynamic>?)) {
        polygons.add(
          Polygon<Constituency>(
            points: ring,
            color: color.withValues(alpha: 0.6),
            borderColor: const Color(0xFF263238),
            // A heavier dashed outline on the "change" state, so the two groups are
            // separable in greyscale or with any colour-vision deficiency.
            borderStrokeWidth: isBinary && _binaryState(c) == 1 ? 1.4 : 0.5,
            pattern: isBinary ? _patternFor(c) : const StrokePattern.solid(),
            hitValue: c,
          ),
        );
      }
    }
    return polygons;
  }

  String? _featureName(Map<String, dynamic> props) {
    for (final key in props.keys) {
      if (key.toUpperCase().endsWith('NM')) return props[key] as String?;
    }
    return null;
  }

  List<List<LatLng>> _rings(Map<String, dynamic>? geometry) {
    if (geometry == null) return [];
    final type = geometry['type'];
    final coords = geometry['coordinates'] as List;
    final rings = <List<LatLng>>[];
    if (type == 'Polygon') {
      for (final ring in coords) {
        rings.add(_ring(ring as List));
      }
    } else if (type == 'MultiPolygon') {
      for (final polygon in coords) {
        for (final ring in polygon as List) {
          rings.add(_ring(ring as List));
        }
      }
    }
    return rings;
  }

  List<LatLng> _ring(List coords) => coords
      .map((p) => LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()))
      .toList();

  /// Tap gives touch and keyboard-less users the same detail the hover tooltip gives
  /// mouse users; without it the tooltip would be pointer-only.
  void _onTap(TapPosition tapPosition, LatLng _) {
    final hit = _hitNotifier.value;
    setState(() {
      _cursor = tapPosition.relative ?? _cursor;
      _hovered = (hit != null && hit.hitValues.isNotEmpty)
          ? hit.hitValues.first
          : null;
    });
  }

  void _onHover(PointerHoverEvent event) {
    final hit = _hitNotifier.value;
    final hovered = (hit != null && hit.hitValues.isNotEmpty)
        ? hit.hitValues.first
        : null;
    if (hovered != _hovered || event.localPosition != _cursor) {
      setState(() {
        _cursor = event.localPosition;
        _hovered = hovered;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final values = widget.byName.values.map(_metricValue).toList();
    final minV = values.isEmpty ? 0 : values.reduce((a, b) => a < b ? a : b);
    final maxV = values.isEmpty ? 1 : values.reduce((a, b) => a > b ? a : b);

    return Semantics(
      label:
          'Map of UK local authority districts. '
          '${_semanticsSummary()} Hover or tap an authority for its details; the same '
          'values are listed in the table below.',
      child: MouseRegion(
        onHover: _onHover,
        onExit: (_) => setState(() => _hovered = null),
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: const LatLng(53.0, -1.5),
                initialZoom: 6,
                onTap: _onTap,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.curiaaugur.ui',
                ),
                PolygonLayer<Constituency>(
                  polygons: _buildPolygons(minV, maxV),
                  hitNotifier: _hitNotifier,
                ),
              ],
            ),
            Positioned(
              left: 8,
              bottom: 8,
              child: _Legend(
                mode: widget.colorMode,
                metric: widget.metric,
                minValue: minV,
                maxValue: maxV,
              ),
            ),
            if (_hovered != null)
              Positioned(
                left: _cursor.dx + 12,
                top: _cursor.dy + 12,
                child: _Tooltip(constituency: _hovered!, metric: widget.metric),
              ),
          ],
        ),
      ),
    );
  }

  String _semanticsSummary() => switch (widget.colorMode) {
    MapColorMode.changed =>
      'Shaded by whether the election result actually changed.',
    MapColorMode.clusterPredicted =>
      'Shaded by whether the cluster prediction says the result changed.',
    MapColorMode.predicted => 'Shaded by the common-indices model prediction.',
    MapColorMode.predictedPerYear =>
      'Shaded by the per-year best-indices model prediction.',
    MapColorMode.metric => 'Shaded by ${widget.metric}.',
  };
}

/// Legend for either colouring mode.
class _Legend extends StatelessWidget {
  const _Legend({
    required this.mode,
    required this.metric,
    required this.minValue,
    required this.maxValue,
  });

  final MapColorMode mode;
  final String metric;
  final num minValue;
  final num maxValue;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Card(
        color: Colors.white.withValues(alpha: 0.92),
        elevation: 3,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: switch (mode) {
            MapColorMode.changed => _binaryLegend(
              'Election result',
              'No change',
              'Changed',
            ),
            MapColorMode.clusterPredicted => _binaryLegend(
              'Cluster prediction',
              'No change',
              'Change',
            ),
            MapColorMode.predicted => _binaryLegend(
              'Predicted (common)',
              'No change',
              'Change',
            ),
            MapColorMode.predictedPerYear => _binaryLegend(
              'Predicted (per-year)',
              'No change',
              'Change',
            ),
            MapColorMode.metric => _metricLegend(),
          },
        ),
      ),
    );
  }

  Widget _binaryLegend(String title, String zeroLabel, String oneLabel) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
        const SizedBox(height: 4),
        _swatchRow(_noChange, '$zeroLabel (solid outline)', dashed: false),
        _swatchRow(_change, '$oneLabel (dashed outline)', dashed: true),
      ],
    );
  }

  /// The swatch mirrors the polygon: fill colour plus the outline style, so the legend
  /// itself is readable without colour (SC 1.4.1).
  Widget _swatchRow(Color color, String label, {required bool dashed}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CustomPaint(painter: _SwatchPainter(color, dashed)),
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _metricLegend() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          metric,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Container(
          width: 160,
          height: 12,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Palette.divergingLow,
                Palette.divergingMid,
                Palette.divergingHigh,
              ],
            ),
          ),
        ),
        const SizedBox(height: 2),
        SizedBox(
          width: 160,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$minValue', style: const TextStyle(fontSize: 11)),
              Text('$maxValue', style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Small card showing the hovered authority's key data.
class _Tooltip extends StatelessWidget {
  const _Tooltip({required this.constituency, required this.metric});

  final Constituency constituency;
  final String metric;

  @override
  Widget build(BuildContext context) {
    final c = constituency;
    final metricValue = metric == 'change_factor'
        ? c.changeFactor
        : (c.deciles[metric] ?? 0);
    return IgnorePointer(
      child: Card(
        color: Colors.white.withValues(alpha: 0.95),
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              if (c.council.isNotEmpty) Text('Council: ${c.council}'),
              Text('Cluster: ${c.clusterId}'),
              Text('Majority ${c.changeFactor == 1 ? 'changed' : 'unchanged'}'),
              Text(
                'Cluster predicts: '
                '${c.changeFactorCluster == 1 ? 'change' : 'no change'} '
                '(${c.clusterPredictionCorrect ? 'correct' : 'incorrect'})',
              ),
              if (c.predictedChange >= 0)
                Text(
                  'Predicted: ${c.predictedChange == 1 ? 'change' : 'no change'}',
                ),
              if (metric != 'change_factor') Text('$metric: $metricValue'),
              const Divider(height: 12),
              const Text(
                'Deprivation decile deltas:',
                style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
              ),
              ...c.deciles.entries.map(
                (e) => Text(
                  '${_short(e.key)}: ${e.value}',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _short(String key) => key.split(' Decile').first.split(' Rank').first;
}

/// Draws a legend swatch as a filled square with either a solid or a dashed outline,
/// matching how the corresponding polygons are drawn on the map.
class _SwatchPainter extends CustomPainter {
  const _SwatchPainter(this.color, this.dashed);

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = color.withValues(alpha: 0.6));
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = dashed ? 1.6 : 0.8
      ..color = const Color(0xFF263238);
    if (!dashed) {
      canvas.drawRect(rect, border);
      return;
    }
    const dash = 3.0;
    for (var x = 0.0; x < size.width; x += dash * 2) {
      final end = (x + dash).clamp(0.0, size.width);
      canvas.drawLine(Offset(x, 0), Offset(end, 0), border);
      canvas.drawLine(Offset(x, size.height), Offset(end, size.height), border);
    }
    for (var y = 0.0; y < size.height; y += dash * 2) {
      final end = (y + dash).clamp(0.0, size.height);
      canvas.drawLine(Offset(0, y), Offset(0, end), border);
      canvas.drawLine(Offset(size.width, y), Offset(size.width, end), border);
    }
  }

  @override
  bool shouldRepaint(_SwatchPainter old) =>
      old.color != color || old.dashed != dashed;
}
