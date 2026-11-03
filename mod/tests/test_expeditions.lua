-- luajit mod/tests/test_expeditions.lua
-- Tests for expeditions.lua:
-- 1. Curated overlanding tours across Southern/Eastern Africa with real checkpoints.
-- 2. Expedition start, sequential checkpoint progression, and milestone discovery.
-- 3. Passport stamps and off-road mileage accumulation.
-- 4. Home Base HQ setting, fast-travel, and default spawn configuration.
-- 5. Vehicle spawner helpers for 4x4 overland rigs and commercial semi trucks.

local dir = (arg and arg[0] or ''):match('^(.*)[/\\]') or '.'
local T = dofile(dir .. '/testlib.lua')
local S = dofile(dir .. '/stubs.lua')

-- Stub JSON and dependencies for test isolation
local storage = {}
function jsonReadFile(path) return storage[path] end
function jsonWriteFile(path, data) storage[path] = data; return true end

local gpsRoute = nil
package.loaded['beamngEarth/gps'] = {
  setDestination = function(lat, lon, name)
    gpsRoute = { lat = lat, lon = lon, name = name }
    return true
  end,
  clear = function() gpsRoute = nil; return true end
}

local teleportTarget = nil
package.loaded['beamngEarth/places'] = {
  distance = function(lat1, lon1, lat2, lon2)
    -- Simple flat-Earth meter distance for tests
    local dx = (lon2 - lon1) * 111000
    local dy = (lat2 - lat1) * 111000
    return math.sqrt(dx * dx + dy * dy)
  end,
  goTo = function(lat, lon, name)
    teleportTarget = { lat = lat, lon = lon, name = name }
    return true
  end
}

local expeditions = require('beamngEarth/expeditions')

--------------------------------------------------------------------------------
-- 1. Curated Tours Catalog Verification
--------------------------------------------------------------------------------
do
  T.check(#expeditions.TOURS >= 5, 'contains at least 5 curated overlanding tours')

  local tourMap = {}
  for _, t in ipairs(expeditions.TOURS) do
    tourMap[t.id] = t
    T.check(#t.checkpoints >= 3, t.name .. ' has at least 3 checkpoints')
    T.check(t.grade >= 1 and t.grade <= 5, t.name .. ' has valid 4x4 trail grade (1-5)')
  end

  T.check(tourMap['sani_pass'] ~= nil, 'Sani Pass Mountain Ascent exists')
  T.check(tourMap['namib_dunes'] ~= nil, 'Namib Desert & Dune 45 Expedition exists')
  T.check(tourMap['okavango_zambezi'] ~= nil, 'Okavango to Victoria Falls exists')
  T.check(tourMap['richtersveld_crawl'] ~= nil, 'Richtersveld Rock Crawl exists')
  T.check(tourMap['chapmans_cape_point'] ~= nil, 'Chapman\'s Peak coastal pass exists')
end

--------------------------------------------------------------------------------
-- 2. Expedition Lifecycle: Transit -> Trailhead -> Checkpoint Progression
--------------------------------------------------------------------------------
do
  expeditions.reset()
  gpsRoute = nil

  -- Plan Sani Pass from Home Base
  local ok, tour = expeditions.startExpedition('sani_pass')
  T.check(ok, 'expedition planned successfully')
  T.check(tour.status == 'transit', 'tour starts in transit mode (must drive to trailhead)')
  T.check(expeditions.getActiveTour() ~= nil, 'active tour set')
  T.check(gpsRoute ~= nil and gpsRoute.name == 'Underberg Valley Trailhead', 'GPS routed to Trailhead')

  -- Simulate arriving at Trailhead (Underberg: -29.7892, 29.4975)
  expeditions.update(-29.7892, 29.4975)
  T.check(expeditions.getActiveTour().atTrailhead == true, 'arrived at trailhead detected')

  -- Begin the expedition trail
  local beginOk, activeTour = expeditions.beginTrail()
  T.check(beginOk and activeTour.status == 'active', 'trail officially begun')
  T.check(expeditions.getCheckpointIndex() == 2, 'checkpoint index advanced to stage 2')
  T.check(gpsRoute ~= nil and gpsRoute.name == 'South Africa Border Post', 'GPS routed to Stage 2 checkpoint')

  -- Reach checkpoint 2 -> advance to checkpoint 3
  local adv2, status2 = expeditions.advanceCheckpoint()
  T.check(adv2 and status2 == 'advanced', 'advanced to checkpoint 3')

  -- Reach checkpoint 3 -> advance to checkpoint 4 (Final Summit)
  local adv3, status3 = expeditions.advanceCheckpoint()
  T.check(adv3 and status3 == 'advanced', 'advanced to summit')

  -- Reach Summit -> Complete Tour!
  local adv4, status4, completedTour = expeditions.advanceCheckpoint()
  T.check(adv4 and status4 == 'completed', 'expedition successfully completed')
  T.check(expeditions.getActiveTour() == nil, 'active tour cleared on completion')

  -- Check passport stamp
  local passport = expeditions.getPassport()
  T.check(passport.stamps['sani_pass'] ~= nil, 'Sani Pass passport stamp awarded')
  T.check(passport.totalOffroadKm >= 45, 'off-road mileage credited to passport')
  T.check(passport.milestonesDiscovered >= 3, 'milestones recorded in passport')
end

--------------------------------------------------------------------------------
-- 3. Home Base Setting & Fast-Travel
--------------------------------------------------------------------------------
do
  teleportTarget = nil

  -- Default Home Base
  local hb = expeditions.getHomeBase()
  T.check(hb ~= nil and hb.name:find('Johannesburg'), 'default Home Base is Johannesburg HQ')

  -- Fast-travel Home
  local travelOk = expeditions.teleportToHomeBase()
  T.check(travelOk, 'teleportToHomeBase initiated')
  T.check(teleportTarget ~= nil and teleportTarget.name == hb.name, 'teleported to Home Base coordinates')

  -- Relocate Home Base using major city preset (Cape Town)
  local cityOk, cptBase = expeditions.setHomeBaseByCity('cpt')
  T.check(cityOk, 'Home Base set via city preset')
  T.check(cptBase.name:find('Cape Town'), 'Home Base set to Cape Town')
  T.check(cptBase.kind == 'city_base', 'kind recorded as city_base')

  -- Relocate Home Base using custom street address
  local addrOk, addrBase = expeditions.setHomeBase('My Cape Town Villa', -33.9312, 18.4110, 'custom_address', '42 Kloof Street, Cape Town')
  T.check(addrOk, 'Home Base set via custom street address')
  T.check(addrBase.address == '42 Kloof Street, Cape Town', 'street address recorded')
  T.check(addrBase.kind == 'custom_address', 'kind recorded as custom_address')

  -- Fast-travel to custom street address Base
  teleportTarget = nil
  expeditions.teleportToHomeBase()
  T.check(teleportTarget ~= nil and teleportTarget.name == 'My Cape Town Villa', 'teleported to custom address Base')
end

--------------------------------------------------------------------------------
-- 4. Vehicle Rig Spawning Stubs
--------------------------------------------------------------------------------
do
  local spawnedModel = nil
  core_vehicles = {
    spawnNewVehicle = function(model, opt)
      spawnedModel = model
      return { id = 999, model = model }
    end
  }

  -- Spawn 4x4 Overland Rig
  local rigOk = expeditions.spawnOverlandRig()
  T.check(rigOk, 'spawnOverlandRig succeeded')
  T.check(spawnedModel == 'roamer', 'spawned Gavril Roamer 4x4 cruiser')

  -- Spawn Heavy Semi Truck
  local truckOk = expeditions.spawnSemiTruck()
  T.check(truckOk, 'spawnSemiTruck succeeded')
  T.check(spawnedModel == 'us_semi', 'spawned Gavril T-Series commercial semi')
end

--------------------------------------------------------------------------------
-- 5. Remote Expedition Sync (BeamMP Convoy)
--------------------------------------------------------------------------------
do
  expeditions.reset()

  -- Remote expedition_start
  expeditions.onRemoteExpedition({
    type = 'expedition_start',
    expedition = {
      id = 'namib_dunes',
      name = 'Namib Desert & Dune 45 Expedition',
      checkpoints = {
        { name = 'Solitaire Desert Outpost', lat = -23.8940, lon = 16.0050 },
        { name = 'Sesriem Canyon Gateway', lat = -24.5160, lon = 15.7990 },
        { name = 'Dune 45 Red Star Dune', lat = -24.7348, lon = 15.4699 }
      },
      status = 'transit'
    },
    playerName = 'LeaderRig'
  })
  local active = expeditions.getActiveTour()
  T.check(active ~= nil and active.id == 'namib_dunes', 'remote expedition_start synced active tour')

  -- Remote expedition_stage
  expeditions.onRemoteExpedition({
    type = 'expedition_stage',
    expeditionId = 'namib_dunes',
    stage = 2,
    status = 'active',
    playerName = 'LeaderRig'
  })
  local uiSt = expeditions.getUiState(0, 0)
  T.check(uiSt.checkpointIndex == 2, 'remote stage advanced to checkpoint 2')

  -- Remote expedition_complete
  expeditions.onRemoteExpedition({
    type = 'expedition_complete',
    expeditionId = 'namib_dunes',
    stamp = { completedAt = 123456789, durationSeconds = 1200 },
    playerName = 'LeaderRig'
  })
  T.check(expeditions.getActiveTour() == nil, 'remote complete cleared active tour')
  T.check(expeditions.getPassport().stamps['namib_dunes'] ~= nil, 'remote complete awarded passport stamp')
end

T.done('test_expeditions')
