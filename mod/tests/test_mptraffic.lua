-- luajit mod/tests/test_mptraffic.lua  (BeamMP traffic directed by the server, mptraffic.lua): the plan for one kind
-- of car (start, stop, trim, refill after REFILL_S short); the cars trimmed (inactive first, then the farthest); the
-- share checked; a session's stock traffic started, trimmed and stopped at the share.
local dir = (arg[0]:match('^(.*)[/\\]') or '.')
local T = dofile(dir .. '/testlib.lua')
local S = dofile(dir .. '/stubs.lua')
local mt = require('beamngEarth/mptraffic')

-- pure: the plan
T.check(mt.plan(0, 0, false, 0, true) == nil, 'plan: no share, nothing running: nothing')
T.check(mt.plan(0, 3, true, 0, true) == 'stop', 'plan: no share: stopped')
T.check(mt.plan(4, 0, false, 0, false) == nil, 'plan: not ready (no road graph yet): waits')
T.check(mt.plan(4, 0, false, 0, true) == 'start', 'plan: ready: started')
T.check(mt.plan(4, 0, true, 0, true) == 'stop', 'plan: on with no cars: stopped (started again next)')
T.check(mt.plan(4, 6, true, 0, true) == 'trim', 'plan: over the share: trimmed')
T.check(mt.plan(4, 4, true, 0, true) == nil, 'plan: at the share: nothing')
T.check(mt.plan(4, 2, true, mt.REFILL_S - 1, true) == nil, 'plan: short for a moment: waits')
T.check(mt.plan(4, 2, true, mt.REFILL_S, true) == 'refill', 'plan: short for REFILL_S: refilled')

-- pure: which cars go
local pick = mt.pickTrim({ [1] = { x = 10, y = 0, active = true }, [2] = { x = 500, y = 0, active = true },
  [3] = { x = 0, y = 0, active = false }, [4] = { x = 200, y = 0, active = true } }, 2, 0, 0)
T.check(pick[1] == 3 and pick[2] == 2 and #pick == 2, 'pickTrim: the inactive one, then the farthest')
T.check(#mt.pickTrim({ [1] = { x = 0, y = 0, active = true } }, 5, 0, 0) == 1, 'pickTrim: no more than there are')

-- the share: checked
mt.onTraffic({ traffic = 'x', parked = 1e9, police = 'yes' })
local s = mt.share()
T.check(s.traffic == 0 and s.parked == mt.MAX_CARS and s.police == false, 'share: bad values made safe')
mt.reset()

-- a session: the stock systems, stubbed
local function car(x)
  local o = S.newObject('BeamNGVehicle')
  o.pos = vec3(x, 0, 0)
  function o:getActive() return true end
  S.objects[o.id] = o
  return o
end
function getObjectByID(id) return S.objects[id] end
be = { getPlayerVehicleID = function() return -1 end }
core_camera = { getPosition = function() return vec3(0, 0, 0) end }
local traffic, tstate, setup = {}, 'off', {}
gameplay_traffic = {
  getState = function() return tstate end,
  getTrafficData = function() return traffic end,
  setupTraffic = function(n, o)
    setup[#setup + 1] = { n = n, police = o and o.police }
    tstate = 'on'
    for i = 1, n do traffic[car(i * 100).id] = {} end
  end,
  deleteVehicles = function()
    for id in pairs(traffic) do S.objects[id] = nil end
    traffic, tstate = {}, 'off'
  end,
  removeTraffic = function(id) traffic[id] = nil end,
}
package.loaded['beamngEarth/navgraph'] = { status = function() return { started = true } end }
package.loaded['beamngEarth/parking'] = { status = function() return { started = false } end }

T.check(not mt.active(), 'not in a session: the player\'s own choice runs the traffic')
mt.onPostJoin()
T.check(mt.active(), 'in a session: the server\'s share does')
mt.update(5)
T.check(#setup == 0, 'no share yet: nothing started')
mt.onTraffic({ traffic = 4, parked = 3, police = true })
mt.update(0.1)
T.check(#setup == 1 and setup[1].n == 4 and setup[1].police == true, 'the share: 4 cars started, police as the server says')
mt.onTraffic({ traffic = 2, parked = 3 })
mt.update(0.1)
local n = 0
for _ in pairs(traffic) do n = n + 1 end
T.check(n == 2 and #setup == 1, 'a smaller share: trimmed to 2, not restarted')
local far = false
for id in pairs(traffic) do if S.objects[id].pos.x > 200 then far = true end end
T.check(not far, 'trimmed: the farthest went')
mt.onTraffic({ traffic = 5, parked = 3 })
for _ = 1, mt.REFILL_S do mt.update(mt.CHECK_S) end
mt.update(mt.CHECK_S)
T.check(#setup == 2 and setup[2].n == 5, 'a larger share: refilled after REFILL_S')
mt.onTraffic({ traffic = 0, parked = 0 })
mt.update(0.1)
T.check(tstate == 'off' and next(traffic) == nil, 'no share: stopped')
mt.reset()
T.check(not mt.active() and mt.share() == nil, 'reset: out of the session')

T.done('test_mptraffic')
