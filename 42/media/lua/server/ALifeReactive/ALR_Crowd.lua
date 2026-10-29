-- A-Life: Reactive Survivors - zombies around an NPC and the way out.
-- Reads A-Life's zombie snapshot (Perception.snapshotFor, rebuilt every
-- 200 ms) through its 16-tile buckets, so a scan costs a few dozen checks.

require "ALifeReactive/00_ALR_Core"

local A = ALifeReactive
local C = {}
A.Crowd = C

local function bodiesNear(perception, now, sx, sy, radius)
    local snapshot = perception.snapshotFor(now)
    local bodies = type(snapshot) == "table" and snapshot.bodies or nil
    if type(bodies) ~= "table" then return {} end
    local out, r2 = {}, radius * radius
    local cells = snapshot.cells
    if cells == nil and snapshot.cellsOff ~= true and type(perception.buildCells) == "function" then
        cells = perception.buildCells(snapshot)
    end
    if type(cells) == "table" and snapshot.cellsOff ~= true then
        local size, floor = snapshot.cellSize or 16, math.floor
        for cx = floor((sx - radius) / size), floor((sx + radius) / size) do
            for cy = floor((sy - radius) / size), floor((sy + radius) / size) do
                local list = cells[cx * 2097152 + cy]
                if list ~= nil then
                    for _, index in ipairs(list) do
                        local row = bodies[index]
                        if row ~= nil and (row.x - sx) ^ 2 + (row.y - sy) ^ 2 <= r2 then out[#out + 1] = row end
                    end
                end
            end
        end
        return out
    end
    for _, row in ipairs(bodies) do
        if (row.x - sx) ^ 2 + (row.y - sy) ^ 2 <= r2 then out[#out + 1] = row end
    end
    return out
end

-- Zombies within settings.crowd.radius on the shell's floor: count, how many
-- walk at the shell, their centroid and the nearest one.
function C.scan(actor, shell, now)
    local result = { count = 0, closing = 0, cx = 0, cy = 0, nearest = nil, nearestD2 = math.huge }
    local perception = ProjectALife and ProjectALife.Perception
    if perception == nil or type(perception.snapshotFor) ~= "function" then return result end
    local sx, sy, sz = A.xyz(shell)
    if sx == nil then return result end
    local ok, rows = pcall(bodiesNear, perception, now, sx, sy, tonumber(A.settings.crowd.radius) or 6)
    if not ok then
        A.fail("crowd scan", rows)
        return result
    end
    local sumx, sumy = 0, 0
    for _, row in ipairs(rows) do
        if math.abs((row.z or sz) - sz) < 0.5 then
            result.count = result.count + 1
            sumx, sumy = sumx + row.x, sumy + row.y
            local d2 = (row.x - sx) ^ 2 + (row.y - sy) ^ 2
            if d2 < result.nearestD2 then result.nearest, result.nearestD2 = row.body, d2 end
            if type(perception.closingSpeed) == "function" then
                local okSpeed, speed = pcall(perception.closingSpeed, shell, row.body)
                if okSpeed and (tonumber(speed) or 0) > 0 then result.closing = result.closing + 1 end
            end
        end
    end
    if result.count > 0 then result.cx, result.cy = sumx / result.count, sumy / result.count end
    return result
end

local function friendlyPlayers(actor)
    local a = ProjectALife
    local locator, relations = a.PlayerLocator, a.Relations
    if locator == nil or type(locator.list) ~= "function" or relations == nil
            or type(relations.playerStance) ~= "function" then return {} end
    local ok, players = pcall(locator.list)
    if not ok or type(players) ~= "table" then return {} end
    local out = {}
    for _, player in ipairs(players) do
        local okStance, stance = pcall(relations.playerStance, actor, player)
        if okStance and (stance == "friendly" or stance == "allied") then
            local x, y, z = A.xyz(player)
            if x ~= nil then out[#out + 1] = { body = player, x = x, y = y, z = z } end
        end
    end
    return out
end

-- Nearest ally within radius: an NPC of the same side or a friendly player.
-- Returns { body, x, y, z } or nil.
function C.ally(actor, shell, now, radius)
    local a = ProjectALife
    local perception, relations = a and a.Perception, a and a.Relations
    local sx, sy, sz = A.xyz(shell)
    if sx == nil or perception == nil or relations == nil then return nil end
    local r2, best, bestD2 = radius * radius, nil, math.huge
    local function consider(row)
        if row.body == shell or math.abs((row.z or sz) - sz) >= 0.5 then return end
        local d2 = (row.x - sx) ^ 2 + (row.y - sy) ^ 2
        if d2 <= r2 and d2 < bestD2 then best, bestD2 = row, d2 end
    end
    if type(perception.snapshotFor) == "function" and type(perception.activeActorForShell) == "function"
            and type(relations.sameSide) == "function" then
        local snapshot = perception.snapshotFor(now)
        local rows = type(snapshot) == "table" and snapshot.actors or nil
        for _, row in ipairs(type(rows) == "table" and rows or {}) do
            local okA, other = pcall(perception.activeActorForShell, row.body)
            if okA and type(other) == "table" and other ~= actor then
                local okS, same = pcall(relations.sameSide, actor, other)
                if okS and same == true then consider(row) end
            end
        end
    end
    for _, row in ipairs(friendlyPlayers(actor)) do consider(row) end
    return best
end

-- Where to run: to the ally when it is not behind the crowd, else straight
-- away from the crowd's centre. Returns target, "regroup" | "crowd".
function C.fallbackPoint(shell, crowd, ally, tiles)
    local sx, sy, sz = A.xyz(shell)
    if sx == nil then return nil end
    local ax, ay = sx - crowd.cx, sy - crowd.cy
    local len = math.sqrt(ax * ax + ay * ay)
    if len < 0.1 then ax, ay, len = 1, 0, 1 end
    ax, ay = ax / len, ay / len
    if ally ~= nil then
        local tx, ty = ally.x - sx, ally.y - sy
        local tl = math.sqrt(tx * tx + ty * ty)
        if tl > 1 and (tx / tl) * ax + (ty / tl) * ay > -0.2 then
            local stop = math.max(0, tl - 1.5)
            return { x = sx + tx / tl * stop, y = sy + ty / tl * stop, z = sz }, "regroup"
        end
    end
    return { x = sx + ax * tiles, y = sy + ay * tiles, z = sz }, "crowd"
end

return C
