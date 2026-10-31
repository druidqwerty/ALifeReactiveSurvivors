-- One world/server configuration. Multiplayer clients consume the game's
-- synchronized SandboxVars, never a separate per-player ModOptions table.
require "ALifeReactive/01_ALR_Settings"

local A = ALifeReactive
local S = { namespace = "ALifeReactiveSurvivors", pollMs = 2000, entries = {} }
A.Sandbox = S
local tuning = { combat = true, meleeDelayMs = true, endurance = true, survival = true,
    lanes = true, focus = true, fear = true, caution = true, gun = true }

-- group, key, type, minimum, maximum. Defaults come from 01_ALR_Settings.
local rows = {
    { "", "enabled", "boolean" },
    { "", "debug", "boolean" },
    { "react", "enabled", "boolean" },
    { "react", "nearTiles", "double", 0.5, 10 },
    { "react", "closingTiles", "double", 1, 25 },
    { "react", "needVisible", "boolean" },
    { "react", "unarmedSkip", "boolean" },
    { "crowd", "enabled", "boolean" },
    { "crowd", "safeRetreat", "boolean" },
    { "crowd", "radius", "double", 2, 16 },
    { "crowd", "gateCount", "integer", 2, 30 },
    { "crowd", "fallbackCount", "integer", 2, 30 },
    { "crowd", "fallbackClosing", "integer", 1, 20 },
    { "crowd", "fallbackTiles", "double", 2, 12 },
    { "crowd", "regroupTiles", "double", 3, 30 },
    { "crowd", "cooldownMs", "integer", 1000, 60000 },
    { "crowd", "legsPerMinute", "integer", 1, 12 },
    { "crowd", "timeoutMs", "integer", 1000, 15000 },
    { "vehicle", "enabled", "boolean" },
    { "vehicle", "sampleMs", "integer", 50, 1000 },
    { "vehicle", "rangeTiles", "double", 4, 30 },
    { "vehicle", "laneTiles", "double", 0.5, 5 },
    { "vehicle", "horizonS", "double", 0.5, 5 },
    { "vehicle", "diveS", "double", 0.1, 3 },
    { "vehicle", "minKmh", "double", 1, 30 },
    { "vehicle", "diveKmh", "double", 5, 100 },
    { "vehicle", "slowKmh", "double", 1, 40 },
    { "vehicle", "courtesyTiles", "double", 1, 10 },
    { "vehicle", "dodgeTiles", "double", 1, 6 },
    { "vehicle", "diveTiles", "double", 1, 8 },
    { "vehicle", "courtesyStep", "double", 0.5, 4 },
    { "vehicle", "cooldownMs", "integer", 500, 15000 },
    { "vehicle", "timeoutMs", "integer", 500, 10000 },
    { "lines", "enabled", "boolean" },
    { "lines", "cooldownMs", "integer", 0, 120000 },
    { "lines", "spotCooldownMs", "integer", 1000, 120000 },
    { "lease", "zombieMs", "integer", 500, 60000 },
    { "ignore", "zombieCapMs", "integer", 250, 30000 },
    { "draw", "scale", "double", 0.2, 1 },
    { "combat", "meleeReadyMs", "integer", 0, 2000 },
    { "combat", "meleeWindupMs", "integer", 20, 2000 },
    { "combat", "meleeRecoveryMs", "integer", 100, 3000 },
    { "combat", "attackIntervalMs", "integer", 100, 5000 },
    { "combat", "unreachableCooldownMs", "integer", 100, 10000 },
    { "combat", "leashSelfDefenceReach", "double", 0.5, 5 },
    { "combat", "closingRunChancePercent", "integer", 0, 100 },
    { "combat", "closingRunMinimumDistance", "double", 1, 12 },
    { "meleeDelayMs", "oneHanded", "integer", 50, 2000 },
    { "meleeDelayMs", "twoHanded", "integer", 50, 2000 },
    { "endurance", "reengageThreshold", "double", 0, 100 },
    { "endurance", "minimumRetreatMs", "integer", 200, 15000 },
    { "endurance", "damageRetreatMs", "integer", 200, 15000 },
    { "survival", "flinchHealth", "double", 0.05, 1 },
    { "lanes", "passiveHotMs", "integer", 50, 1000 },
    { "lanes", "passiveMidMs", "integer", 100, 5000 },
    { "lanes", "passiveFarMs", "integer", 250, 10000 },
    { "lanes", "passiveCloseRadius", "double", 4, 40 },
    { "focus", "ignoreMs", "integer", 50, 5000 },
    { "focus", "closingRadius", "double", 3, 30 },
    { "focus", "minRadius", "double", 3, 20 },
    { "fear", "ignoreMs", "integer", 50, 10000 },
    { "fear", "farTiles", "double", 2, 25 },
    { "caution", "waitMs", "integer", 250, 15000 },
    { "caution", "lightWaitMs", "integer", 250, 15000 },
    { "gun", "rollMs", "integer", 1000, 60000 },
    { "report", "everyMinutes", "integer", 0, 60 },
}

local function capital(text) return (text:gsub("^%l", string.upper)) end
for _, row in ipairs(rows) do
    local group, key = row[1], row[2]
    local source = group == "" and A.settings or A.settings[group]
    S.entries[#S.entries + 1] = { group = group, key = key, kind = row[3], min = row[4], max = row[5],
        default = source[key], option = (group == "" and "" or capital(group) .. "_") .. capital(key),
        tuning = tuning[group] == true }
end

function S.value(entry, raw)
    if entry.kind == "boolean" then
        if type(raw) == "boolean" then return raw end
        return entry.default
    end
    local number = tonumber(raw)
    if number == nil or number ~= number or number == math.huge or number == -math.huge then
        return entry.default
    end
    number = math.max(entry.min, math.min(entry.max, number))
    if entry.kind == "integer" then number = math.floor(number + 0.5) end
    return number
end

-- Missing options on old saves use shipped defaults. Update nested tables in
-- place because hooks may retain references. Return only meaningful changes.
function S.refresh()
    local vars = type(SandboxVars) == "table" and SandboxVars[S.namespace] or nil
    if type(vars) ~= "table" then vars = {} end
    local changed, tuningChanged, enabledChanged = false, false, false
    for _, entry in ipairs(S.entries) do
        local target = entry.group == "" and A.settings or A.settings[entry.group]
        local value = S.value(entry, vars[entry.option])
        if target[entry.key] ~= value then
            target[entry.key], changed = value, true
            tuningChanged = tuningChanged or entry.tuning
            enabledChanged = enabledChanged or (entry.group == "" and entry.key == "enabled")
        end
    end
    return changed, tuningChanged, enabledChanged
end

return S
