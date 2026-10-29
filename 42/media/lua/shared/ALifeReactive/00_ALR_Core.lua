-- A-Life: Reactive Survivors - shared core. One global table, ALifeReactive.
-- Nothing here touches Project A-Life at load time; the hooks and the tuning
-- are installed at OnGameStart / OnServerStarted (see server/ALifeReactive).

ALifeReactive = ALifeReactive or {}
local A = ALifeReactive

A.MOD_ID = "ALifeReactiveSurvivors"
A.VERSION = "0.1.0"
A.TAG = "[ALR]"

-- Every knob of phase 1. Edit, then restart the game (or the host).
-- "base" = the value Project A-Life 1.4.6 uses on its own.
A.settings = {
    enabled = true,
    debug = false,

    -- Reactive engagement. Base: a travelling / idle NPC ignores a zombie until
    -- it is 1.5 tiles away (contact). Here the NPC commits to a zombie that is
    -- within nearTiles, or within closingTiles while walking at the NPC and in
    -- sight. Retreating / recovering NPCs, zombie-avoid mode and gun discipline
    -- keep the base behaviour.
    react = {
        enabled = true,
        nearTiles = 2.5,
        closingTiles = 6,
        needVisible = true,
    },

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

A.metrics = {
    reactiveChecks = 0, reactiveCommits = 0, reactiveRefused = 0,
    leaseCaps = 0, ignoreCaps = 0, draws = 0, configures = 0, errors = 0,
}

function A.now()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function A.log(...)
    local parts = { A.TAG }
    for index = 1, select("#", ...) do parts[#parts + 1] = tostring(select(index, ...)) end
    print(table.concat(parts, " "))
end

function A.isZombie(body)
    if body == nil or type(instanceof) ~= "function" then return false end
    local ok, result = pcall(instanceof, body, "IsoZombie")
    return ok and result == true
end

-- Replace tbl[name] with factory(original). False when there is nothing to wrap.
A.wrapped = A.wrapped or {}
function A.wrap(tbl, name, factory, label)
    label = label or name
    if type(tbl) ~= "table" or type(tbl[name]) ~= "function" then
        A.log("hook skipped:", label)
        return false
    end
    if A.wrapped[label] ~= nil then return true end
    local original = tbl[name]
    tbl[name] = factory(original)
    A.wrapped[label] = original
    return true
end

-- tbl[key] = value, remembering the first original value (for status()).
A.originals = A.originals or {}
function A.set(tbl, key, value, label)
    if type(tbl) ~= "table" or value == nil then return false end
    label = label or key
    if A.originals[label] == nil then A.originals[label] = { was = tbl[key], now = value } end
    tbl[key] = value
    return true
end

-- Console helper: ALifeReactive.status()
function A.status()
    A.log("v" .. A.VERSION, "enabled=" .. tostring(A.settings.enabled))
    local m = A.metrics
    A.log("checks=" .. m.reactiveChecks, "commits=" .. m.reactiveCommits, "refused=" .. m.reactiveRefused,
        "leaseCaps=" .. m.leaseCaps, "ignoreCaps=" .. m.ignoreCaps, "draws=" .. m.draws,
        "configures=" .. m.configures, "errors=" .. m.errors)
    local names = {}
    for label in pairs(A.originals) do names[#names + 1] = label end
    table.sort(names)
    for _, label in ipairs(names) do
        local entry = A.originals[label]
        A.log(label, tostring(entry.was) .. " -> " .. tostring(entry.now))
    end
    for label in pairs(A.wrapped) do A.log("wrapped", label) end
end

return A
