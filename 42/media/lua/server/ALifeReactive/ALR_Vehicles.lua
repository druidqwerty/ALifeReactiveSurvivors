-- A-Life: Reactive Survivors - moving vehicles and the geometry of a near miss.
-- NPCs "hear" vehicles: no sight check. Velocity in tiles per second comes
-- from two position samples; a vehicle seen for the first time uses its
-- forward vector (map-plane components x and z, as A-Life reads them) and the
-- speedometer.

require "ALifeReactive/00_ALR_Core"

local A = ALifeReactive
local V = { moving = {}, samples = setmetatable({}, { __mode = "k" }), refreshedAtMs = -1, lastError = nil }
A.Vehicles = V

local function kmh(vehicle)
    local ok, value = pcall(vehicle.getCurrentSpeedKmHour, vehicle)
    if ok then return tonumber(value) or 0 end
    return 0
end

local function forward(vehicle)
    local ok, fx, fy = pcall(function()
        local f = vehicle:getForwardVector(Vector3f.new())
        return f:x(), f:z()
    end)
    if ok and type(fx) == "number" and type(fy) == "number" then return fx, fy end
    return nil
end

-- Rows { vehicle, x, y, z, vx, vy, kmh } of every vehicle faster than minKmh,
-- refreshed at most every sampleMs.
function V.refresh(now)
    local s = A.settings.vehicle
    if now - V.refreshedAtMs < (tonumber(s.sampleMs) or 100) then return V.moving end
    V.refreshedAtMs = now
    local moving = {}
    local ok, err = pcall(function()
        local cell = type(getCell) == "function" and getCell() or nil
        local list = cell ~= nil and cell:getVehicles() or nil
        if list == nil or list.size == nil then return end
        local minimum = tonumber(s.minKmh) or 6
        for index = 0, list:size() - 1 do
            local vehicle = list:get(index)
            if vehicle ~= nil then
                local speed = kmh(vehicle)
                if math.abs(speed) >= minimum then
                    local x, y, z = A.xyz(vehicle)
                    if x ~= nil then
                        local sample = V.samples[vehicle]
                        local vx, vy
                        if sample ~= nil and now - sample.atMs > 0 and now - sample.atMs <= 1000 then
                            local dt = (now - sample.atMs) / 1000
                            vx, vy = (x - sample.x) / dt, (y - sample.y) / dt
                        end
                        if vx == nil or vx * vx + vy * vy < 1 then
                            local fx, fy = forward(vehicle)
                            if fx ~= nil then
                                local tiles = speed / 3.6
                                vx, vy = fx * tiles, fy * tiles
                            end
                        end
                        V.samples[vehicle] = { x = x, y = y, atMs = now }
                        if vx ~= nil then
                            moving[#moving + 1] = { vehicle = vehicle, x = x, y = y, z = z or 0,
                                vx = vx, vy = vy, kmh = math.abs(speed) }
                        end
                    end
                end
            end
        end
    end)
    if not ok then
        V.lastError = tostring(err)
        A.fail("vehicles", err)
    end
    V.moving = moving
    return moving
end

-- One vehicle against a point: t = seconds to the closest approach, d = how
-- far the path passes from the point, dist = distance now, (nx, ny) = unit
-- normal to the path pointing to the point's side (the way to step).
function V.approach(row, sx, sy)
    local rx, ry = sx - row.x, sy - row.y
    local v2 = row.vx * row.vx + row.vy * row.vy
    if v2 < 0.25 then return nil end
    local t = (rx * row.vx + ry * row.vy) / v2
    local cx, cy = rx - row.vx * t, ry - row.vy * t
    local d = math.sqrt(cx * cx + cy * cy)
    local speed = math.sqrt(v2)
    local nx, ny = -row.vy / speed, row.vx / speed
    if cx * nx + cy * ny < 0 then nx, ny = -nx, -ny end
    if d < 0.05 and (math.floor(sx) + math.floor(sy)) % 2 == 0 then nx, ny = -nx, -ny end
    return { t = t, d = d, dist = math.sqrt(rx * rx + ry * ry), nx = nx, ny = ny, speed = speed }
end

-- The most urgent vehicle on a collision course with the shell, if any.
function V.threat(shell, now)
    local s = A.settings.vehicle
    local sx, sy, sz = A.xyz(shell)
    if sx == nil then return nil end
    local range = tonumber(s.rangeTiles) or 14
    local lane = tonumber(s.laneTiles) or 2
    local horizon = tonumber(s.horizonS) or 2.2
    local best, bestGeo
    for _, row in ipairs(V.refresh(now)) do
        if math.abs((row.z or 0) - (sz or 0)) < 0.5 then
            local geo = V.approach(row, sx, sy)
            if geo ~= nil and geo.dist <= range and geo.t >= -0.2 and geo.t <= horizon and geo.d <= lane then
                if best == nil or geo.t < bestGeo.t then best, bestGeo = row, geo end
            end
        end
    end
    return best, bestGeo
end

return V
