-- A-Life: Reactive Survivors - shared core. One global table, ALifeReactive.
-- Nothing here touches Project A-Life at load time; the hooks and the tuning
-- are installed at OnGameStart / OnServerStarted (see server/ALifeReactive).
-- Settings live in 01_ALR_Settings.lua, speech lines in 02_ALR_Lines.lua.

ALifeReactive = ALifeReactive or {}
local A = ALifeReactive

A.MOD_ID = "ALifeReactiveSurvivors"
A.VERSION = "0.2.0"
A.TAG = "[ALR]"
A.settings = A.settings or {}

A.metrics = {
    reactiveChecks = 0, reactiveCommits = 0, reactiveRefused = 0, crowdRefused = 0, unarmedRefused = 0,
    leaseCaps = 0, ignoreCaps = 0, draws = 0, configures = 0, errors = 0,
    dodges = 0, dives = 0, courtesies = 0, fallbacks = 0, regroups = 0, bites = 0, hits = 0, lines = 0,
}

-- uid -> shell, as seen by our hooks (weak values).
A.shells = setmetatable({}, { __mode = "v" })

function A.now()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function A.log(...)
    local parts = { A.TAG }
    for index = 1, select("#", ...) do parts[#parts + 1] = tostring(select(index, ...)) end
    print(table.concat(parts, " "))
end

function A.fail(where, err)
    A.metrics.errors = A.metrics.errors + 1
    if A.settings.debug then A.log(where, "failed:", err) end
end

function A.rand(n)
    n = math.max(1, math.floor(tonumber(n) or 1))
    if type(ZombRand) == "function" then return ZombRand(n) end
    return math.random(0, n - 1)
end

local function instance(body, class)
    if body == nil or type(instanceof) ~= "function" then return false end
    local ok, result = pcall(instanceof, body, class)
    return ok and result == true
end

function A.isZombie(body) return instance(body, "IsoZombie") end
function A.isPlayer(body) return instance(body, "IsoPlayer") end

-- x, y, z of a game object, or nil.
function A.xyz(body)
    if body == nil or type(body.getX) ~= "function" then return nil end
    local ok, x, y, z = pcall(function() return body:getX(), body:getY(), body:getZ() end)
    if not ok or type(x) ~= "number" or type(y) ~= "number" then return nil end
    return x, y, type(z) == "number" and z or 0
end

function A.noteShell(actor, shell)
    if type(actor) == "table" and type(actor.uid) == "string" and shell ~= nil then A.shells[actor.uid] = shell end
end

function A.shellFor(uid)
    local shell = A.shells[uid]
    if shell ~= nil then return shell end
    local talk = ProjectALife and ProjectALife.Talk
    if talk ~= nil and type(talk.shellFor) == "function" then
        local ok, found = pcall(talk.shellFor, uid)
        if ok then return found end
    end
    return nil
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

function A.counters()
    local m = A.metrics
    return "checks=" .. m.reactiveChecks .. " commits=" .. m.reactiveCommits .. " refused=" .. m.reactiveRefused
        .. " crowdRefused=" .. m.crowdRefused .. " unarmedRefused=" .. m.unarmedRefused
        .. " dodges=" .. m.dodges .. " dives=" .. m.dives .. " stepAside=" .. m.courtesies
        .. " fallbacks=" .. m.fallbacks .. " regroups=" .. m.regroups .. " bites=" .. m.bites .. " hits=" .. m.hits
        .. " lines=" .. m.lines .. " leaseCaps=" .. m.leaseCaps .. " ignoreCaps=" .. m.ignoreCaps
        .. " draws=" .. m.draws .. " configures=" .. m.configures .. " errors=" .. m.errors
end

-- Console helper: ALifeReactive.status()
function A.status()
    A.log("v" .. A.VERSION, "enabled=" .. tostring(A.settings.enabled))
    A.log(A.counters())
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
