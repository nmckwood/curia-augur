# Flutter setup on WSL (for the Curia Augur UI)

Steps to install Flutter 3.32.0 / Dart 3.8.0 inside WSL2 (Ubuntu) and run the web app.
Curia Augur ships a **web** app, so a browser + web server toolchain is all that's needed —
no Android SDK required unless you also want mobile builds.

## 1. Install prerequisites

```bash
sudo apt update
sudo apt install -y curl git unzip xz-utils zip libglu1-mesa
```

For running/serving Flutter **web** you also need Chrome reachable from WSL. Either:
- install Chrome in WSL: `sudo apt install -y google-chrome-stable` (add Google's apt repo), or
- point Flutter at Windows Chrome:
  ```bash
  echo 'export CHROME_EXECUTABLE="/mnt/c/Program Files/Google/Chrome/Application/chrome.exe"' >> ~/.bashrc
  source ~/.bashrc
  ```

## 2. Install Flutter (pinned to 3.32.0)

Use the version manager-free tarball approach so the version matches `.claude/CLAUDE.md`
(Flutter 3.32.0 bundles Dart 3.8.0):

```bash
cd ~
git clone https://github.com/flutter/flutter.git -b 3.32.0 --depth 1 ~/flutter
echo 'export PATH="$HOME/flutter/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
flutter --version   # expect Flutter 3.32.0 / Dart 3.8.0
```

If Flutter warns about the git checkout being detached, that's expected for a pinned tag.

## 3. First-run configuration

```bash
flutter config --enable-web
flutter config --no-analytics
dart --disable-analytics
flutter doctor            # resolve any ✗ items; for web-only you can ignore Android/iOS
```

WSL note: `flutter doctor` may flag Android toolchain / no connected device — safe to
ignore for web-only development.

## 4. Get dependencies and run the app

```bash
cd /home/nwood/non-soc/personal/curia-augur/frontend/curia_augur_ui
flutter create . --platforms=web    # scaffold web/ , .metadata etc (source in lib/ already present)
flutter pub get
```

Run against a deployed backend (fill in the CDK stack outputs):

```bash
flutter run -d chrome \
  --dart-define=API_BASE_URL=https://api.curia-augur.<your-domain> \
  --dart-define=COGNITO_USER_POOL_ID=us-east-1_xxxxxxx \
  --dart-define=COGNITO_CLIENT_ID=xxxxxxxxxxxxxxxxxxxxxxxxxx
```

> ⚠️ **WSL: use `-d web-server`, not `-d chrome`.** Flutter usually cannot launch/drive
> Windows Chrome from inside WSL (`Failed to launch browser after 3 tries`). Instead serve
> the app and open the browser yourself — WSL forwards `localhost` to Windows:
>
> ```bash
> flutter run -d web-server --web-port=8080 \
>   --dart-define=SKIP_AUTH=true \
>   --dart-define=API_BASE_URL=http://localhost:3000
> ```
>
> Then open **http://localhost:8080** in Chrome on Windows. (Installing Chrome *inside*
> WSL and setting `CHROME_EXECUTABLE` also works, but `web-server` is the least-fuss path.)

`flutter create . --platforms=web` only adds the platform scaffolding; it will **not**
overwrite the existing `lib/` sources or `pubspec.yaml`.

## 4b. Running locally against the local pipeline output (no AWS)

The UI can run entirely offline against the files produced by the local pipeline,
mirroring the backend `CURIA_LOCAL` flag. `--dart-define=LOCAL=true` makes **everything**
local: the file list, every analysis file and the GeoJSON all come from the app's bundled
assets — no API call and no Cognito login.

```bash
# 1. Generate the pipeline output locally (from the repo root)
CURIA_LOCAL=true ./.venv/bin/python tools/test_all.py

# 2. Copy the output + boundaries into the app's asset bundle
./.venv/bin/python tools/prepare_local_ui_assets.py

# 3. Run the UI fully local (WSL: web-server; open the URL in Windows Chrome)
cd frontend/curia_augur_ui
flutter run -d web-server --web-port=8080 --dart-define=LOCAL=true
```

In `LOCAL=true` mode the login screen is bypassed and the dropdown lists **all** bundled
analyses (the file list comes from the asset manifest); the map, metric selector and table
behave exactly as in the cloud build. To preselect one file, add
`--dart-define=LOCAL_FILENAME=analysis-d_2015_d_2019_le_2018_le_2022.json` (it still
implies local mode on its own).

### Skipping login against a live/localhost API

If instead you want to hit a real API (e.g. a locally-served or dev backend) but without
the Cognito login screen, use `--dart-define=SKIP_AUTH=true`. This bypasses login and
sends no `Authorization` header, so the target API must not require the authorizer:

```bash
flutter run -d chrome \
  --dart-define=SKIP_AUTH=true \
  --dart-define=API_BASE_URL=http://localhost:3000
```

`LOCAL_FILENAME` (bundled assets) already implies `SKIP_AUTH`. Never build the production
web bundle with `SKIP_AUTH=true` — REQ UI-8 requires authentication before any data is
shown, so the CloudFront build must keep login on.

> ℹ️ **GeoJSON size is handled automatically.** The raw ONS **BFC** boundary files in
> `data/geospatial_data/` are ~196 MB (2022) and ~280 MB (2025) — far too large to bundle
> as web assets. `tools/prepare_local_ui_assets.py` **simplifies them on copy** (down to
> ~2.3 MB each, all features and LAD `*NM` name properties preserved) via the dependency-free
> `tools/simplify_geojson.py`. Run that tool standalone or tune it:
>
> ```bash
> python tools/simplify_geojson.py --input in.geojson --output out.geojson \
>   --tolerance 0.001 --precision 4     # ~0.001 deg ~= 100 m; larger = smaller file
> ```
>
> For topology-perfect output (no slivers between adjacent authorities) use mapshaper
> instead: `mapshaper in.geojson -simplify 5% -o out.geojson`.

## 5. Build for deployment

```bash
flutter build web \
  --dart-define=API_BASE_URL=... \
  --dart-define=COGNITO_USER_POOL_ID=... \
  --dart-define=COGNITO_CLIENT_ID=...
```

Then publish with `tools/deploy_web.sh` (syncs `build/web/` + the GeoJSON boundaries to
the web bucket and invalidates CloudFront).

## Troubleshooting

- **`Unable to find git`** — install git (step 1) and reopen the shell.
- **Chrome not found** — set `CHROME_EXECUTABLE` (step 1) or install Chrome in WSL.
- **Slow file IO / watcher errors** — keep the repo on the Linux filesystem
  (`~/…` or `/home/…`), not under `/mnt/c`, for acceptable Flutter performance on WSL2.
- **Pinned version drift** — re-run `flutter --version`; if it isn't 3.32.0,
  `cd ~/flutter && git checkout 3.32.0 && flutter --version`.
```
```
