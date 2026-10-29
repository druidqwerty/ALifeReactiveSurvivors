-- A-Life: Reactive Survivors - every knob. Edit, then restart the game (or the
-- host). "base" = the value Project A-Life 1.4.6 uses on its own.

require "ALifeReactive/00_ALR_Core"

local A = ALifeReactive

A.settings = {
    enabled = true,
    debug = false,

    -- Lone zombie. Base: a travelling / idle NPC ignores a zombie until it is
    -- 1.5 tiles away. Here the NPC attacks a zombie within nearTiles, or within
    -- closingTiles while it walks at the NPC and is in sight. Unarmed NPCs keep
    -- the base behaviour when unarmedSkip is true.
    react = { enabled = true, nearTiles = 2.5, closingTiles = 6, needVisible = true, unarmedSkip = true },

    -- Crowd. gateCount zombies within radius: no early attack (A-Life decides at
    -- contact). fallbackCount zombies within radius, fallbackClosing of them
    -- walking at the NPC: run fallbackTiles away from the group, or to an ally
    -- (NPC of the same side, or a friendly player) within regroupTiles.
    crowd = { enabled = true, radius = 6, gateCount = 3, fallbackCount = 3, fallbackClosing = 2,
        fallbackTiles = 8, regroupTiles = 20, cooldownMs = 6000, legsPerMinute = 3, timeoutMs = 4500 },

    -- Vehicles (heard, no sight check). A vehicle faster than minKmh within
    -- rangeTiles whose path passes within laneTiles of the NPC in less than
    -- horizonS seconds: sidestep dodgeTiles at a sprint. Faster than diveKmh and
    -- less than diveS seconds away: diveTiles. Slower than slowKmh and within
    -- courtesyTiles of an idle NPC: step courtesyStep aside at a walk.
    vehicle = { enabled = true, sampleMs = 100, rangeTiles = 14, laneTiles = 2.0, horizonS = 2.2, diveS = 1.0,
        minKmh = 6, diveKmh = 25, slowKmh = 12, courtesyTiles = 5, dodgeTiles = 3, diveTiles = 4.5,
        courtesyStep = 2, cooldownMs = 1500, timeoutMs = 2500 },

    -- Speech lines (shared/Translate/<lang>/IG_UI.json). cooldownMs per NPC and
    -- situation unless the situation sets its own.
    lines = { enabled = true, cooldownMs = 8000, spotCooldownMs = 20000 },

    -- After a retreat the base mod avoids the same zombie for 25 s (9 s after
    -- a recovery). Cap for zombie targets, ms.
    lease = { zombieMs = 8000 },

    -- The base mod ignores a zombie for 10-15 s after a failed approach, a
    -- blocked line or another floor. Cap for zombie targets, ms.
    ignore = { zombieCapMs = 4000 },

    -- Weapon draw: scale of the base reach + take sequence (420+750 /
    -- 450+850 ms). 1 = base.
    draw = { scale = 0.8 },

    -- ProjectALife.BehaviorSettings.combat and Combat.settings.
    -- Base: ready 220, windup 150, recovery 680, interval 650,
    -- unreachable cooldown 1200, self-defence reach 1.5, closing run 80 % / 5.5.
    combat = {
        meleeReadyMs = 120,
        meleeWindupMs = 90,
        meleeRecoveryMs = 520,
        attackIntervalMs = 500,
        unreachableCooldownMs = 700,
        leashSelfDefenceReach = 2.0,
        closingRunChancePercent = 100,
        closingRunMinimumDistance = 3.5,
    },

    -- Pause after a swing clip per weapon class (Combat.MELEE_TIMING, base 400).
    meleeDelayMs = { oneHanded = 250, twoHanded = 300 },

    -- Endurance. Base: re-engage at 72, minimum retreat 2200, damage retreat 2600.
    endurance = { reengageThreshold = 50, minimumRetreatMs = 1500, damageRetreatMs = 1500 },

    -- Survival: retreat on recent damage only below this HP ratio (base 0.6).
    survival = { flinchHealth = 0.45 },

    -- Decision loop passive scan cadence. Base: 250 hot / 1000 mid / 2500 far,
    -- "close to a player" radius 12.
    lanes = { passiveHotMs = 150, passiveMidMs = 400, passiveFarMs = 1200, passiveCloseRadius = 16 },

    -- ZombieFocus relevance filter (A-Life's own and the Jeem Extension's copy
    -- in front of it). Base: ignore 750 ms, closing radius 15, radius from the
    -- sandbox (8). minRadius lifts a smaller sandbox radius (A-Life's filter
    -- only; Jeem reads its radius from its own option).
    focus = { ignoreMs = 400, closingRadius = 18, minRadius = 10 },

    -- Fear module. Base: ignore 1000 ms, far 8 tiles.
    fear = { ignoreMs = 500, farTiles = 10 },

    -- Caution module: "wait for the zombies to pass" idle. Base 3500 / 2500 ms.
    caution = { waitMs = 1500, lightWaitMs = 1200 },

    -- Gun discipline: how often "may I shoot this zombie" is re-rolled (base 30 s).
    gun = { rollMs = 10000 },

    -- Console report of the counters every N minutes (0 = off).
    report = { everyMinutes = 1 },
}

return A.settings
