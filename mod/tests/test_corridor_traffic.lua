-- Tests for corridor_traffic.lua:
-- 1. Hazard zones catalog (wildlife & livestock road crossing zones).
-- 2. African regional corridor traffic archetypes (B-doubles, Quantum minibuses, overland 4x4s).
-- 3. Proximity hazard zone detection and warnings.
-- 4. Traffic density management.

local dir = (arg and arg[0] or ''):match('^(.*)[/\\]') or '.'
local T = dofile(dir .. '/testlib.lua')
package.loaded['beamngEarth/settings'] = { get = function(key) return key == 'otbtLogisticsEnabled' end }

-- Stub dependencies
local storage = {}
function jsonReadFile(path) return storage[path] end
function jsonWriteFile(path, data) storage[path] = data; return true end

local ct = require('beamngEarth/corridor_traffic')

--------------------------------------------------------------------------------
-- 1. Hazard Zones Catalog
--------------------------------------------------------------------------------
do
  local zones = ct.HAZARD_ZONES
  T.check(#zones >= 5, 'contains at least 5 major African wildlife/livestock hazard zones')

  local types = { wildlife = 0, livestock = 0 }
  for _, hz in ipairs(zones) do
    T.check(hz.id ~= nil, 'zone has id')
    T.check(hz.name ~= nil, 'zone has descriptive name')
    T.check(hz.hazard ~= nil, 'zone specifies crossing animal hazard')
    T.check(hz.speedLimitKmh ~= nil and hz.speedLimitKmh <= 80, 'zone defines safe advisory speed limit')
    types[hz.type] = (types[hz.type] or 0) + 1
  end

  T.check(types.wildlife >= 3, 'contains wildlife migration corridors (Kruger, Chobe, Serengeti)')
  T.check(types.livestock >= 2, 'contains rural open range livestock corridors (Karoo, Kalahari)')
end

--------------------------------------------------------------------------------
-- 2. Traffic Archetypes
--------------------------------------------------------------------------------
do
  local archetypes = ct.TRAFFIC_ARCHETYPES
  T.check(#archetypes >= 3, 'contains at least 3 regional vehicle archetypes')

  local models = {}
  for _, a in ipairs(archetypes) do
    T.check(a.name ~= nil, 'archetype has name')
    T.check(a.speedFactor ~= nil, 'archetype defines speed behavior')
    models[a.model] = a
  end

  T.check(models['us_semi'] ~= nil, 'includes heavy commercial b-double interlink hauler')
  T.check(models['van'] ~= nil, 'includes brisk regional commuter minibus taxi')
  T.check(models['roamer'] ~= nil, 'includes safari overland 4x4')
end

--------------------------------------------------------------------------------
-- 3. Proximity Hazard Detection
--------------------------------------------------------------------------------
do
  ct.reset()

  -- Position near Greater Kruger fringe (-24.9900, 31.5900)
  local hz, dist = ct.findNearestHazard(-24.9800, 31.5800)
  T.check(hz ~= nil, 'found nearest hazard zone')
  T.check(hz.id == 'kruger_fringe', 'identified Kruger wildlife corridor')
  T.check(dist < 5000, 'calculated distance accurately within zone (<5km)')

  local uiSt = ct.getUiState(-24.9800, 31.5800)
  T.check(uiSt.activeHazard ~= nil, 'UI state recognizes active hazard zone')
  T.check(uiSt.activeHazard.speedLimitKmh == 60, 'reports 60 km/h advisory speed limit')
end

--------------------------------------------------------------------------------
-- 4. Traffic Density
--------------------------------------------------------------------------------
do
  local d = ct.setDensity(0.80)
  T.check(d == 0.80, 'density set to 80%')

  local ok, res = ct.spawnCorridorTraffic(0.75)
  T.check(ok, 'spawned corridor traffic')
  T.check(res.density == 0.75, 'active traffic density 75%')
end

T.done('test_corridor_traffic')
