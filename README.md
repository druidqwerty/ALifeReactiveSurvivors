# A-Life: Reactive Survivors [B42] — experimental

An add-on for [Project A-Life [ALIFE NPCS]](https://steamcommunity.com/sharedfiles/filedetails/?id=3803984183) (by Vice):
NPCs react to zombies sooner and fight back faster. Project A-Life itself is not changed and none of its code is
copied; this is a separate Lua mod that adjusts A-Life through its public tables and functions.

> **Experimental, not tested in game yet.** v0.1.0 passes an offline simulation test only. It is not on the
> Steam Workshop; it will go there after a real in-game test. Feedback is welcome in the Issues.

**Source code (MIT):** https://github.com/druidqwerty/ALifeReactiveSurvivors

<p align="center"><a href="https://boosty.to/lrgpp"><img src="docs/banner.png" alt="LrgPP mods on Boosty" width="640"></a></p>

Free and open source. The code is written by an AI; the direction, the testing and the time are mine. If the mod made your game better: [support on Boosty](https://boosty.to/lrgpp).

Русская версия: [README_RU.md](README_RU.md)

## The problem

A zombie walks 7-10 tiles straight at an A-Life NPC. The NPC watches it, does not draw a weapon, and then stands
still while it gets bitten. Reading A-Life 1.4.6 shows why:

- a travelling or idle NPC "bypasses" a zombie until it is within 1.5 tiles (contact), so the zombie bites first;
- at contact the weapon draw takes about 1.2 s and a one-handed swing cycle about 1.5 s;
- after one retreat the NPC avoids that zombie for 25 s, and after a failed approach it ignores it for 10-15 s.

## What the add-on does

- **Reacts before contact.** A zombie within 6 tiles that walks at the NPC and is in sight, or any zombie within
  2.5 tiles, makes the NPC attack instead of ignoring it. Retreating or recovering NPCs, the "avoid zombies" mode
  and A-Life's gun discipline keep their own decision.
- **Fights faster.** Weapon draw 20 % shorter; shorter swing preparation, windup, recovery and pause between swings.
- **Gets stuck less.** Avoids a zombie for 8 s after a retreat instead of 25 s; ignores it at most 4 s after a failed
  approach; scans for threats 150 / 400 / 1200 ms instead of 250 / 1000 / 2500 ms; returns to the fight at
  endurance 50 instead of 72.
- Works with the Jeem Extension: its own zombie-focus filter gets the same numbers.

Zombies are not changed. In multiplayer the add-on runs where A-Life runs the NPC (also on the players' games).

## Requirements and installation

- Project Zomboid Build 42 (42.20+), [Project A-Life [ALIFE NPCS]](https://steamcommunity.com/sharedfiles/filedetails/?id=3803984183).
- Download the zip from [Releases](https://github.com/druidqwerty/ALifeReactiveSurvivors/releases) and unpack it to
  `%USERPROFILE%\Zomboid\mods\` so that you get `mods\ALifeReactiveSurvivors\42\mod.info`.
- Enable "A-Life: Reactive Survivors" in the mod list. In co-op every player needs the same folder, and the host adds
  the mod to the server's mod list.

## Settings

All numbers are in `42/media/lua/shared/ALifeReactive/00_ALR_Core.lua`, each with A-Life's own value next to it.
Edit and restart. `enabled = false` turns the add-on off; `draw.scale = 1` restores the normal draw animation.

## Is it working?

- `console.txt` shows `[ALR] v0.1.0 installed` and `[ALR] tuning re-applied after Decisions.configure`.
- Every minute (when something changed): `[ALR] checks=.. commits=.. refused=..`. `commits` grows when an NPC
  attacked a zombie earlier than A-Life would have.
- Lua console: `ALifeReactive.status()` prints the counters and every changed value (was -> now).

## Known limitations

- Not tested in game yet.
- Multiplayer: a zombie's bite can be computed on another player's game than the one running the NPC, so the NPC may
  not learn that it is being bitten. Planned for phase 2.
- Bite stagger (0.5 s) and the zombies' own behaviour are untouched.

## Source and tests

- `42/media/lua/` — the mod (4 Lua files, global table `ALifeReactive`).
- `tools/run_test.py` — simulation test with stubbed A-Life tables (Python + [lupa](https://pypi.org/project/lupa/)):
  `python tools/run_test.py` → `RESULT passed=63 failed=0`.

## My mods
- [SmoothRide MP](https://steamcommunity.com/sharedfiles/filedetails/?id=3827367565) — smooth multiplayer vehicles.
- [ZombieSync MP](https://steamcommunity.com/sharedfiles/filedetails/?id=3827946115) — smooth multiplayer zombies.
- [Tripping Zombies MP Fix](https://steamcommunity.com/sharedfiles/filedetails/?id=3829034899) — the same Tripping Zombies trips for every player.
- [Wandering Hordes Performance Fix](https://steamcommunity.com/sharedfiles/filedetails/?id=3829140377) — no save freezes and no client lag from Wandering Hordes.
- [Download Unstuck](https://steamcommunity.com/sharedfiles/filedetails/?id=3829163351) — un-sticks the Workshop download when hosting from the menu.
- **A-Life: Reactive Survivors** — A-Life NPCs react to zombies sooner (this mod, experimental).

## Credits and license

Project A-Life is by Vice; this add-on only works alongside it. Add-on code: MIT.
