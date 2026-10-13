#!/usr/bin/env bash
# Online test on one machine: a host and a guest (two Godot processes, ENet on localhost) race
# one lap of a track with the AI driving both players' cars. Prints the NETTEST lines of both;
# a good run ends with the same "results:" line on both sides. Add `xvfb` as the second argument
# to render and save screenshots (lobby, race, results) in the folder given first.
#   tools/net_test.sh [shots dir] [xvfb] [track]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$(command -v godot || echo "$HOME/.local/bin/godot")}"
SHOTS="${1:-/tmp/aether-net}"
TRACK="${3:-0}"
mkdir -p "$SHOTS"
run=("$GODOT" --headless --path "$ROOT")
extra=""
if [ "${2:-}" = "xvfb" ]; then
	run=(xvfb-run -a -s "-screen 0 1280x800x24" "$GODOT" --path "$ROOT" --rendering-driver opengl3 --resolution 1280x720)
	extra=",shots=$SHOTS"
fi
"${run[@]}" -- "--net=host,start=2,laps=${LAPS:-1},track=$TRACK,bot,quit$extra" > "$SHOTS/host.log" 2>&1 &
host=$!
for i in $(seq 1 60); do grep -q "hosting" "$SHOTS/host.log" 2>/dev/null && break; sleep 0.5; done
"${run[@]}" -- "--net=join=127.0.0.1,bot,quit$extra" > "$SHOTS/guest.log" 2>&1
wait $host
grep -hE "NETTEST|SCRIPT ERROR" "$SHOTS/host.log" "$SHOTS/guest.log"
