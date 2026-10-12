# Aether Drift: notes for Claude

"Need for Speed: ~~Tokyo~~ Aether Drift" is an arcade racing game in **Godot 4.3** (GDScript, GL
Compatibility renderer). It is Petr's project; he describes features in plain language and expects
them built, tested and shown with screenshots. `README.md` is the player-facing guide and must stay
accurate when gameplay changes. `docs/HISTORY.md` has every request Petr made and what was built.
Sister project: `PJPT1989/ashen-depths` (same tooling). The web build is published on Petr's shop
(`PJPT1989/tomano-collection-shop`, `hry-aether-drift.html`, imported with its `tools/game_import.py`).

## Running and testing (cloud or Linux)
- `tools/setup_godot.sh` installs Godot 4.3 as `~/.local/bin/godot` and imports the project (the
  SessionStart hook in `.claude/settings.json` runs it in cloud sessions).
- `godot --headless --path . -- --simtest [--track=N]` races every track with eight AI cars at full
  speed without rendering (about 20 s) and prints lap times, wall hits and stuck checks. Run it
  after any change to physics, AI or track layouts; every car must finish.
- `tools/smoke_test.sh [dir]` runs `scripts/autotest.gd` under `xvfb-run` (about 2 minutes): menus,
  a stretch of every track with the AI driving, a side view, pause, results. Look at the PNGs. A good
  run ends with `AUTOTEST done` and has no `SCRIPT ERROR`. ALSA errors and leaked RIDs are normal.
- `tools/export_web.sh` builds `build/web/` (no-threads template, any HTTPS host). Test it in headless
  Chromium (Playwright is preinstalled: launch with `--use-gl=angle --use-angle=swiftshader
  --enable-unsafe-swiftshader`). The web fonts have no fallback: Orbitron lacks `·` and arrows, so
  use plain ASCII in titles and buttons.

## Design
- Lore source: the Aetherdrift set's Grand Prix (race starts at nightfall in Ghirapur on Avishkar,
  rural outskirts, portal to Amonkhet's revived river, elevated track over Muraganda's jungle, back
  across Amonkhet's desert, finale in Ghirapur). Place names are kept; teams, characters, art and text
  are original. Never copy card art, card text or Wizards/EA assets.
- Everything visual is generated from code: `MeshKit` primitives with vertex colours, two shared
  materials (`Game.mat_solid`, `Game.mat_glow`), procedural road and ground textures, `shaders/sky.gdshader`.
- Track layouts are control points in `tracks.gd`, smoothed with Catmull-Rom and stretched by
  `Track.STRETCH`. Cars do not use the physics engine: they slide on the centre line samples
  (`Track.locate/lateral/road_y`), with walls at `Track.limit`.
- Each camera carries its environment (`camera.environment`); do not add WorldEnvironment nodes.
- Quality (`Game.quality`, L key, `user://settings.cfg`): HIGH full res + shadows + glow + MSAA,
  MEDIUM 1280x720 viewport scaling + glow, LOW 960x540, no glow, fewer props and particles.

## Code conventions
- GDScript with tabs, static types where the surrounding code has them, `##` doc comment at the top
  of each script. Data in `const` dictionaries near the top of the script that owns it.
- Nodes are built in code; `scenes/main.tscn` only holds `Main`.
