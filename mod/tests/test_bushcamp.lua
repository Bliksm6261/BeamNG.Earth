-- Tests for bushcamp.lua:
-- 1. Bush camp deployment criteria (stationary vehicle check, coordinate recording).
-- 2. Camp pack-up and stowage.
-- 3. Campfire resting (driver fatigue reset, TimeOfDay advancement).
-- 4. "Well-Rested Bush Explorer" buff activation, payout bonus flag, and expiration.

local dir = (arg and arg[0] or ''):match('^(.*)[/\\]') or '.'
local T = dofile(dir .. '/testlib.lua')
package.loaded['beamngEarth/settings'] = { get = function(key) return key == 'otbtLogisticsEnabled' end }

-- Stub dependencies
local storage = {}
function jsonReadFile(path) return storage[path] end
function jsonWriteFile(path, data) storage[path] = data; return true end

package.loaded['beamngEarth/gps'] = { setDestination = function() return true end }
package.loaded['beamngEarth/freight'] = {
  restDriver = function(h) return true, h end,
  getCompany = function() return { name = 'Test Co', vault = 10000, reputation = 100 } end
}

local bushcamp = require('beamngEarth/bushcamp')

--------------------------------------------------------------------------------
-- 1. Camp Deployment & Stationary Validation
--------------------------------------------------------------------------------
do
  bushcamp.reset()

  -- Vehicle moving at 5 m/s (18 km/h) cannot deploy camp
  local movingVeh = {
    getVelocity = function() return { length = function() return 5.0 end } end
  }
  local badOk, err = bushcamp.deployCamp(-24.5, 28.5, movingVeh)
  T.check(badOk == false, 'rejected camp deployment while vehicle moving')

  -- Stationary vehicle (<0.8 m/s) succeeds
  local stoppedVeh = {
    getVelocity = function() return { length = function() return 0.0 end } end,
    queueLuaCommand = function() return true end
  }
  local ok, st = bushcamp.deployCamp(-24.5000, 28.5000, stoppedVeh)
  T.check(ok, 'camp deployed successfully while stopped')
  T.check(st.deployed == true, 'camp state marked deployed')
  T.check(st.lat == -24.5000 and st.lon == 28.5000, 'recorded camp coordinates')
  T.check(st.amenities.rooftopTent == true, 'rooftop tent amenity verified')
  T.check(st.amenities.campfire == true, 'campfire amenity verified')

  -- Cannot deploy twice
  local doubleOk, doubleErr = bushcamp.deployCamp(-24.5, 28.5, stoppedVeh)
  T.check(doubleOk == false, 'cannot deploy camp when already active')
end

--------------------------------------------------------------------------------
-- 2. Campfire Resting & Explorer Buff
--------------------------------------------------------------------------------
do
  -- Rest at camp for 8 hours
  local restOk, res = bushcamp.restAtCamp(8)
  T.check(restOk, 'rested by campfire for 8 hours')
  T.check(res.hours == 8, '8 hours recorded')
  T.check(bushcamp.hasExplorerBuff() == true, 'granted Well-Rested Bush Explorer buff')

  local uiSt = bushcamp.getUiState(-24.5, 28.5, nil)
  T.check(uiSt.hasBuff == true, 'UI state indicates active explorer buff')
  T.check(uiSt.buffMinutesLeft > 100, 'buff has ~120 minutes remaining')
end

--------------------------------------------------------------------------------
-- 3. Camp Pack-Up & Stowage
--------------------------------------------------------------------------------
do
  local stoppedVeh = {
    getVelocity = function() return { length = function() return 0.0 end } end,
    queueLuaCommand = function() return true end
  }

  local packOk = bushcamp.packCamp(stoppedVeh)
  T.check(packOk, 'packed camp successfully')

  local uiSt = bushcamp.getUiState(-24.5, 28.5, stoppedVeh)
  T.check(uiSt.deployed == false, 'camp is no longer deployed')
  T.check(uiSt.canDeploy == true, 'can deploy again when ready')
end

-- Use real freight to verify camp advances BeamNG time once, across midnight.
do
  local oldFreight = package.loaded['beamngEarth/freight']
  package.loaded['beamngEarth/freight'] = nil
  local realFreight = require('beamngEarth/freight')
  beamngEarth_freight = realFreight
  local tod = {time=0.25} -- 18:00
  local oldTree = scenetree
  scenetree = {findClassObjects=function() return {'tod'} end, findObject=function() return tod end}
  bushcamp.reset()
  bushcamp.deployCamp(-26, 28, nil)
  T.check(bushcamp.restAtCamp(8), 'camp rest with real freight succeeds')
  T.check(math.abs(tod.time - (0.25 + 8/24) % 1) < 1e-9, 'camp advances exactly eight hours from dusk')
  tod.time = 0.75 -- 06:00
  realFreight.restDriver(6)
  T.check(math.abs(tod.time) < 1e-9, 'driver rest advances dawn to noon')
  scenetree = oldTree
  beamngEarth_freight = nil
  package.loaded['beamngEarth/freight'] = oldFreight
end

T.done('test_bushcamp')
