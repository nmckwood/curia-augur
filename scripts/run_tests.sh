#!/usr/bin/env bash
#
# Run every unit test in the repo: the Python functional core + lambda handlers, and the
# Flutter/Dart UI. Prints a coverage figure for each and fails if either falls below its
# threshold.
#
#   ./scripts/run_tests.sh              # both suites, with coverage
#   ./scripts/run_tests.sh python       # Python only
#   ./scripts/run_tests.sh dart         # Dart only
#   ./scripts/run_tests.sh --no-coverage
#
# Nothing here touches AWS: the Python suite runs in CURIA_LOCAL mode against tmp dirs
# with a stub S3 client, and the Dart suite uses no network (tile fetches fail harmlessly
# under the test binding). See tests/README.md and frontend/curia_augur_ui/test/README.md
# for what is deliberately not covered.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UI_DIR="$REPO_ROOT/frontend/curia_augur_ui"
VENV_PY="$REPO_ROOT/.venv/bin/python"

PYTHON_MIN_COVERAGE=70
DART_MIN_COVERAGE=70

target="all"
coverage=1
png=0
for arg in "$@"; do
  case "$arg" in
    python|py)      target="python" ;;
    dart|flutter)   target="dart" ;;
    all)            target="all" ;;
    --png) png=1 ;;
    --no-coverage)  coverage=0 ;;
    -h|--help)      sed -n '2,17p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown argument: $arg (expected python|dart|all|--no-coverage|--png)" >&2; exit 2 ;;
  esac
done

bold() { printf '\n\033[1m== %s\033[0m\n' "$1"; }
fail() { printf '\033[31m%s\033[0m\n' "$1"; }
pass() { printf '\033[32m%s\033[0m\n' "$1"; }

python_status=skipped
dart_status=skipped

# --- Python -------------------------------------------------------------------
run_python() {
  bold "Python (pytest)"

  local python_bin="$VENV_PY"
  if [[ ! -x "$python_bin" ]]; then
    python_bin="$(command -v python3 || true)"
    if [[ -z "$python_bin" ]]; then
      fail "no Python interpreter found (expected $VENV_PY or python3 on PATH)"
      return 1
    fi
    echo "note: .venv not found, falling back to $python_bin"
  fi

  if ! "$python_bin" -c "import pytest" >/dev/null 2>&1; then
    fail "pytest is not installed. Install the dev deps:"
    echo "    $python_bin -m pip install -r requirements-dev.txt"
    return 1
  fi

  local args=()
  if [[ "$coverage" -eq 0 ]]; then
    args+=(--no-cov)
  else
    args+=("--cov-fail-under=$PYTHON_MIN_COVERAGE")
  fi

  if [[ "$png" -eq 1 && "$coverage" -eq 1 ]]; then
    args+=("--cov-report=html:htmlcov")
  fi

  ( cd "$REPO_ROOT" && "$python_bin" -m pytest "${args[@]}" ) || return 1

  if [[ "$png" -eq 1 && "$coverage" -eq 1 ]]; then
    wkhtmltoimage --enable-local-file-access --load-error-handling ignore --width 1200 "$REPO_ROOT/htmlcov/index.html" "$REPO_ROOT/python_coverage.png"
  fi
}

# --- Dart ---------------------------------------------------------------------
run_dart() {
  bold "Dart / Flutter (flutter test)"

  if ! command -v flutter >/dev/null 2>&1; then
    fail "flutter is not on PATH — skipping the UI suite."
    echo "    Install Flutter 3.32.0+ and re-run, or use: $0 python"
    return 1
  fi

  cd "$UI_DIR" || return 1

  if [[ ! -d .dart_tool ]]; then
    echo "fetching Dart packages..."
    flutter pub get >/dev/null || return 1
  fi

  local flutter_args=(test)
  [[ "$coverage" -eq 1 ]] && flutter_args+=(--coverage)

  # `flutter test` prints a progress line per test and cannot be quietened when stdout is
  # not a TTY, and flutter_map's TileLayer logs a failed OpenStreetMap fetch per tile (the
  # test binding fails every request with 400; the widget carries on). Buffer it all and
  # show only the summary on success, everything on failure.
  local log
  log="$(mktemp)"
  if flutter "${flutter_args[@]}" >"$log" 2>&1; then
    tail -c 4000 "$log" | tr '\r' '\n' | grep -E "All tests passed|[0-9]+ (test|tests)" | tail -1
  else
    grep -v "tile.openstreetmap.org" "$log" | tr '\r' '\n' | grep -vE "^[0-9]{2}:[0-9]{2} \+[0-9]+: " 
    rm -f "$log"
    return 1
  fi
  rm -f "$log"

  [[ "$coverage" -eq 1 ]] || return 0
  report_dart_coverage
  if [[ "$png" -eq 1 ]]; then
    local html_dir="$UI_DIR/coverage/html"
    genhtml "$UI_DIR/coverage/lcov.info" -o "$html_dir" >/dev/null 2>&1
    wkhtmltoimage --enable-local-file-access --load-error-handling ignore --width 1200 "$html_dir/index.html" "$REPO_ROOT/dart_coverage.png"
  fi
}

# Summarise lcov.info per file and enforce the threshold. lcov/genhtml are not required.
report_dart_coverage() {
  local lcov="$UI_DIR/coverage/lcov.info"
  if [[ ! -f "$lcov" ]]; then
    fail "no coverage/lcov.info produced"
    return 1
  fi

  local python_bin="$VENV_PY"
  [[ -x "$python_bin" ]] || python_bin="$(command -v python3 || true)"
  [[ -n "$python_bin" ]] || { echo "note: no python available to summarise lcov"; return 0; }

  "$python_bin" - "$lcov" "$DART_MIN_COVERAGE" <<'PYEOF'
import sys

lcov_path, minimum = sys.argv[1], float(sys.argv[2])
rows, hit_total, found_total, current, found = [], 0, 0, None, 0
for line in open(lcov_path):
    line = line.strip()
    if line.startswith("SF:"):
        current = line[3:]
    elif line.startswith("LF:"):
        found = int(line[3:])
    elif line.startswith("LH:"):
        hit = int(line[3:])
        rows.append((current, hit, found))
        hit_total += hit
        found_total += found

print(f"\n{'Cover':>7}  {'Lines':>10}  File")
print("-" * 72)
for path, hit, found in sorted(rows, key=lambda r: (r[1] / r[2]) if r[2] else 1.0):
    pct = (hit / found * 100) if found else 100.0
    print(f"{pct:6.1f}%  {hit:5d}/{found:<4d}  {path}")
print("-" * 72)

total = (hit_total / found_total * 100) if found_total else 0.0
print(f"{total:6.2f}%  {hit_total:5d}/{found_total:<4d}  TOTAL")
if total < minimum:
    print(f"\nFAIL: Dart coverage {total:.2f}% is below the required {minimum:.0f}%")
    sys.exit(1)
print(f"\nRequired test coverage of {minimum:.0f}% reached. Total coverage: {total:.2f}%")
PYEOF
}

# --- Drive --------------------------------------------------------------------
overall=0

if [[ "$target" == "all" || "$target" == "python" ]]; then
  if run_python; then python_status=passed; else python_status=FAILED; overall=1; fi
fi

if [[ "$target" == "all" || "$target" == "dart" ]]; then
  if run_dart; then dart_status=passed; else dart_status=FAILED; overall=1; fi
fi

bold "Summary"
printf '  python : %s\n' "$python_status"
printf '  dart   : %s\n' "$dart_status"

if [[ "$overall" -eq 0 ]]; then
  pass "All requested test suites passed."
else
  fail "One or more test suites failed."
fi
exit "$overall"
