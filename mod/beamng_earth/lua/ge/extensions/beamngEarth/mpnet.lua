-- Smaller and fewer BeamMP packets for the AI traffic our game drives (mptraffic.lua), and smaller position packets for
-- all our cars (the user, 2026-10-24: "make that transaction / packet as small as possible to keep latency as low as
-- possible"). BeamMP sends every car's position 50 times a second ('Zp', positionVE / MPUpdatesGE: positionTickrate
-- 0.020) as JSON with full doubles, and the server sends each one on to every other player on it; a player's inputs go
-- as changes ('Vi', up to 30 a second). Electrics and powertrain are already sent only when they change: left as
-- they are. Wrapped here, at run time, like mpanchor.lua's positionGE.handle (BeamMP's files are not changed):
--   - positionGE.sendVehiclePosRot (every own car): the packet written again with its numbers rounded (positions and
--     velocities to 1 cm, the rotation to 1e-4, times to 1 ms), about half the bytes; a packet with anything this does
--     not know goes as it was;
--   - and for our traffic and parked cars, the rate by how near the nearest other player is (rateFor): POS_HZ_NEAR
--     within NEAR_M, POS_HZ_MID within MID_M, POS_HZ_FAR beyond, POS_HZ_STILL for a car standing still. A position
--     packet carries the whole state, so the ones in between are simply not sent; BeamMP's receiver predicts between
--     them (positionVE: from the velocity, for up to 0.1 s);
--   - MPInputsGE.sendInputs for our traffic: the changes merged and sent at most INPUTS_HZ (a change is never lost:
--     the latest value of each input goes out with the next send).
-- The other players' places come from the plugin's anchors (mpsession.others), every POSE_S. Our update runs with
-- mpsession's, which stops while the world server is not connected; the wraps then pass everything through as BeamMP
-- would (no thinning without our clock: STALE_S).
local M = {}

M.NEAR_M = 300
M.MID_M = 1000
M.POS_HZ_NEAR = 20          -- (BeamMP's receiver stops predicting 0.1 s after a packet: faster than 10 a second)
M.POS_HZ_MID = 5
M.POS_HZ_FAR = 1
M.POS_HZ_STILL = 1
M.STILL_MS = 0.3
M.INPUTS_HZ = 10
M.NEAREST_S = 0.5           -- each traffic car's nearest other player found again this often
M.STALE_S = 0.5             -- our update not run for this long (real time): the wraps thin nothing

local installed = { pos = false, inputs = false }
local clock = 0
local updatedAt = nil       -- realTime() of our last update

-- Seconds of real time (BeamMP's own high-precision timer when there is one; tests: M.realTime replaced).
local timer = nil
function M.realTime()
  if not timer then
    local mk = rawget(_G, 'HighPerfTimer') or rawget(_G, 'hptimer')
    timer = mk and mk() or false
  end
  if timer then return timer:stop() / 1000 end
  return os.clock()
end

-- Is our update running (the thinning is on)?
local function live() return updatedAt ~= nil and M.realTime() - updatedAt < M.STALE_S end
local lastPos = {}          -- own game vehicle id -> clock of its last position packet sent
local lastInputs = {}       -- own game vehicle id -> clock of its last inputs packet sent
local pendingInputs = {}    -- own game vehicle id -> { input -> value } not sent yet
local nearest = {}          -- own traffic car id -> metres to the nearest other player
local nearestIn = 0
local stats = { posIn = 0, posOut = 0, bytesIn = 0, bytesOut = 0, inputsIn = 0, inputsOut = 0 }

-- Pure: position packets a second for a car: d metres from the nearest other player (nil: none), speed m/s.
function M.rateFor(d, speed)
  if speed and speed < M.STILL_MS then return M.POS_HZ_STILL end
  if d and d <= M.NEAR_M then return M.POS_HZ_NEAR end
  if d and d <= M.MID_M then return M.POS_HZ_MID end
  return M.POS_HZ_FAR
end

-- Pure: a number as short as it can be at `places` decimals ("-0" as "0").
function M.num(v, places)
  local s = string.format('%.' .. places .. 'f', v)
  if places > 0 then s = s:gsub('0+$', ''):gsub('%.$', '') end
  if s == '-0' then s = '0' end
  return s
end

local PLACES = { pos = 2, vel = 2, rot = 4, rvel = 3, tim = 3, ping = 3 }
local ORDER = { 'pos', 'vel', 'rot', 'rvel', 'tim', 'ping' }
local LEN = { pos = 3, vel = 3, rot = 4, rvel = 3 }

-- Pure: a decoded position packet written again with rounded numbers; nil when it has a field or value this does
-- not know (it then goes as it was).
function M.compact(d)
  if type(d) ~= 'table' then return nil end
  for k in pairs(d) do
    if not PLACES[k] then return nil end
  end
  local parts = {}
  for _, k in ipairs(ORDER) do
    local v = d[k]
    if v ~= nil then
      local p = PLACES[k]
      if LEN[k] then
        if type(v) ~= 'table' or #v ~= LEN[k] then return nil end
        local xs = {}
        for i = 1, LEN[k] do
          local x = tonumber(v[i])
          if not x or x ~= x or x == math.huge or x == -math.huge then return nil end
          xs[i] = M.num(x, p)
        end
        parts[#parts + 1] = '"' .. k .. '":[' .. table.concat(xs, ',') .. ']'
      else
        local x = tonumber(v)
        if not x or x ~= x or x == math.huge or x == -math.huge then return nil end
        parts[#parts + 1] = '"' .. k .. '":' .. M.num(x, p)
      end
    end
  end
  return '{' .. table.concat(parts, ',') .. '}'
end

local function isTraffic(gid) return require('beamngEarth/mptraffic').isOurs(gid) end

local function speedOf(d)
  local v = type(d) == 'table' and type(d.vel) == 'table' and d.vel
  local x, y, z = v and tonumber(v[1]), v and tonumber(v[2]), v and tonumber(v[3])
  return x and y and z and math.sqrt(x * x + y * y + z * z) or nil
end

-- Wraps positionGE.sendVehiclePosRot(data, gameVehicleID) (positionVE calls it by name through queueGameEngineLua).
function M.wrapPos(original)
  return function(data, gid)
    stats.posIn = stats.posIn + 1
    stats.bytesIn = stats.bytesIn + #tostring(data)
    local decode = rawget(_G, 'jsonDecode')
    local ok, d = false, nil
    if decode then ok, d = pcall(decode, data) end
    if not ok then d = nil end
    if isTraffic(gid) and live() then
      local hz = M.rateFor(nearest[gid], speedOf(d))
      if lastPos[gid] and clock - lastPos[gid] < 1 / hz - 1e-6 then return end
      lastPos[gid] = clock
    end
    local out = d and M.compact(d) or data
    stats.posOut = stats.posOut + 1
    stats.bytesOut = stats.bytesOut + #out
    return original(out, gid)
  end
end

local sendInputsRef = nil

-- Wraps MPInputsGE.sendInputs(data, gameVehicleID): our traffic's changes merged, sent at most INPUTS_HZ.
function M.wrapInputs(original)
  sendInputsRef = original
  return function(data, gid)
    if not isTraffic(gid) then return original(data, gid) end
    stats.inputsIn = stats.inputsIn + 1
    local decode = rawget(_G, 'jsonDecode')
    local ok, d = false, nil
    if decode then ok, d = pcall(decode, data) end
    if not ok or type(d) ~= 'table' then return original(data, gid) end
    local p = pendingInputs[gid] or {}
    for k, v in pairs(d) do p[k] = v end
    pendingInputs[gid] = p
    if not live() then              -- (no flush coming: sent now, with anything held)
      pendingInputs[gid] = {}
      return original(M.inputsJson(p), gid)
    end
  end
end

-- Pure: the merged inputs as BeamMP's JSON object { name: value }, keys sorted.
function M.inputsJson(p)
  local keys = {}
  for k in pairs(p) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, k in ipairs(keys) do
    local v = p[k]
    local s = type(v) == 'number' and M.num(v, 4) or (type(v) == 'boolean' and tostring(v)) or nil
    if not s then s = string.format('%q', tostring(v)) end
    parts[#parts + 1] = string.format('%q', tostring(k)) .. ':' .. s
  end
  return '{' .. table.concat(parts, ',') .. '}'
end

local function flushInputs()
  if not sendInputsRef then return end
  for gid, p in pairs(pendingInputs) do
    if next(p) and (not lastInputs[gid] or clock - lastInputs[gid] >= 1 / M.INPUTS_HZ - 1e-6) then
      lastInputs[gid] = clock
      pendingInputs[gid] = {}
      stats.inputsOut = stats.inputsOut + 1
      pcall(sendInputsRef, M.inputsJson(p), gid)
    end
  end
end

-- The hooks, once BeamMP's modules are there (a no-op after, and in single player).
function M.install()
  local pg = rawget(_G, 'positionGE')
  if not installed.pos and pg and type(pg.sendVehiclePosRot) == 'function' then
    pg.sendVehiclePosRot = M.wrapPos(pg.sendVehiclePosRot)
    installed.pos = true
    log('I', 'beamngEarth', 'mpnet: position packets made smaller')
  end
  local mi = rawget(_G, 'MPInputsGE')
  if not installed.inputs and mi and type(mi.sendInputs) == 'function' then
    mi.sendInputs = M.wrapInputs(mi.sendInputs)
    installed.inputs = true
  end
end

local function objectOf(id)
  local get = rawget(_G, 'getObjectByID')
  return get and get(id) or nil
end

-- Each frame in a session (mpsession.update): anchor (our frame's geodesy anchor), others ({ { lat, lon } }:
-- mpsession.others).
function M.update(dt, anchor, others)
  M.install()
  updatedAt = M.realTime()
  clock = clock + (dt or 0)
  nearestIn = nearestIn - (dt or 0)
  if nearestIn <= 0 and anchor and anchor.geodeticToEnu then
    nearestIn = M.NEAREST_S
    local pts = {}
    for _, o in ipairs(others or {}) do
      local x, y = anchor:geodeticToEnu(o.lat, o.lon, 0)
      pts[#pts + 1] = { x, y }
    end
    local now = {}
    for _, id in ipairs(require('beamngEarth/mptraffic').ours()) do
      local obj = objectOf(id)
      if obj then
        local p, best = obj:getPosition(), nil
        for _, q in ipairs(pts) do
          local d = math.sqrt((p.x - q[1]) ^ 2 + (p.y - q[2]) ^ 2)
          if not best or d < best then best = d end
        end
        now[id] = best
      end
    end
    nearest = now
  end
  flushInputs()
end

function M.status()
  local s = {}
  for k, v in pairs(stats) do s[k] = v end
  s.installed = installed.pos
  return s
end

function M.reset()
  clock, lastPos, lastInputs, pendingInputs, nearest, nearestIn, updatedAt = 0, {}, {}, {}, {}, 0, nil
  stats = { posIn = 0, posOut = 0, bytesIn = 0, bytesOut = 0, inputsIn = 0, inputsOut = 0 }
end

return M
