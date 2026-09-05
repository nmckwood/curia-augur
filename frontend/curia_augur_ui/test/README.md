# Flutter test suite

Unit and widget tests for the Curia Augur UI. Everything runs offline under
`TestWidgetsFlutterBinding`, which fails all HTTP requests with status 400.

## Running

```bash
../../../scripts/run_tests.sh dart     # from anywhere in the repo: ./scripts/run_tests.sh dart
flutter test                           # from this package
flutter test --coverage                # writes coverage/lcov.info
flutter test test/models               # one directory
flutter test --plain-name "uplift"     # by name
```

## Coverage

`scripts/run_tests.sh` summarises `coverage/lcov.info` per file and fails below **70%**.
Current coverage is **78%** across 926 lines. Note that lcov only reports files the tests
actually import, so the figure above deliberately includes the two low-coverage service
files by importing `HomeScreen` (which pulls them in) rather than quietly omitting them.

## Layout

| File | Covers |
|------|--------|
| `helpers.dart` | JSON builders matching the ML pipeline output, a sizing harness, a WCAG contrast helper |
| `config_test.dart` | The derived `Config` getters (`isLocal`, `requiresAuth`, `filesEndpoint`) |
| `models/analysis_test.dart` | The whole JSON contract with the Python pipeline |
| `theme/palette_test.dart` | The accessible palette: CVD separation, contrast ratios, the diverging ramp, cluster hue+shape pairing |
| `widgets/interpretation_banner_test.dart` | The ethics-review ecological-fallacy banner |
| `widgets/info_heading_test.dart` | The ⓘ tooltip affordance and its semantics label |
| `widgets/accuracy_test.dart` | The model pie, the no-ML baseline pie, the shared donut |
| `widgets/regression_summary_test.dart` | Uplift sign, verdict wording, icon + semantics |
| `widgets/data_table_view_test.dart` | Columns, filtering, sorting, collapse, horizontal scroll |
| `widgets/charts_test.dart` | Scatter legends, marker shapes, the predictive-indices bars |
| `widgets/analysis_summary_test.dart` | The written summary and the cluster ranking |
| `widgets/map_view_test.dart` | `MapView.normalize`, the pure GeoJSON↔analysis name join |
| `widgets/map_view_render_test.dart` | Polygon fills AND outline patterns, legends, semantics |
| `screens/per_year_screen_test.dart` | The per-year page end to end |
| `screens/home_screen_test.dart` | App-bar chrome and the API-failure path |

## Accessibility is under test

The WCAG 2.2 work is asserted, not just documented, so a future change that reintroduces a
red/green palette or drops a redundant cue fails the build:

- `palette_test.dart` computes real contrast ratios and asserts the AA/AAA thresholds.
- `map_view_render_test.dart` asserts that "change" polygons differ by **outline pattern
  and stroke width**, not only by fill colour (SC 1.4.1).
- `charts_test.dart` asserts each series carries a distinct **marker shape** and that the
  predictive-indices bars carry a ✓/– glyph.
- `data_table_view_test.dart` asserts the table states every value as **text**, making it
  the accessible equivalent of the maps and charts.

## Deliberately not covered

| Area | Why |
|------|-----|
| `services/auth_service.dart` | Cognito SRP against a live user pool plus `flutter_secure_storage`, which needs platform channels. Faking both would test the fake. |
| `services/api_service.dart` (beyond the error path) | It calls the top-level `http.get` rather than an injectable `Client`, and `Config` is compile-time (`String.fromEnvironment`), so local vs cloud mode cannot be varied per test. Making this properly testable means injecting a `http.Client` into `ApiService` — worth doing, but a production change rather than a test one. |
| `HomeScreen` fully populated | Same reason: it constructs its own `ApiService`. The chrome and the failure path are covered. |
| Map tile rendering | `TileLayer` fetches OpenStreetMap tiles; the binding blocks them. flutter_map logs the failures and carries on, so the polygon layer, legend and tooltip are all still asserted. |
