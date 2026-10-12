#!/usr/bin/env bash
# Runs the in-game smoke test (scripts/autotest.gd) under a virtual display and saves
# screenshots. Takes about 2 minutes with software rendering.
#   tools/smoke_test.sh [shots_dir]      default: /tmp/aether-shots
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHOTS="${1:-/tmp/aether-shots}"
GODOT="${GODOT:-$(command -v godot || echo "$HOME/.local/bin/godot")}"
mkdir -p "$SHOTS"
cmd=("$GODOT" --path "$ROOT" --rendering-driver opengl3 -- --autotest "--shots=$SHOTS")
if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null; then
	cmd=(xvfb-run -a -s "-screen 0 1280x800x24" "${cmd[@]}")
fi
"${cmd[@]}" 2>&1 | grep -E "AUTOTEST|SCRIPT ERROR|^ERROR|Parse Error" | grep -v "resources still in use"
echo "screenshots in $SHOTS"
