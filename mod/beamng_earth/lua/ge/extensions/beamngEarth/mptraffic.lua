-- BeamMP traffic directed by the server (the user, 2026-10-24: the server as the source of the traffic). A BeamMP
-- server has no physics, so the players' games drive the AI cars: the plugin (beammp/Server/BeamNGEarth/main.lua)
-- splits each area's moving and parked cars between the players in it and sends each player their share,
-- bngeTraffic { traffic, parked, police }; BeamMP sends every car a game spawns to the others as that player's, so
-- everyone in the area sees the same cars, none twice. In a session this module, not the player's level-start choice
-- (navgraph.choice), runs the stock traffic (gameplay_traffic) and parked cars (gameplay_parking) at that share:
--   - started once the road graph (navgraph.lua) or the parking spots (parking.lua) are in;
--   - a smaller share: the cars over it removed, the inactive (pooled) ones first, then the farthest from the camera
--     (BeamMP removes them for the others);
--   - a larger share (a player near left, or drove away): stock traffic cannot add cars to a running group, so the
--     cars are started again at the new share once it has been short for REFILL_S;
--   - none: stopped. A player who starts traffic from the radial menu is brought back to the share.
-- Every engine call here is an assumption until a two-player test in the game.
local M = {}

M.CHECK_S = 1
M.REFILL_S = 20
M.MAX_CARS = 64             -- a share larger than this is not believed

local inSession = false     -- joined a BeamMP server (onPostJoin) and not left
local share = nil           -- { traffic, parked, police }: the plugin's latest bngeTraffic
local shortFor = { traffic = 0, parked = 0 }
local checkIn = 0
local stats = { starts = 0, stops = 0, trims = 0, refills = 0 }
local own = { traffic = {}, parked = {} }  -- kind -> { id = true }: our cars of it at the last check (mpnet.lua)

function M.onPostJoin() inSession = true end

-- In a BeamMP session: the server's share runs the traffic (navgraph.lua and parking.lua start none themselves).
function M.active() return inSession end

function M.share() return share end

local function count(n)
  n = tonumber(n)
  if not n or n ~= n then return 0 end
  return math.max(0, math.min(M.MAX_CARS, math.floor(n)))
end

-- The plugin's bngeTraffic, decoded.
function M.onTraffic(d)
  if type(d) ~= 'table' then return end
  share = { traffic = count(d.traffic), parked = count(d.parked), police = d.police == true }
  checkIn = 0
  if log then
    log('I', 'beamngEarth', string.format('BeamMP: the server gives us %d traffic and %d parked car(s)', share.traffic,
      share.parked))
  end
end

-- Pure: what to do with one kind of car. target: the share; have: the cars running; running: the stock system is on;
-- short: seconds the share has been short; ready: the system may start (the graph or the spots are in).
-- -> 'start' | 'stop' | 'trim' | 'refill' | nil
function M.plan(target, have, running, short, ready)
  if target <= 0 then return (running or have > 0) and 'stop' or nil end
  if running and have == 0 then return 'stop' end           -- (on with no cars: started again from off)
  if not running then return ready and 'start' or nil end
  if have > target then return 'trim' end
  if have < target and short >= M.REFILL_S then return 'refill' end
  return nil
end

-- Pure: the n cars to remove of cars { id -> { x, y, active } }: the inactive ones first, then the farthest from
-- (x, y); ties to the lower id. -> { id, ... }
function M.pickTrim(cars, n, x, y)
  local list = {}
  for id, c in pairs(cars) do
    list[#list + 1] = { id = id, off = not c.active, d = ((c.x or 0) - (x or 0)) ^ 2 + ((c.y or 0) - (y or 0)) ^ 2 }
  end
  table.sort(list, function(a, b)
    if a.off ~= b.off then return a.off end
    if a.d ~= b.d then return a.d > b.d end
    return a.id < b.id
  end)
  local out = {}
  for i = 1, math.min(n, #list) do out[i] = list[i].id end
  return out
end

local function obj(id)
  local get = rawget(_G, 'getObjectByID')
  return get and get(id) or (be and be.getObjectByID and be:getObjectByID(id)) or nil
end

local function playerId() return be and be.getPlayerVehicleID and be:getPlayerVehicleID(0) or -1 end

-- Our cars of a kind { id -> { x, y, active } }.
local function carsOf(ids)
  local out, me = {}, playerId()
  for _, id in ipairs(ids) do
    local o = id ~= me and obj(id)
    if o then
      local p = o:getPosition()
      out[id] = { x = p.x, y = p.y, active = not o.getActive or o:getActive() }
    end
  end
  return out
end

-- The two kinds: the stock system's state and calls.
local kinds = {
  traffic = {
    system = function() return rawget(_G, 'gameplay_traffic') end,
    ids = function(gt)
      local out = {}
      local ok, data = pcall(gt.getTrafficData)
      for id in pairs(ok and type(data) == 'table' and data or {}) do out[#out + 1] = id end
      return out
    end,
    running = function(gt) return gt.getState() == 'on' end,
    busy = function(gt) local s = gt.getState(); return s == 'spawning' or s == 'loading' end,
    ready = function() return require('beamngEarth/navgraph').status().started == true end,
    start = function(gt, s) return gt.setupTraffic(s.traffic, { police = s.police }) end,
    stop = function(gt) return gt.deleteVehicles() end,
    remove = function(gt, id) if gt.removeTraffic then gt.removeTraffic(id) end end,
  },
  parked = {
    system = function() return rawget(_G, 'gameplay_parking') end,
    ids = function(gp)
      local ok, list = pcall(gp.getParkedCarsList)
      local out = {}
      for k, v in pairs(ok and type(list) == 'table' and list or {}) do
        out[#out + 1] = type(v) == 'number' and v or k
      end
      return out
    end,
    running = function(gp) return gp.getState() and true or false end,
    busy = function() return false end,
    ready = function() return require('beamngEarth/parking').status().started == true end,
    start = function(gp, s)
      local cp = core_camera and core_camera.getPosition()
      return gp.setupVehicles(s.parked, cp and { pos = cp } or nil)
    end,
    stop = function(gp) return gp.deleteVehicles() end,
    remove = function() end,
  },
}

local function step(kind, target, dt)
  local k = kinds[kind]
  local sys = k.system()
  if not sys or k.busy(sys) then return end
  local cars = carsOf(k.ids(sys))
  local have = 0
  own[kind] = {}
  for id in pairs(cars) do have = have + 1; own[kind][id] = true end
  shortFor[kind] = have < target and shortFor[kind] + dt or 0
  local what = M.plan(target, have, k.running(sys), shortFor[kind], k.ready())
  if not what then return end
  local ok, err = true, nil
  if what == 'start' then
    ok, err = pcall(k.start, sys, share)
    stats.starts = stats.starts + 1
  elseif what == 'stop' or what == 'refill' then
    ok, err = pcall(k.stop, sys)
    shortFor[kind] = 0
    if what == 'refill' then stats.refills = stats.refills + 1 else stats.stops = stats.stops + 1 end
  else
    local cp = core_camera and core_camera.getPosition()
    for _, id in ipairs(M.pickTrim(cars, have - target, cp and cp.x, cp and cp.y)) do
      pcall(k.remove, sys, id)
      local o = obj(id)
      if o then o:delete() end
      stats.trims = stats.trims + 1
    end
  end
  if not ok then log('W', 'beamngEarth', string.format('BeamMP traffic: %s %s: %s', what, kind, tostring(err))) end
  if what ~= 'trim' then
    log('I', 'beamngEarth', string.format('BeamMP traffic: %s %s (%d of %d)', what, kind, have, target))
  end
end

-- Each frame in a session (mpsession.update).
function M.update(dt)
  if not inSession or not share then return end
  checkIn = checkIn - (dt or 0)
  if checkIn > 0 then return end
  checkIn = M.CHECK_S
  for _, kind in ipairs({ 'traffic', 'parked' }) do
    local ok, err = pcall(step, kind, share[kind], M.CHECK_S)
    if not ok then log('W', 'beamngEarth', 'BeamMP traffic: ' .. tostring(err)) end
  end
end

-- Is the game vehicle id one of the traffic or parked cars our game runs for the server (at the last check)?
function M.isOurs(id) return own.traffic[id] == true or own.parked[id] == true end

-- Our traffic and parked cars' ids (at the last check).
function M.ours()
  local out = {}
  for _, kind in ipairs({ 'traffic', 'parked' }) do
    for id in pairs(own[kind]) do out[#out + 1] = id end
  end
  table.sort(out)
  return out
end

function M.status()
  return { active = inSession, share = share, starts = stats.starts, stops = stats.stops, trims = stats.trims,
           refills = stats.refills }
end

-- The session's end: the player's own choice again next time.
function M.reset()
  inSession, share, checkIn = false, nil, 0
  own = { traffic = {}, parked = {} }
  shortFor = { traffic = 0, parked = 0 }
  stats = { starts = 0, stops = 0, trims = 0, refills = 0 }
end

return M
