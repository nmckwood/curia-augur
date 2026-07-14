"""Simplify a (large) GeoJSON boundary file for use in the UI.

Dependency-free: applies Ramer-Douglas-Peucker simplification per ring plus coordinate
precision rounding, which shrinks the raw ONS BFC boundaries (~200-280 MB) by ~95-99%
while keeping every feature and its properties (incl. the LAD `*NM` name field the UI
joins on). Good enough for web map rendering; for topology-perfect output use mapshaper
(`mapshaper in.geojson -simplify 5% -o out.geojson`).

Usage:
    python tools/simplify_geojson.py --input in.geojson --output out.geojson \
        [--tolerance 0.001] [--precision 4] [--min-ring-points 6]

--tolerance is in degrees (~0.001 deg ≈ 100 m). --precision is decimal places kept.
"""

import argparse
import json
import os


def _perp_distance(point, start, end):
    """Perpendicular distance of ``point`` from the segment start-end (in degrees)."""
    (x, y), (x1, y1), (x2, y2) = point, start, end
    dx, dy = x2 - x1, y2 - y1
    if dx == 0 and dy == 0:
        return ((x - x1) ** 2 + (y - y1) ** 2) ** 0.5
    # Distance from point to the infinite line through start-end.
    num = abs(dy * x - dx * y + x2 * y1 - y2 * x1)
    den = (dx * dx + dy * dy) ** 0.5
    return num / den


def rdp(points, epsilon):
    """Ramer-Douglas-Peucker on an iterable of [x, y] points (iterative stack)."""
    if len(points) < 3:
        return list(points)
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        start, end = stack.pop()
        max_dist = 0.0
        index = start
        for i in range(start + 1, end):
            dist = _perp_distance(points[i], points[start], points[end])
            if dist > max_dist:
                max_dist = dist
                index = i
        if max_dist > epsilon:
            keep[index] = True
            stack.append((start, index))
            stack.append((index, end))
    return [p for p, k in zip(points, keep) if k]


def _round_ring(ring, precision):
    return [[round(p[0], precision), round(p[1], precision)] for p in ring]


def _close(ring):
    """Ensure a linear ring is closed (first point == last point)."""
    if ring and ring[0] != ring[-1]:
        ring.append(ring[0])
    return ring


def simplify_ring(ring, epsilon, precision, min_points):
    simplified = rdp(ring, epsilon)
    simplified = _round_ring(simplified, precision)
    # Drop consecutive duplicates introduced by rounding.
    deduped = [simplified[0]] if simplified else []
    for point in simplified[1:]:
        if point != deduped[-1]:
            deduped.append(point)
    if len(deduped) < min_points:
        return None
    return _close(deduped)


def simplify_geometry(geometry, epsilon, precision, min_points):
    if geometry is None:
        return None
    gtype = geometry.get("type")
    coords = geometry.get("coordinates")
    if gtype == "Polygon":
        rings = [simplify_ring(r, epsilon, precision, min_points) for r in coords]
        rings = [r for r in rings if r]
        return {"type": "Polygon", "coordinates": rings} if rings else None
    if gtype == "MultiPolygon":
        polygons = []
        for polygon in coords:
            rings = [simplify_ring(r, epsilon, precision, min_points) for r in polygon]
            rings = [r for r in rings if r]
            if rings:
                polygons.append(rings)
        return {"type": "MultiPolygon", "coordinates": polygons} if polygons else None
    return geometry  # non-polygon geometry left untouched


def simplify_feature_collection(data, epsilon, precision, min_points):
    features = []
    dropped = 0
    for feature in data.get("features", []):
        geometry = simplify_geometry(
            feature.get("geometry"), epsilon, precision, min_points
        )
        if geometry is None:
            dropped += 1
            continue
        features.append({**feature, "geometry": geometry})
    return {**data, "features": features}, dropped


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--tolerance", type=float, default=0.001)
    parser.add_argument("--precision", type=int, default=4)
    parser.add_argument("--min-ring-points", type=int, default=6)
    args = parser.parse_args()

    with open(args.input, encoding="utf-8") as fh:
        data = json.load(fh)

    result, dropped = simplify_feature_collection(
        data, args.tolerance, args.precision, args.min_ring_points
    )
    with open(args.output, "w", encoding="utf-8") as fh:
        json.dump(result, fh, separators=(",", ":"))

    in_size = os.path.getsize(args.input)
    out_size = os.path.getsize(args.output)
    print(
        f"{args.input} ({in_size / 1e6:.1f} MB) -> {args.output} "
        f"({out_size / 1e6:.1f} MB, {100 * out_size / in_size:.1f}% of original); "
        f"{len(result['features'])} features kept, {dropped} dropped"
    )


if __name__ == "__main__":
    main()
