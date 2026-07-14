import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/analysis.dart';
import 'metric_color.dart';

/// How polygons are coloured:
/// - metric: continuous green->red by the selected metric value (REQ UI-6).
/// - changed: binary green (election result unchanged) / red (changed).
/// - predicted: binary green/red by the common-indices predicted majority flip.
/// - predictedPerYear: binary green/red by the per-year best-indices predicted flip.
enum MapColorMode { metric, changed, predicted, predictedPerYear }

const Color _green = Color(0xFF2E7D32);
const Color _red = Color(0xFFC62828);

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

  Color _colorFor(Constituency c, num minV, num maxV) {
    if (widget.colorMode == MapColorMode.changed) {
      return c.changeFactor == 0 ? _green : _red;
    }
    if (widget.colorMode == MapColorMode.predicted) {
      return c.predictedChange <= 0 ? _green : _red;
    }
    if (widget.colorMode == MapColorMode.predictedPerYear) {
      return c.predictedChangePerYear <= 0 ? _green : _red;
    }
    return MetricColor.forValue(_metricValue(c), minV, maxV);
  }

  List<Polygon<Constituency>> _buildPolygons(num minV, num maxV) {
    final polygons = <Polygon<Constituency>>[];
    final features = (widget.geoJson['features'] as List?) ?? [];
    for (final feature in features) {
      final props = (feature['properties'] as Map?)?.cast<String, dynamic>() ?? {};
      final name = _featureName(props);
      if (name == null) continue;
      final c = widget.byName[MapView.normalize(name)];
      if (c == null) continue;
      final color = _colorFor(c, minV, maxV);
      for (final ring in _rings(feature['geometry'] as Map<String, dynamic>?)) {
        polygons.add(Polygon<Constituency>(
          points: ring,
          color: color.withValues(alpha: 0.6),
          borderColor: const Color(0xFF37474F),
          borderStrokeWidth: 0.4,
          hitValue: c,
        ));
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

  void _onHover(PointerHoverEvent event) {
    final hit = _hitNotifier.value;
    final hovered =
        (hit != null && hit.hitValues.isNotEmpty) ? hit.hitValues.first : null;
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

    return MouseRegion(
      onHover: _onHover,
      onExit: (_) => setState(() => _hovered = null),
      child: Stack(
        children: [
          FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(53.0, -1.5),
              initialZoom: 6,
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
    );
  }
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
          child: mode == MapColorMode.changed
              ? _binaryLegend('Election result', 'No change', 'Changed')
              : mode == MapColorMode.predicted
                  ? _binaryLegend('Predicted (common)', 'No change', 'Change')
                  : mode == MapColorMode.predictedPerYear
                      ? _binaryLegend('Predicted (per-year)', 'No change', 'Change')
                      : _metricLegend(),
        ),
      ),
    );
  }

  Widget _binaryLegend(String title, String greenLabel, String redLabel) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        const SizedBox(height: 4),
        _swatchRow(_green, greenLabel),
        _swatchRow(_red, redLabel),
      ],
    );
  }

  Widget _swatchRow(Color color, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 14, height: 14, color: color),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ]),
    );
  }

  Widget _metricLegend() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(metric,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        const SizedBox(height: 4),
        Container(
          width: 160,
          height: 12,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [_green, Color(0xFFF9A825), _red],
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
    final metricValue =
        metric == 'change_factor' ? c.changeFactor : (c.deciles[metric] ?? 0);
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
              Text(c.name,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              if (c.council.isNotEmpty) Text('Council: ${c.council}'),
              Text('Cluster: ${c.clusterId}'),
              Text('Majority ${c.changeFactor == 1 ? 'changed' : 'unchanged'}'),
              if (c.predictedChange >= 0)
                Text('Predicted: ${c.predictedChange == 1 ? 'change' : 'no change'}'),
              if (metric != 'change_factor') Text('$metric: $metricValue'),
              const Divider(height: 12),
              const Text('Deprivation decile deltas:',
                  style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12)),
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

  String _short(String key) =>
      key.split(' Decile').first.split(' Rank').first;
}
