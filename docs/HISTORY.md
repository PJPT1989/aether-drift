# History

## 1. The first version (2026-10-12)
> I want to add new game into my gaming section. Game will be called Ned for speed: Aether drift.
> Name will have before Aether work Tokie crossstriked (as a reference). It will be racing Nedd for
> speed like game, but set into Magic The gathering: Aetherdrift set lore. Learn what was the lore of
> that set and put it my game into that visuals. Use Godot engine to build the game, just like my
> previous game. I want there to be at least 6 different tracks to play/race and race tracks will
> have visuals of aetherdrift lore/world.

Petr confirmed the title "Need for Speed: ~~Tokyo~~ Aether Drift" and created this repository.

Lore used (from Wizards' Planeswalker's Guide to Aetherdrift): the Grand Prix starts at nightfall in
Ghirapur on Avishkar (the renamed plane of invention), runs into its rural outskirts, through a
portal to Amonkhet along the revived river, onto an elevated track over Muraganda's primordial
jungle (geysers, volcanoes, giant beasts, a shattered moon), back across Amonkhet's desert and ends
in the heart of Ghirapur; the prize is the Aetherspark. The six tracks follow those legs in order.
Ten teams raced in the story; the game has eight original teams loosely echoing them (aether
ramjets, last year's champions, desert charioteers, automaton pilgrims, haunted racers, rocket
goblins, shark-folk riders, wasteland nomads).

Built: arcade driving with drift that charges aether and a boost, aether orbs, 7 AI racers with
corner-speed look-ahead and gentle catch-up, 3-lap races, Quick Race and a 6-leg Grand Prix with
points, HUD with minimap, menus with a turning car, pause, results, Low/Medium/High quality (the
same three levels as Ashen Depths, browser defaults to Medium and drops to Low once if slow),
keyboard and gamepad, generated sounds. All art is generated from code.

Tested: headless simulation (all 8 cars finish on every track, laps 34-44 s), smoke test screenshots
of every track, web build loaded and raced in headless Chromium. Not yet tuned by a human player.

## 2. Tagline (2026-10-12)
> Put in the title of video game phrase like "Its time for planeswalkers to learn how to drive a
> stick and importance of family"

The title screen now shows "It's time for planeswalkers to learn how to drive a stick, and the
importance of family." under the logo (`Game.TAGLINE`), in gold; the shop's game page shows it too.

## 3. Sharper graphics, better cars and world (2026-10-12)
> I like the tone and visual theme but game we make graphics more sharper, better models of cars, world etc

- Sharper: menus and HUD always draw at the screen's full resolution; the 3D view renders at full
  resolution with 4x anti-aliasing on High and at up to 1080 lines with 2x anti-aliasing on Medium
  (before: Medium drew everything at 1280x720 and scaled it up). 8x anisotropic filtering, road
  textures at 512-1024 px, ground detail at 512 px.
- Cars: rebuilt as smooth lofted bodies in a glossy paint shader that reflects each track's sky,
  with glass cabins, painted wheel arches, head and tail lights, rims with spokes, and each team's
  own parts (ramjets, wings, sun-disc prow, brass hover pod, spines, goblin rocket, shark fin, war-rig cage).
- World: detailed city buildings (shop fronts, set-back tiers, framed windows, balconies, domes and
  turrets), fuller trees and palms, fluted columns, rounded curbs and crash barriers, and more
  detailed arches and landmarks. Distant props and Low quality use lighter versions.

## 4. World events (2026-10-12)
> Lets do one more change, I want "world" in individual races to interact with the race itself. Each
> race should have certain "events" that introduce complications and set backs to the racing cars,
> thus making outcome more rng dependent.

Built `scripts/hazards.gd`: every 15-25 s one of the track's two events fires 170-300 m ahead of a
random racer (the player 40% of the time), with a HUD banner, distance and minimap marker. Twelve
events, two per track (see README). Effects: grip and top-speed zones, aether gain or drain, sideways
gusts, obstacles, blasts and lightning that spin a car once round. AI drivers notice obstacles only
60% of the time per event (and always after hitting one), so results vary from race to race.
Sim test: every car still finishes every track; about 5-8 events and 2-16 spins per race.
Also fixed: the HUD's minimap, speedometer and aether meter never showed (the HUD had zero size).

## 5. Multiplayer with friends and bots (2026-10-13)
> I want to adjust the game now, I want there to be multiplayer option so that this can be played
> with friends and bots

Online rooms (`scripts/net.gd`): a player hosts a room (five-letter code and invite link), friends
join, everyone picks a team, the host picks track, laps and whether bots fill the grid, up to eight
players. Each player's car is simulated on their own computer and sent 20 times a second; the host
runs the bots, the world events (sent as kind + place + seed, so every player builds the same
event) and the results. In the browser the players connect peer to peer with WebRTC; the shop
page's Supabase Realtime channel only carries the connection handshake (`tools/web/aether-net.js`
batches it). On desktop the same code runs over ENet with the host's IP as the code.
Decided without asking: online play rather than split screen on one keyboard (the game lives on a
website, and "friends" usually means each at their own computer); no TURN relay server, so very
strict networks may not connect.
Tests: `tools/net_test.sh` (two Godot processes race a lap and must agree on the results) and two
headless Chromium tabs joining a room through the web build.
