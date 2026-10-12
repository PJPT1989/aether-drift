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
