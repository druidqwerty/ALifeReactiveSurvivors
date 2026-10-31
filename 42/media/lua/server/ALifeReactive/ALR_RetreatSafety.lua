-- Small, conservative checks for short crowd escapes. No new pathfinder.
require "ALifeReactive/00_ALR_Core"
require "ALifeReactive/ALR_Crowd"
local A = ALifeReactive
local S = {}
A.RetreatSafety = S

-- Loaded geometry only. Stay in this building/outdoors: Movement.begin can
-- otherwise replace a validated target with a different building entrance.
function S.route(shell, origin, target)
    local p = ProjectALife
    if p == nil or p.FireManeuver == nil or type(p.FireManeuver.route) ~= "function"
            or p.Caution == nil or type(p.Caution.squareHazard) ~= "function"
            or type(getCell) ~= "function" then return false end
    local ok, clear = pcall(function()
        local cell = getCell()
        if cell == nil then return false end
        local floor = math.floor(origin.z)
        local start = cell:getGridSquare(math.floor(origin.x), math.floor(origin.y), floor)
        if start == nil or type(start.getBuilding) ~= "function" then return false end
        local building = start:getBuilding()
        if not p.FireManeuver.route(shell, origin, target) then return false end
        local dx, dy = target.x - origin.x, target.y - origin.y
        local count = math.ceil(math.sqrt(dx * dx + dy * dy) * 4)
        if count < 1 or count > 64 then return false end
        local function safeTile(x, y)
            local square = cell:getGridSquare(x, y, floor)
            return square ~= nil and type(square.TreatAsSolidFloor) == "function"
                and square:TreatAsSolidFloor() == true and square:getBuilding() == building
                and p.Caution.squareHazard(square) == nil
        end
        local lastX, lastY = math.floor(origin.x), math.floor(origin.y)
        for i = 1, count do
            local x, y = math.floor(origin.x + dx * i / count), math.floor(origin.y + dy * i / count)
            if x ~= lastX or y ~= lastY then
                if not safeTile(x, y) then return false end
                -- A diagonal may touch a side tile between the 1/4-tile
                -- samples. Reject unsafe corner cuts as well as landings.
                if x ~= lastX and y ~= lastY and
                        (not safeTile(lastX, y) or not safeTile(x, lastY)) then return false end
                lastX, lastY = x, y
            end
        end
        return true
    end)
    return ok and clear == true
end

-- Snapshot includes hidden/dead zombies. Use close hearing (base Caution's
-- six-tile range) or actual Perception visibility; never global omniscience.
function S.threats(shell, origin, now, radius)
    local p = ProjectALife and ProjectALife.Perception
    if p == nil or type(p.snapshotFor) ~= "function" then return nil end
    local ok, rows = pcall(A.Crowd.rowsNear, p, now, origin.x, origin.y, radius, 129)
    if not ok or #rows > 128 then return nil end
    local known, rays = {}, 0
    for _, row in ipairs(rows) do
        if row.body ~= nil and math.abs((row.z or origin.z) - origin.z) < 0.4 then
            local alive, dead = pcall(function() return row.body:isDead() end)
            if not alive then return nil end
            if alive and not dead then
                local near = (row.x - origin.x) ^ 2 + (row.y - origin.y) ^ 2 <= 36
                local seen = near
                if not near then
                    if rays >= 16 or type(p.visible) ~= "function" then return nil end
                    rays = rays + 1
                    local visibleOK, visible = pcall(p.visible, shell, row.body)
                    seen = visibleOK and visible == true
                end
                if seen then known[#known + 1] = row end
            end
        end
    end
    return known
end

function S.pressure(point, rows)
    local pressure, nearest = 0, 1000
    for _, row in ipairs(rows) do
        local distance = math.sqrt((point.x - row.x) ^ 2 + (point.y - row.y) ^ 2)
        nearest = math.min(nearest, distance)
        if distance < 5 then pressure = pressure + ((5 - distance) / 5) ^ 2 end
    end
    return pressure, nearest
end

-- Analytic segment distance prevents running through a zombie between two
-- sampled endpoints. Already in contact: allow a strictly outward escape.
function S.rank(origin, target, rows, initialPressure, initialNearest)
    local dx, dy = target.x - origin.x, target.y - origin.y
    local length2 = dx * dx + dy * dy
    if length2 < 1 then return nil end
    local pathRisk = 0
    for _, row in ipairs(rows) do
        local rx, ry = row.x - origin.x, row.y - origin.y
        local start2 = rx * rx + ry * ry
        local dot = rx * dx + ry * dy
        local t = math.max(0, math.min(1, dot / length2))
        local closest2 = (rx - t * dx) ^ 2 + (ry - t * dy) ^ 2
        if start2 < 2.25 then
            if dot >= 0 then return nil end
        elseif closest2 < 2.25 then return nil end
        pathRisk = pathRisk + math.max(0, 3 - math.sqrt(closest2)) * 0.3
    end
    local pressure, nearest = S.pressure(target, rows)
    if pressure > initialPressure + 0.001 or nearest < math.min(5, initialNearest + 0.5) then return nil end
    return pressure * 20 + math.max(0, 5 - nearest) * 3 + pathRisk + math.sqrt(length2) * 0.02
end

return S
