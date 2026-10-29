-- A-Life: Reactive Survivors - speech lines. Texts live in
-- shared/Translate/<lang>/IG_UI.json as IGUI_ALR_<situation>_<n>; a situation
-- picks one of its `count` lines at random. Shown through A-Life's own
-- Speech.say (same bubble, same multiplayer mirroring, same "hurt" rules:
-- a hurt NPC only says lines with a pain event).

require "ALifeReactive/00_ALR_Core"

local A = ALifeReactive
local L = { lastAtMs = {}, lastText = {} }
A.Lines = L

-- pain = true: the NPC was just hit, and A-Life keeps a hit NPC quiet for 5 s
-- (Speech.quietHitMs) or swaps the text for its own "Aagh". Those lines go
-- through Speech.display directly (same bubble, colour and mirroring), unless
-- the NPC is down.
L.catalog = {
    spot = { count = 3 },
    crowd = { count = 3 },
    regroup = { count = 2 },
    unarmed = { count = 2 },
    vehicle_slow = { count = 2 },
    vehicle_dodge = { count = 3 },
    vehicle_dive = { count = 3 },
    vehicle_hit = { count = 2, pain = true },
    vehicle_hit_again = { count = 1, pain = true },
    bitten = { count = 2, pain = true },
}

local function painLine(speech, shell, text)
    if type(speech.display) ~= "function" then return false end
    if type(speech.quietReason) == "function" then
        local ok, reason = pcall(speech.quietReason, shell, nil, nil)
        if ok and reason == "downed" then return false end
    end
    if type(speech.refusedDead) == "function" then
        local ok, dead = pcall(speech.refusedDead, shell)
        if ok and dead == true then return false end
    end
    local uid, factionId
    if type(speech.variable) == "function" then
        local ok, value = pcall(speech.variable, shell, "ALifeUID")
        if ok then uid = value end
        ok, value = pcall(speech.variable, shell, "ALifeFactionId")
        if ok then factionId = value end
    end
    local color = { 220, 220, 220 }
    if type(speech.colorFor) == "function" then
        local ok, value = pcall(speech.colorFor, uid, factionId)
        if ok and type(value) == "table" then color = value end
    end
    local ok, shown = pcall(speech.display, shell, text, color, "pain", uid)
    return ok and shown ~= false
end

-- Every translation key the catalog needs (for the tests and the status).
function L.keys()
    local keys = {}
    for situation, entry in pairs(L.catalog) do
        for index = 1, entry.count do keys[#keys + 1] = "IGUI_ALR_" .. situation .. "_" .. index end
    end
    table.sort(keys)
    return keys
end

function L.text(situation)
    local entry = L.catalog[situation]
    if entry == nil then return nil end
    local index = A.rand(entry.count) + 1
    local key = "IGUI_ALR_" .. situation .. "_" .. index
    local text = type(getText) == "function" and getText(key) or nil
    if type(text) ~= "string" or text == "" or text == key then return nil end
    return text, entry.event, entry.pain == true
end

-- Say a line for `situation`; false when disabled, on cooldown or quieted.
function L.say(actor, shell, situation, cooldownMs)
    if not A.settings.enabled or type(A.settings.lines) ~= "table" or not A.settings.lines.enabled
            or shell == nil then
        return false
    end
    local uid = type(actor) == "table" and tostring(actor.uid or "?") or "?"
    local now = A.now()
    local key = uid .. ":" .. tostring(situation)
    if now < (L.lastAtMs[key] or 0) then return false end
    local text, event, pain = L.text(situation)
    if text == nil then return false end
    local speech = ProjectALife and ProjectALife.Speech
    if speech == nil or type(speech.say) ~= "function" then return false end
    local shown
    if pain then
        shown = painLine(speech, shell, text)
    else
        local ok, result = pcall(speech.say, shell, text, { event = event })
        if not ok then
            A.fail("say", result)
            return false
        end
        shown = result
    end
    if shown == false then return false end
    L.lastAtMs[key] = now + (tonumber(cooldownMs) or tonumber(A.settings.lines.cooldownMs) or 8000)
    L.lastText[uid] = text
    A.metrics.lines = A.metrics.lines + 1
    return true
end

A.say = L.say

return L
