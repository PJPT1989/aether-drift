# Need for Speed: ~~Tokyo~~ Aether Drift

*It's time for planeswalkers to learn how to drive a stick, and the importance of family.*

An arcade racing game in **Godot 4.3**, set in the world of a multiversal Grand Prix: eight teams
race across three planes through portals, from a copper-and-aether city of invention to a revived
desert river, a primordial jungle and the boiling desert, and back for the finale. Inspired by the
lore of the *Aetherdrift* Magic: The Gathering set; all art, models, teams and text are original
and generated from code. A fan project, not affiliated with Electronic Arts or Wizards of the Coast.

## Playing

- **Quick race**: pick one of six tracks and one of eight teams; 3 laps against seven AI racers.
- **Grand Prix**: all six legs in race order; points 10-8-6-5-4-3-2-1; most points takes the Aetherspark.

| Key | Action |
| --- | --- |
| W / Up | accelerate |
| S / Down | brake, then reverse |
| A D / Left Right | steer |
| Space | **drift**: hold through a corner to slide and charge aether, let go for a short burst |
| Shift (or N) | **aether boost**: spends the aether meter |
| R | reset onto the track |
| C | camera (far / near) |
| Esc / P | pause |
| L | graphics quality: Low, Medium, High (remembered) |
| M | sound on / off |

A gamepad works too (left stick, triggers, A/B/X/Y).

Aether fills from drifting and from the glowing **aether orbs** lined up on the road. Grass, sand
and run-off slow you down; walls and rails bounce you back.

## World events

The tracks fight back. Every 15-25 seconds something happens somewhere ahead of a random racer
(you are picked more often than any one rival). A banner names it and says how far ahead it is, and
an amber dot marks it on the minimap. Rivals are caught out too, and only some of them see a log in
time to steer round it, so every race turns out differently.

| Track | Events |
| --- | --- |
| Ghirapur Nightfall | **Thopter swarm**: buffeting and spins. **Aether pipe burst**: a slick with almost no grip that fills your aether meter |
| The Inventors' Outskirts | **Runaway harvester**: a huge automaton walks across the road. **Crosswind**: gusts push every car sideways |
| Banks of the Living River | **River surge**: water floods the road, top speed drops. **Scarab swarm**: beetles slow you and eat your aether |
| Primordial Canopy | **Geyser eruption**: glowing vents go off and throw cars. **Falling branches**: logs land on the deck; hitting one stops you dead |
| The Broken Sands | **Sandstorm**: thick haze, loose grip, gusts. **Drifting sand**: a dune covers half the road |
| Heart of Ghirapur | **Fireworks misfire**: rockets land on the track and explode. **Aether lightning**: bolts hit random racers, spin them and empty their aether |

A car caught by a blast, a bolt or a slick spins once round and loses most of its speed.

## The tracks (race order)

| # | Track | Plane | Look |
| --- | --- | --- | --- |
| 1 | Ghirapur Nightfall | Avishkar | night city, copper towers, aether pipes over the street, a spire with rings, thopters |
| 2 | The Inventors' Outskirts | Avishkar | dawn countryside, coloured terraced fields, curling trees, windmills, aether pipelines |
| 3 | Banks of the Living River | Amonkhet | green river valley, palms, reeds, obelisks, lion-headed guardian statues, pyramids, grandstands |
| 4 | Primordial Canopy | Muraganda | elevated wooden track above the jungle, giant trees, geysers, volcano, long-necked beasts, shattered moon |
| 5 | The Broken Sands | Amonkhet | dunes, ruins and fallen statues, mesas, a tomb of ancient kings |
| 6 | Heart of Ghirapur | Avishkar | night finale, grandstands, fireworks, the Aetherspark trophy |

Tracks 1-5 begin by driving out of a portal ring (the plane-to-plane gates of the story).

## Teams

Indigo Rangers (balanced), Skyfire Racing (top speed), Sunchariot Dynasty (grip), Brasslight
Pilgrims (acceleration), Wraith Speed (fast but slippery), Rocket Rabble (fastest straight-line,
poor grip), Reefjaw Haulers (light, quick), Duskwander Nomads (armoured, grippy). Each has its own
body shape and livery.

## Graphics quality

Menus and the HUD always draw at your screen's full resolution. **High** (desktop default): the 3D
view at full resolution with 4x anti-aliasing, shadows and glow. **Medium** (browser default): the 3D
view at up to 1080 lines with 2x anti-aliasing and glow, no shadows. **Low**: up to 720 lines, no
anti-aliasing or glow, fewer props and particles. In the browser the game drops to Low by itself
once if the first seconds of a race run under 24 fps and nobody chose a level.

## Files

| Path | What |
| --- | --- |
| `scripts/main.gd` | menus, race flow, Grand Prix, pause, results, quality, headless sim test |
| `scripts/game.gd` | `Game` autoload: teams, settings, controls, fonts, materials, generated sounds |
| `scripts/tracks.gd` | the six track definitions (layout, sky, colours, props, landmarks) |
| `scripts/track.gd` | builds a track (road, terrain, river, scenery) and answers position queries |
| `scripts/props.gd` | scenery, arches and landmarks made from primitives |
| `scripts/car.gd` | driving physics, drift and boost, lap counting, AI driver |
| `scripts/car_models.gd` | the eight team car models (smooth lofted bodies, glass cabins, detailed wheels) |
| `scripts/race.gd` | one race: grid, countdown, collisions, ranking, camera |
| `scripts/hazards.gd` | world events: what each one does, its visuals, and how the AI reacts |
| `scripts/hud.gd` | race overlay: place, laps, minimap, speedometer, aether meter |
| `scripts/showcase.gd` | the turning car on the menu screens |
| `scripts/mesh_kit.gd` | mesh builder (boxes, cylinders, spheres, rings, smooth lofted shells) |
| `scripts/autotest.gd` | smoke test with screenshots |
| `shaders/` | painted sky, aether glow, glossy car paint |
| `tools/car_lineup.gd` | art check: all eight cars side by side (`-- --lineup`) |
| `fonts/` | Orbitron and Exo 2 (SIL Open Font License) |
| `tools/` | Godot install, smoke test, web export |
