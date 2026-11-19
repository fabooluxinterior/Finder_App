#!/usr/bin/env bash
# Builds the offline web demo (build/web). Web builds don't support flavors,
# so the demo-only asset restriction in pubspec.yaml is lifted for this build
# and restored afterwards. Never use this for a production web build.
set -euo pipefail
cd "$(dirname "$0")/.."
cp pubspec.yaml pubspec.yaml.bak
trap 'mv pubspec.yaml.bak pubspec.yaml' EXIT
python3 - <<'PY'
import re
s = open('pubspec.yaml').read()
s = re.sub(r"    - path: assets/demo/\n      flavors:\n        - demo\n", "    - assets/demo/\n", s)
open('pubspec.yaml', 'w').write(s)
PY
flutter build web --release --no-web-resources-cdn --pwa-strategy=none --no-wasm-dry-run --dart-define=DEMO=true \
  --dart-define=SPOTIFY_CLIENT_ID="${SPOTIFY_CLIENT_ID:-}" "$@"
