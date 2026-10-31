# 0.3.0 verification — 2026-10-31

## Scope

Project Zomboid Build 42.21, installed Project A-Life 1.4.6, isolated single-player Sandbox world.
This checks a controlled real crowd interrupt and real engine movement, not a long gameplay session or multiplayer
ownership transfer. All 13 runtime Lua files in the tested profile were byte-identical to the release source.

## Automated checks

- 63 original tuning/engagement regressions.
- 60 vehicle/crowd/speech regressions (legacy geometric retreat explicitly selected there).
- 31 safe-retreat assertions: second crowd, obstacles, fire/campfire/water, floor holes, unloaded cells,
  diagonal side tiles, visibility/work limits, contact escape, missing APIs, no-safe/no-movement fall-through,
  and unchanged combat/guard/order handling.
- 548 configuration/schema assertions for 66 options: defaults, bounds, invalid numbers, translations,
  live enable/disable, reversible tuning, external mod writes, configure rebuilding and two-second polling.
- Total: **702 passed, 0 failed**. Runtime Lua syntax: **13 passed**. Speech catalog EN/RU parity passed.

## Real-game scenario

- Sandbox `Crowd_SafeRetreat` changed false, then true; the normal two-second polling applied both changes.
- Real A-Life actor and six real zombie bodies. Crowd snapshot at interruption: count=3, closing=3.
- Three solid test obstacles blocked the direct westward route; the actual engine route checker rejected it.
- Original `Hazards.interrupt` and A-Life movement helpers chose `(10632.79, 10276.53)`
  from `(10629.09, 10283.63)`.
- Thirteen position samples recorded **7.238 tiles of actual displacement**, ending 0.762 tiles from the goal.
  No sampled position entered a test obstacle.
- ALR's runtime error counter remained **0** during the scenario.

The fixture established the passive starting state explicitly; this is not a claim that every spontaneous NPC
state transition or every possible escape geometry was tested. No production behavior was patched to force a pass.

## Test tooling notes

The first fixture requested zero zombie population using the option that disables manual zombie creation too.
It was corrected in the isolated test world, then the scenario was rerun without changing production source.
The log also contains a vanilla mannequin-zone warning and a test-only UI/screenshot-control exception after
the successful movement scenario; these are not represented as a completely error-free game session.

Evidence was retained locally in `tools/livetest/runs/20261031_183838/`:
`cache/console.txt`, `cache/Lua/ALRLive_result.txt`, `runtime_hashes.json`, `game_184348.png`.
Run profiles, user-derived options, game/dependency files and raw saves are deliberately excluded from Git.

## Remaining coverage limits

Multiplayer handoffs, mixed-client bite ownership, long sessions, large mod packs and Jeem-specific live behavior
were not verified here. The release keeps these limitations visible in the README and Workshop description.
