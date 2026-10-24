-- luajit mod/tests/test_mpnet.lua  (smaller BeamMP packets, mpnet.lua): the position rate by the nearest other
-- player; position packets written again with rounded numbers (an unknown field: as they were); our traffic's
-- positions thinned out, other own cars' only rounded; our traffic's inputs merged and sent at most INPUTS_HZ.
local dir = (arg[0]:match('^(.*)[/\\]') or '.')
local T = dofile(dir .. '/testlib.lua')
local S = dofile(dir .. '/stubs.lua')
local net = require('beamngEarth/mpnet')
local real = 0
net.realTime = function() return real end

-- pure: the rate
T.check(net.rateFor(100, 15) == net.POS_HZ_NEAR, 'rate: a player near: the full rate')
T.check(net.rateFor(600, 15) == net.POS_HZ_MID, 'rate: a player within MID_M')
T.check(net.rateFor(5000, 15) == net.POS_HZ_FAR and net.rateFor(nil, 15) == net.POS_HZ_FAR, 'rate: nobody near')
T.check(net.rateFor(10, 0.1) == net.POS_HZ_STILL, 'rate: standing still')

-- pure: numbers and packets
T.check(net.num(1234.5678, 2) == '1234.57' and net.num(2.5, 2) == '2.5' and net.num(3.0, 2) == '3', 'num: short')
T.check(net.num(-0.00001, 2) == '0', 'num: no "-0"')
local d = { pos = { 1234.56789012345, -2345.67890123456, 123.456789012345 },
  vel = { 12.3456789012345, -0.00012345678, 0.987654321098765 },
  rot = { 0.0123456789012345, -0.00987654321098, 0.707106781186547, 0.707000000000001 },
  rvel = { 0.00123456789, -0.0234567890123, 0.345678901234 }, tim = 123.456789012345, ping = 0.0345678901234 }
local c = net.compact(d)
T.check(c == '{"pos":[1234.57,-2345.68,123.46],"vel":[12.35,0,0.99],"rot":[0.0123,-0.0099,0.7071,0.707],'
  .. '"rvel":[0.001,-0.023,0.346],"tim":123.457,"ping":0.035}', 'compact: rounded: ' .. tostring(c))
local function full(t)            -- (a JSON writer with full doubles, as BeamMP's packets look before)
  local parts = {}
  for _, k in ipairs({ 'pos', 'vel', 'rot', 'rvel', 'tim', 'ping' }) do
    local v = t[k]
    if type(v) == 'table' then
      local xs = {}
      for i, x in ipairs(v) do xs[i] = string.format('%.17g', x) end
      parts[#parts + 1] = '"' .. k .. '":[' .. table.concat(xs, ',') .. ']'
    else
      parts[#parts + 1] = '"' .. k .. '":' .. string.format('%.17g', v)
    end
  end
  return '{' .. table.concat(parts, ',') .. '}'
end
local before = full(d)
print(string.format('  position packet: %d bytes with full doubles, %d rounded', #before, #c))
T.check(#c < #before * 0.55, 'compact: under 55% of the full-double packet')
T.check(net.compact({ pos = { 1, 2, 3 }, extra = 1 }) == nil, 'compact: an unknown field: left as it was')
T.check(net.compact({ pos = { 1, 2 } }) == nil and net.compact({ tim = 0 / 0 }) == nil, 'compact: bad values: left')

-- the wraps
local packets = {}
function jsonDecode(s) return s == before and d or (s:sub(1, 1) == '{' and s:find('"t"') and { t = 0.5, s = -0.1 }
  or s:find('"b"') and { b = 1 } or s:find('0.3') and { s = 0.3 } or s:find('"s"') and { s = 0.2 } or nil) end
local ours = { [7] = true }
package.loaded['beamngEarth/mptraffic'] = { isOurs = function(id) return ours[id] == true end,
  ours = function() return { 7 } end }
local pos = net.wrapPos(function(data, gid) packets[#packets + 1] = { data = data, gid = gid } end)
pos(before, 3)
T.check(#packets == 1 and packets[1].data == c, 'positions: our own car: every packet, rounded')
pos(before, 3)
T.check(#packets == 2, 'positions: our own car: not thinned')
pos('not json', 3)
T.check(packets[3].data == 'not json', 'positions: a packet that does not decode: as it was')
packets = {}
pos(before, 7)
pos(before, 7)
T.check(#packets == 2, 'positions: our update not running yet: nothing thinned')
net.update(0)
packets = {}
pos(before, 7)
pos(before, 7)
T.check(#packets == 1, 'positions: our traffic far from everyone: thinned (1 a second)')
net.update(1.0)
pos(before, 7)
T.check(#packets == 2, 'positions: ... the next one a second later')

-- the nearest player: a player 100 m from our traffic car gives it the full rate
local car = S.newObject('BeamNGVehicle')
car.pos = vec3(100, 0, 0)
function getObjectByID(id) return id == 7 and car or nil end
local anchor = { geodeticToEnu = function(_, lat, lon) return lon * 1000, lat * 1000, 0 end }
net.update(0.5, anchor, { { lat = 0, lon = 0 } })
packets = {}
for _ = 1, 10 do net.update(1 / net.POS_HZ_NEAR); pos(before, 7) end
T.check(#packets == 10, 'positions: a player 100 m away: every 1/POS_HZ_NEAR s (' .. #packets .. ')')

-- inputs: our traffic's merged, at most INPUTS_HZ; other cars' straight through
local inputs = {}
local send = net.wrapInputs(function(data, gid) inputs[#inputs + 1] = { data = data, gid = gid } end)
send('{"s":0.2}', 3)
T.check(#inputs == 1 and inputs[1].data == '{"s":0.2}', 'inputs: our own car: straight through')
inputs = {}
send('{"t":0.5,"s":-0.1}', 7)
send('{"b":1}', 7)
T.check(#inputs == 0, 'inputs: our traffic: held')
net.update(1 / net.INPUTS_HZ)
T.check(#inputs == 1 and inputs[1].data == '{"b":1,"s":-0.1,"t":0.5}', 'inputs: merged, the latest of each: '
  .. tostring(inputs[1] and inputs[1].data))
send('{"s":0.2}', 7)
net.update(0.01)
T.check(#inputs == 1, 'inputs: not again within 1/INPUTS_HZ')
net.update(1 / net.INPUTS_HZ)
T.check(#inputs == 2 and inputs[2].data == '{"s":0.2}', 'inputs: then the change')

-- our update stops (the world server is not connected): everything through, as BeamMP would
send('{"b":1}', 7)              -- (held: our update is still live)
real = real + net.STALE_S + 1
inputs, packets = {}, {}
send('{"s":0.3}', 7)
T.check(inputs[1] and inputs[1].data == '{"b":1,"s":0.3}', 'our update stopped: the held change goes with the next')
pos(before, 7)
pos(before, 7)
T.check(#inputs == 1 and #packets == 2, 'our update stopped: inputs and positions straight through')

local st = net.status()
T.check(st.bytesOut < st.bytesIn, 'status: fewer bytes out than in')
net.reset()
T.done('test_mpnet')
