-- Bounded, local crowd retreat; preserves A-Life's combat and order policy.
require "ALifeReactive/ALR_RetreatSafety"
local A = ALifeReactive
local R = { windowMs = -1, searches = 0 }
A.Retreat = R

local function candidate(out, origin, dx, dy, distance, angle, kind)
    local cs, sn = math.cos(angle), math.sin(angle)
    out[#out + 1] = { x = origin.x + (dx * cs - dy * sn) * distance,
        y = origin.y + (dy * cs + dx * sn) * distance, z = origin.z, kind = kind or "crowd" }
end

function R.candidates(origin, crowd, ally, distance)
    local dx, dy = origin.x - crowd.cx, origin.y - crowd.cy
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.1 then dx, dy, length = 1, 0, 1 end
    dx, dy = dx / length, dy / length
    local out = {}
    for _, angle in ipairs({0, math.pi / 4, -math.pi / 4, math.pi / 2, -math.pi / 2, math.pi}) do
        candidate(out, origin, dx, dy, distance, angle)
    end
    for _, angle in ipairs({0, math.pi / 2, -math.pi / 2, math.pi}) do
        candidate(out, origin, dx, dy, math.max(1, distance / 2), angle)
    end
    if ally ~= nil and math.abs((ally.z or origin.z) - origin.z) < 0.4 then
        local ax, ay = ally.x - origin.x, ally.y - origin.y
        local away = math.sqrt(ax * ax + ay * ay)
        if away > 2.5 then
            local step = math.min(distance, away - 1.5)
            candidate(out, origin, ax / away, ay / away, step, 0, "regroup")
        end
    end
    return out
end

function R.choose(actor, shell, crowd, ally, now, stepTiles)
    local x, y, z = A.xyz(shell)
    if x == nil or type(crowd) ~= "table" then return nil, "no_position" end
    now = tonumber(now) or A.now()
    -- Global budget, not per NPC: a busy scene cannot multiply route scans
    -- without bound. Rejected actors can retry at the existing crowd cadence.
    if now < R.windowMs or now - R.windowMs >= 250 then R.windowMs, R.searches = now, 0 end
    if R.searches >= 4 then return nil, "budget" end
    R.searches = R.searches + 1
    A.metrics.safeRetreatChecks = A.metrics.safeRetreatChecks + 1
    local origin = { x = x, y = y, z = z }
    local distance = math.max(2, math.min(12, tonumber(stepTiles) or tonumber(A.settings.crowd.fallbackTiles) or 8))
    local safety = A.RetreatSafety
    local rows = safety.threats(shell, origin, now, distance + 6)
    if rows == nil or #rows == 0 then return nil, "unknown_threats" end
    local pressure, nearest = safety.pressure(origin, rows)
    local best, bestScore
    for _, point in ipairs(R.candidates(origin, crowd, ally, distance)) do
        local score = safety.rank(origin, point, rows, pressure, nearest)
        if score ~= nil then
            -- An ally helps break near ties, never cancels collision/danger
            -- rejection. Path safety is checked before accepting a candidate.
            if point.kind == "regroup" then score = score - 0.15 end
            if (bestScore == nil or score < bestScore) and safety.route(shell, origin, point) then
                best, bestScore = point, score
            end
        end
    end
    if best == nil then
        A.metrics.safeRetreatRefused = A.metrics.safeRetreatRefused + 1
        return nil, "no_safe_route"
    end
    return { x = best.x, y = best.y, z = best.z }, best.kind
end

return R
