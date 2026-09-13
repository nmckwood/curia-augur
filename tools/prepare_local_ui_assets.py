"""Copy locally-generated pipeline output into the Flutter app's asset bundle so the
UI can run in local mode (--dart-define=LOCAL_FILENAME=...).

Copies:
  local_output/analysis/*.json  -> frontend/curia_augur_ui/assets/analysis/
  data/geospatial_data/*2022*    -> assets/geo/boundaries_2022.geojson
  data/geospatial_data/*2025*    -> assets/geo/boundaries_2025.geojson

Run the pipeline first:
  CURIA_LOCAL=true python tools/test_all.py
Then:
  python tools/prepare_local_ui_assets.py
"""

import glob
import json
import os
import shutil

from simplify_geojson import simplify_feature_collection

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ANALYSIS_SRC = os.path.join(ROOT, "local_output", "analysis")
GEO_SRC = os.path.join(ROOT, "data", "geospatial_data")
UI_ASSETS = os.path.join(ROOT, "frontend", "curia_augur_ui", "assets")


def _copy_geo(year, dest_name):
    matches = glob.glob(os.path.join(GEO_SRC, f"*{year}*.geojson"))
    if not matches:
        print(f"  WARNING: no GeoJSON matching *{year}* in {GEO_SRC}")
        return
    dest = os.path.join(UI_ASSETS, "geo", dest_name)
    # Always simplify: the raw ONS BFC files are ~200 MB and cannot be bundled as-is.
    with open(matches[0], encoding="utf-8") as fh:
        data = json.load(fh)
    result, _dropped = simplify_feature_collection(data, 0.001, 4, 6)
    with open(dest, "w", encoding="utf-8") as fh:
        json.dump(result, fh, separators=(",", ":"))
    src_mb = os.path.getsize(matches[0]) / 1e6
    dst_mb = os.path.getsize(dest) / 1e6
    print(
        f"  {os.path.basename(matches[0])} ({src_mb:.0f} MB) -> "
        f"assets/geo/{dest_name} ({dst_mb:.1f} MB, simplified)"
    )


def main():
    os.makedirs(os.path.join(UI_ASSETS, "analysis"), exist_ok=True)
    os.makedirs(os.path.join(UI_ASSETS, "geo"), exist_ok=True)

    analyses = glob.glob(os.path.join(ANALYSIS_SRC, "*.json"))
    if not analyses:
        print(f"No analysis files in {ANALYSIS_SRC}. Run tools/test_all.py first.")
    for path in analyses:
        dest = os.path.join(UI_ASSETS, "analysis", os.path.basename(path))
        shutil.copyfile(path, dest)
        print(f"  {os.path.basename(path)} -> assets/analysis/")

    _copy_geo("2022", "boundaries_2022.geojson")
    _copy_geo("2025", "boundaries_2025.geojson")

    print("\nAvailable LOCAL_FILENAME values:")
    for path in analyses:
        print(f"  --dart-define=LOCAL_FILENAME={os.path.basename(path)}")


if __name__ == "__main__":
    main()
