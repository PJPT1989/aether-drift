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

**High** (desktop default): full resolution, shadows, glow, 2x MSAA. **Medium** (browser default):
draws at 1280x720 and scales up, glow, no shadows. **Low**: 960x540, no glow, fewer props and
particles. In the browser the game drops to Low by itself once if the first seconds of a race run
under 24 fps and nobody chose a level.

## Files

| Path | What |
| --- | --- |
| `scripts/main.gd` | menus, race flow, Grand Prix, pause, results, quality, headless sim test |
| `scripts/game.gd` | `Game` autoload: teams, settings, controls, fonts, materials, generated sounds |
| `scripts/tracks.gd` | the six track definitions (layout, sky, colours, props, landmarks) |
| `scripts/track.gd` | builds a track (road, terrain, river, scenery) and answers position queries |
| `scripts/props.gd` | scenery, arches and landmarks made from primitives |
| `scripts/car.gd` | driving physics, drift and boost, lap counting, AI driver |
| `scripts/car_models.gd` | the eight team car models |
| `scripts/race.gd` | one race: grid, countdown, collisions, ranking, camera |
| `scripts/hud.gd` | race overlay: place, laps, minimap, speedometer, aether meter |
| `scripts/showcase.gd` | the turning car on the menu screens |
| `scripts/mesh_kit.gd` | low-poly mesh builder (boxes, cylinders, spheres, rings) |
| `scripts/autotest.gd` | smoke test with screenshots |
| `shaders/` | painted sky, aether glow |
| `fonts/` | Orbitron and Exo 2 (SIL Open Font License) |
| `tools/` | Godot install, smoke test, web export |
