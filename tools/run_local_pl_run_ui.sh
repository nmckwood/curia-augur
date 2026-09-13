#!/usr/bin/env bash
CURIA_LOCAL=true ./.venv/bin/python tools/test_all.py
./.venv/bin/python tools/prepare_local_ui_assets.py
cd frontend/curia_augur_ui && flutter pub get
flutter run -d web-server --web-port=8080 --dart-define=LOCAL=true
cd ../..