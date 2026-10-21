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
- `godot --headless --path . -- --simtest [--track=N]` races one lap of every track with eight AI
  cars at full speed without rendering (about 2 minutes) and prints lap times, wall hits and stuck
  checks. Run it after any change to physics, AI or track layouts; every car must finish.
- `tools/smoke_test.sh [dir]` runs `scripts/autotest.gd` under `xvfb-run` (about 2 minutes): menus,
  a stretch of every track with the AI driving, a side view, pause, results. Look at the PNGs. A good
  run ends with `AUTOTEST done` and has no `SCRIPT ERROR`. ALSA errors and leaked RIDs are normal.
- `tools/export_web.sh` builds `build/web/` (no-threads template, any HTTPS host). Test it in headless
  Chromium (Playwright is preinstalled: launch with `--use-gl=angle --use-angle=swiftshader
  --enable-unsafe-swiftshader`). The web fonts have no fallback: Orbitron lacks `·` and arrows, so
  use plain ASCII in titles and buttons.
- Mid-race stutters in the browser are shader compiles (WebGL keeps no shader cache).
  `Hazards.warm_up` draws every event, particle effect and material variant while loading; anything
  new that appears mid-race (a new light, material or effect) must be covered there, and its materials
  kept alive (`Hazards._kept`: Godot frees a shader with its last material). To check, wrap
  `WebGL2RenderingContext.prototype.linkProgram` in Playwright and count links during a race; the
  test flag `?aenet=...,event=KIND` makes only that event fire.

## Design
- Lore source: the Aetherdrift set's Grand Prix (race starts at nightfall in Ghirapur on Avishkar,
  rural outskirts, portal to Amonkhet's revived river, elevated track over Muraganda's jungle, back
  across Amonkhet's desert, finale in Ghirapur). Place names are kept; teams, characters, art and text
  are original. Never copy card art, card text or Wizards/EA assets.
- Everything visual is generated from code: `MeshKit` primitives and lofted shells with vertex
  colours, three shared materials (`Game.mat_solid`, `Game.mat_glow`, and `Game.mat_paint` for glossy
  car paint and glass, which reflects the current track's sky via `Game.set_paint_sky`), procedural
  road and ground textures, `shaders/sky.gdshader`.
- Car bodies are stations `[z, half width, bottom, top, top width factor, squareness]` lofted by
  `CarModels._shell`. Check cars with `xvfb-run -a godot --path . --rendering-driver opengl3 -- --lineup`
  (screenshots in `/tmp/aether-cars`).
- Track layouts in `tracks.gd` are drives: `["S", metres]` straights and `["L"/"R", radius, degrees]`
  bends from the start line (turns add up to 360; a small end gap is spread over the lap), plus
  "heights" keys and "indoor" stretches (`Track.INDOOR` styles, own light via `Track.update_view`).
  The layouts (11-16 km, about four minutes a lap, 3-4 curving indoor stretches each) are made by
  `python3 tools/track_gen.py --write` from each track's style and seed in its `STYLES`, which also
  writes "heights" (hills from the style's "h" range, "bump" sizes and "hills" weights, kept gentle
  where two parts of the lap run close), "indoor" and the river; edit the style, not the generated lists.
  Cars stick to the road except over fast crests, where they lift off (`Car.air`, `Car.LIFT_G`).
  `python3 tools/track_check.py` checks a layout (length, tightest bend, clearance between parts of
  the lap, river) and draws maps without Godot. Long meshes are cut into pieces (`Track.CHUNK`) and
  scenery is batched per `Track.PROP_CELL` so far pieces are culled; props counts are per km. Cars
  do not use the physics engine: they slide on the centre line samples (`Track.locate/lateral/road_y`), with walls at `Track.limit`.
- World events (`scripts/hazards.gd`, `Hazards.KINDS`): each track lists two kinds in `Tracks.LIST`
  "events". `Race.simulate` calls `hazards.update` once per step and `hazards.affect(car)` before each
  `car.step`; events act through `Car.fx_grip/fx_top/fx_push`, `Car.spin_out()` and `hop_t`. The AI
  sees obstacles through `think(..., dangers)` only when `Car.alert` (re-rolled per event, 60%).
  The sim test prints events and spins per track. After adding a new `class_name` script, run
  `godot --headless --path . --import` once so the class cache knows it.
- Multiplayer (`scripts/net.gd`, autoload `Net`): host-run rooms over Godot's high-level multiplayer,
  WebRTC in the browser (signalling via `tools/web/aether-net.js`, which uses the shop page's
  `window.AetherSignal` Supabase channel or, without it, a BroadcastChannel between tabs) and ENet on
  desktop. A car with `Car.remote` is driven elsewhere and follows `net_apply`/`net_follow`; only
  local cars run `think`/`step`/`hazards.affect`. Anything random in a world event must use
  `Hazards.rng` (seeded per event) so all players build the same one. Test with
  `tools/net_test.sh [dir] [xvfb]` (both sides must print the same results line) and, for the web
  build, two Chromium tabs on `index.html?aenet=host=CODE,start=2,laps=1,bot` and `?aenet=join=CODE,bot`
  (launch with `--disable-features=WebRtcHideLocalIpsWithMdns`).
- Each camera carries its environment (`camera.environment`); do not add WorldEnvironment nodes.
- Quality (`Game.quality`, L key, `user://settings.cfg`): the UI always draws at native resolution
  (canvas_items stretch); `Main._apply_quality` sets the 3D `scaling_3d_scale` and MSAA. HIGH full
  res + 4x MSAA + shadows + glow, MEDIUM up to 1080 lines + 2x MSAA + glow, LOW up to 720 lines, no
  MSAA or glow, fewer props and particles.

## Code conventions
- GDScript with tabs, static types where the surrounding code has them, `##` doc comment at the top
  of each script. Data in `const` dictionaries near the top of the script that owns it.
- Nodes are built in code; `scenes/main.tscn` only holds `Main`.
