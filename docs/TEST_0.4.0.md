# Reactive Survivors 0.4.0 verification

Target: Project Zomboid 42.21, Project A-Life 1.4.6, ZombieBuddy 2.3.4 standard agent.
Joint scenarios load Caravans 0.6.0, Jeem Extension 0.7.5 and Living Factions 0.2.2.
All game worlds and characters used here are isolated fixtures, not the player's saves.

## Findings and changes

Cooperative logs showed low engagement activity and increasing bite counts, but counters alone do
not prove that an individual NPC was frozen. Code inspection found that the existing engagement
wrapper did not cover passive idle/recovering actors early enough. The new awareness pass uses
the existing owning A-Life decision loop, bounded visible threats, normal combat engagement and
checked short retreat paths. Orders, conversations, gun fear, passengers and existing movement
retain priority. It does not create a second NPC scheduler or force pointless wandering.

Actual game testing exposed an additional handoff defect: A-Life's passive-state interruption
canceled the newly created ALR action while retiring the old one. The adapter now retires the old
action before starting ours and protects only the exact new UID/generation/action object from
the immediate `gun_fear` cancellation once. Death, orders, replacement actions, later cancellation
and ownership loss remain effective. No upstream source files are modified.

A second MP trace showed a legitimate action completing after only 0.73 tiles: the checked planner
selected its 1.5-tile fallback, but A-Life's default 0.8 arrival tolerance consumed most of it.
The add-on now supplies a 0.3 tolerance only for its short make-space action, not global movement.

## Automated checks

`python tools/run_test.py`: **743 assertions passed** (63 + 60 + 31 + 548 + 41).
The 41 new awareness/bootstrap/handoff checks include threat visibility, budgets, role exclusions,
safe-path refusal, startup retry, old-action retirement, single-use protection and cancellation
for expired/replaced/dead actors. Translation key parity is also checked.

## Actual single-player result

Cold SP run 053654 used the final runtime, with Jeem and Living Factions loaded.

| Case | Threat distance when reacting | Genuine displacement | Action during displacement |
| --- | --- | --- | --- |
| Armed NPC | 4.53992 tiles | 1.09601 tiles / 2133 ms | `alr_alert`, running |
| Unarmed NPC | 3.43949 tiles | 1.04983 tiles / 667 ms | `alr_make_space`, running |

The observer requires at least one tile of movement tied to the exact ALR action: running, or
successfully completed within the last 200 ms with the body within 0.35 tiles of its exact target.
Counter increments, cancelled actions and later unrelated patrol do not qualify. Earlier loose observations were invalidated after
finding the cancellation bug and are not counted as passing evidence. Fixture initialization
preserves healthy NPC health; setting it to 2 had accidentally injured an A-Life actor and triggered
Jeem's unrelated damage/radio behavior.

## Final cold MP run 053850

Dedicated server +two real clients, exact release runtime, with Jeem/Living Factions.
Caravans is installed with identical runtime but its population disabled for this standalone scene.

- **Reactive server:** PASS natural owner-client make-space before contact, actual action movement and other-client replication
- **Reactive primary client:** PASS owner natural reaction at 5.739079263456493 tiles; actual make-space movement=1.028505777731297 action=running
- **Reactive observer client:** PASS spectator saw original actor move 0.9405594812431309 tiles

A fresh fixture actor uses normal owning-client thinking. Only fixture equipment and its initial
idle state are prepared; a real spawned zombie approaches. The owner must react before contact and
move at least one tile tied to the exact ALR action as described above; the other client must observe
replicated movement of that same actor. See [live-0.4.0.txt](live-0.4.0.txt).

Two earlier MP attempts in the post-Caravans world were not counted: network latency let the first
actor patrol before the threat arrived; a subsequent replacement existed in A-Life registry but
never appeared physically on either client (upstream replica_missing/shell_recovery logs). The
fresh standalone test avoids that body-reuse setup. Missing upstream replicas cannot react; this
release does not claim to fix A-Life actor replication/recovery itself.

## Limits and integrity

This is local awareness and a checked short step, not a global navigator or survival guarantee.
An NPC with no safe candidate may stay put. Existing car-dodge combat/indoor restrictions remain.
A bite computed on another client may still be missed by the owning NPC client. Large mod packs,
long sessions and ownership churn need broader coverage; two-client tests do not certify them all.

Reactive has no standalone trade/contact window to reskin. Its 66 global settings remain in live
Sandbox options; Caravans supplies the redesigned original trade/contact UI and optional Jeem palette.

The runtime hash manifest and sanitized live evidence accompany this report. Release packaging
checks exact cold-run bytes; private launchers/caches, credentials, upstream mods and player logs
are excluded. All SP runtime files, including mod.info, match the release.
