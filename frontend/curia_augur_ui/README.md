# curia_augur_ui

The Flutter web front-end for Curia Augur. Authenticated users pick an analysis file and
explore it through maps, charts, a summary and a table; a second page investigates per-year
predictiveness. It reads the ML analysis JSON either from the Cognito-secured files API or,
in local mode, from bundled assets.

| | |
|---|---|
| **Framework** | Flutter 3.32 / Dart 3.8 (web target) |
| **Key packages** | `flutter_map` + `latlong2` (OSM maps), `fl_chart` (scatter/pie), `amazon_cognito_identity_dart_2` + `flutter_secure_storage` (auth), `http` |
| **Config** | compile-time `--dart-define` (see below) |
| **Style** | OOP (project convention for front-end code) |

## Layout
```
lib/
├── main.dart                    # app root; auth gate vs local/skip-auth
├── config.dart                  # --dart-define config + LOCAL / SKIP_AUTH flags
├── models/analysis.dart         # Analysis, Constituency, ClusterSummary,
│                                #   FeatureImportance, PredictionMeta, IndexPredictiveness
├── services/
│   ├── auth_service.dart        # Cognito sign-in + token persistence
│   └── api_service.dart         # files API + presigned fetch; asset reads in local mode
├── screens/
│   ├── login_screen.dart        # sign-in gate (REQUIREMENTS UI-8)
│   ├── home_screen.dart         # main analysis page
│   └── per_year_screen.dart     # per-year predictiveness page (REQUIREMENTS_3 follow-up)
└── widgets/
    ├── map_view.dart            # OSM choropleth + hover tooltip + legend (4 colour modes)
    ├── metric_color.dart        # green→amber→red scale
    ├── analysis_summary.dart    # written summary of characterizing indices
    ├── cluster_scatter.dart     # PCA cluster scatter
    ├── prediction_scatter.dart  # predicted vs actual (common or per-year)
    ├── accuracy_pie.dart        # held-out accuracy vs baseline
    ├── most_predictive_indices.dart  # per-index univariate accuracy bars
    └── data_table_view.dart     # filterable, collapsible table
assets/
├── analysis/   # bundled analysis JSON (local mode) — populated by tools
└── geo/        # simplified GeoJSON boundaries (local mode) — populated by tools
```

## Pages
**Home** (`home_screen.dart`) — banner, analysis-file dropdown, deprivation-metric selector,
a written **summary** (including each cluster's accuracy and rank), **two maps** — actual
election change and the cluster prediction (`change_factor_cluster`), both using green = no
change so disagreements read as a colour flip — a **PCA cluster scatter**, a
**predicted-vs-actual scatter + accuracy pie** (both scored on `change_factor_cluster`)
alongside a **no-ML baseline pie** (always guess the most common `change_factor`) and a
**regression summary** reading `predict.py`'s logistic-regression scores against that
baseline, and a filterable **table** showing actual vs cluster prediction per authority. An
app-bar button opens the per-year page.

An **ecological-fallacy banner** sits above every screen (required by the project ethics
review): findings are area-level and must not be read as individual voting behaviour.

## Accessibility (WCAG 2.2)
Charts and maps are the main exposure, so the original red/green "bad/good" palette was
replaced under **SC 1.4.1 Use of Color**:
- **Blue `#2a78d6` / orange `#eb6834`** for every binary outcome, and a diverging
  blue→grey→red ramp for signed deprivation deltas. Both validated with the data-viz
  palette validator (binary pair: CVD ΔE 24.7, normal-vision ΔE 33.6, both ≥ 3:1 on the
  chart surface). Central definitions live in `lib/theme/palette.dart`.
- **Colour is never the only cue**: map polygons also vary their outline (solid vs thicker
  dashed), scatter series and clusters also vary marker shape (circle / square / cross),
  donut slices are labelled in words inside the slice, the bar chart adds a ✓/– glyph, and
  the data table states every value as text — it is the accessible equivalent of the maps.
- **Contrast**: secondary text uses `#52514e` (7.9:1, AAA) rather than `black54`, which
  renders at 4.61:1 and only just clears AA; slice labels are near-black (≥ 4.8:1 on both
  fills, where white would have been 3.2:1 on the orange); the banner ink is 6.0:1.
- **Tooltips throughout**, each flagged by a visible ⓘ affordance (`InfoHeading` /
  `InfoHint`), opening on hover and on tap. Map details are reachable by tap as well as
  hover, and marks/legends carry `Semantics` labels.

**Per-year predictiveness** (`per_year_screen.dart`) — the most-predictive-indices bar chart
(each index's univariate held-out accuracy vs the baseline marker), plus a predicted map,
predicted-vs-actual scatter and accuracy pie for a model trained on that year's best indices.

## Configuration (`--dart-define`)
| Flag | Effect |
|------|--------|
| `LOCAL=true` | Fully offline: file list, analyses and GeoJSON all come from bundled assets — no API, no auth. |
| `LOCAL_FILENAME=<file>` | Preselect one bundled analysis (implies local mode). |
| `SKIP_AUTH=true` | Skip Cognito login (dev against a local API). **Never** use for a production build (violates UI-8). |
| `API_BASE_URL` | Files API base URL (cloud mode). |
| `COGNITO_USER_POOL_ID`, `COGNITO_CLIENT_ID` | Cognito config (cloud mode). |
| `GEO_BASE_PATH` | Path prefix for GeoJSON in cloud mode (default `/geo`). |

## Run it

### Fully local (no backend)
```bash
# from the repo root: generate outputs, then bundle them into assets/
CURIA_LOCAL=true ./.venv/bin/python tools/test_all.py
./.venv/bin/python tools/prepare_local_ui_assets.py

cd frontend/curia_augur_ui
flutter pub get
flutter run -d web-server --web-port=8080 --dart-define=LOCAL=true
# open http://localhost:8080  (WSL: use -d web-server and open in Windows Chrome)
```

### Against a deployed backend
```bash
flutter run -d web-server --web-port=8080 \
  --dart-define=API_BASE_URL=https://api.curia-augur.<your-domain> \
  --dart-define=COGNITO_USER_POOL_ID=us-east-1_xxxxx \
  --dart-define=COGNITO_CLIENT_ID=xxxxxxxxxxxxxxxxxxxxxxxxxx
```

> **WSL:** prefer `-d web-server` over `-d chrome` — Flutter usually can't drive Windows Chrome
> from WSL. See `docs/FLUTTER_WSL_SETUP.md`.

## Build & deploy
```bash
flutter build web --dart-define=API_BASE_URL=... --dart-define=COGNITO_USER_POOL_ID=... --dart-define=COGNITO_CLIENT_ID=...
```
`tools/deploy_web.sh` builds, syncs `build/web/` to the web S3 bucket, uploads simplified
GeoJSON under `/geo`, and invalidates CloudFront. The app is served from CloudFront + a private
S3 bucket at `curia-augur.<your-domain>`.

## Assets & GeoJSON
Local mode reads bundled `assets/analysis/*.json` (enumerated at runtime via the asset
manifest) and `assets/geo/boundaries_{2022,2025}.geojson`. Both are populated by
`tools/prepare_local_ui_assets.py`, which also simplifies the raw ~200 MB boundaries down to
~2.3 MB (`tools/simplify_geojson.py`). Bundled assets are git-ignored — regenerate them locally.

## Notes
- `main.dart` skips the login screen when `LOCAL`/`LOCAL_FILENAME`/`SKIP_AUTH` make auth
  unnecessary (`Config.requiresAuth`); otherwise it restores a Cognito session or shows login.
- The maps join GeoJSON polygons to constituencies by normalized LAD name; polygons without a
  matching analysis row are skipped.
