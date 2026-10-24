-- luajit mod/tests/test_beammp_plugin.lua  (BeamNG.Earth's BeamMP server plugin, beammp/Server/BeamNGEarth/main.lua,
-- its pure part; the server runs Lua 5.3, this file keeps to what both have): every player's anchor and place for
-- the clients' position conversion, sent at once when an anchor changes; a joining player sent to the others.
local dir = (arg[0]:match('^(.*)[/\\]') or '.')
local T = dofile(dir .. '/testlib.lua')
local G = dofile(dir .. '/../../beammp/Server/BeamNGEarth/main.lua')

local M_PER_DEG = 111194.9     -- (G.dist's sphere)

T.check(math.abs(G.dist(0, 0, 1000 / M_PER_DEG, 0) - 1000) < 1, 'dist: 1 km north')

-- the first player: alone, nowhere to go; its anchor new: sent at once
G.players, G.clock = {}, 0
local place, moved = G.onPose(1, { v = G.PROTO, aLat = 36, aLon = -118, lat = 36, lon = -118, joined = true }, 'a')
T.check(place == nil and moved == true, 'the first player: alone, its anchor sent at once')
place, moved = G.onPose(1, { v = G.PROTO, aLat = 36, aLon = -118, lat = 36.001, lon = -118 }, 'a')
T.check(place == nil and moved == false, 'the same anchor: not sent at once (the tick sends it)')
place, moved = G.onPose(1, { v = G.PROTO, aLat = 36.2, aLon = -118, lat = 36.2, lon = -118 }, 'a')
T.check(moved == true, 'a rebase: the anchors go out at once')

-- a second player joining 80 miles away: sent to the first; near: not
G.tick(2)
place = G.onPose(2, { v = G.PROTO, aLat = 35, aLon = -118.7, lat = 35, lon = -118.7, joined = true }, 'b')
T.check(place and place.lat == 36.2 and place.lon == -118, 'a joining player far away: sent to the first player')
place = G.onPose(3, { v = G.PROTO, aLat = 36.2, aLon = -118, lat = 36.201, lon = -118, joined = true }, 'c')
T.check(place == nil, 'a joining player already near them: stays')

-- the anchors message: every live player's anchor and place, keyed by the id as a string
local a = G.anchors(G.live())
T.check(a['1'] and a['1'].aLat == 36.2 and a['2'] and a['2'].lon == -118.7 and a['3'], 'anchors: every player')
T.check(a['1'].name == 'a' and a['1'].h == nil, 'anchors: the name, no heading without one')
G.onPose(1, { v = G.PROTO, aLat = 36.2, aLon = -118, lat = 36.2, lon = -118, h = 90.5 }, 'a')
T.check(G.anchors(G.live())['1'].h == 90.5, 'anchors: the heading (the map arrows)')
G.onPose(1, { v = G.PROTO, aLat = 36.2, aLon = -118, lat = 36.2, lon = -118, h = 'x' }, 'a')
T.check(G.anchors(G.live())['1'].h == nil, 'anchors: a bad heading left out')

-- config: the sharing port set at the top of main.lua, a bad one left out (each player's own default)
T.check(G.config().sharePort == 47621, 'config: the default sharing port')
G.SHARE_PORT = 50000
T.check(G.config().sharePort == 50000, 'config: an edited port')
for _, bad in ipairs({ 80, 70000, 'x' }) do
  G.SHARE_PORT = bad
  T.check(G.config().sharePort == nil, 'config: a bad port left out: ' .. tostring(bad))
end
G.SHARE_PORT = 47621

-- peers: the sharing players on one anchor, the same sorted list for each; a player on another anchor alone
G.players = {}
G.onPose(1, { v = G.PROTO, aLat = 40, aLon = -111.9, lat = 40, lon = -111.9, sp = 47621, sc = 'c1' }, 'u1')
G.onPose(2, { v = G.PROTO, aLat = 40, aLon = -111.9, lat = 40.01, lon = -111.9, sp = 47621, sc = 'c1' }, 'u2')
G.onPose(3, { v = G.PROTO, aLat = 45.46, aLon = 9.19, lat = 45.46, lon = 9.19, sp = 47621, sc = 'c1' }, 'it')
G.onPose(4, { v = G.PROTO, aLat = 40, aLon = -111.9, lat = 40, lon = -111.9 }, 'noshare')
G.onPose(5, { v = G.PROTO, aLat = 40, aLon = -111.9, lat = 40, lon = -111.9, sp = 99999, sc = 'c1' }, 'badport')
for pid, ip in pairs({ [1] = '10.0.0.1', [2] = '10.0.0.2', [3] = '10.0.0.3', [4] = '10.0.0.4', [5] = '10.0.0.5' }) do
  G.players[pid].ip = ip
end
local pe = G.peers(G.live())
T.check(pe[1] and #pe[1].members == 2 and pe[1].members[1].id == '1' and pe[1].members[2].host == '10.0.0.2'
  and pe[2] and G.peersKey(pe[1]) == G.peersKey(pe[2]), 'peers: Utah\'s two share one list')
T.check(pe[3] and #pe[3].members == 1, 'peers: Italy alone')
T.check(pe[4] == nil and pe[5] == nil, 'peers: no sharing port (or a bad one): left out')
G.players, G.sentPeers = {}, {}

-- traffic: the players within TRAFFIC_NEAR_M of each other split their area's cars, the odd ones to the lowest ids;
-- a player far away runs a whole area's
G.TRAFFIC_CARS, G.PARKED_CARS, G.TRAFFIC_NEAR_M = 8, 6, 1000
local near = 800 / M_PER_DEG
local sh = G.trafficShares({ [1] = { lat = -33.9, lon = 18.4 }, [2] = { lat = -33.9 + near, lon = 18.4 },
  [3] = { lat = -33.9 + 2 * near, lon = 18.4 }, [10] = { lat = -26.2, lon = 28.0 } })
T.check(sh[1].traffic == 3 and sh[2].traffic == 3 and sh[3].traffic == 2, 'shares: 8 moving cars over a chain of 3')
T.check(sh[1].parked == 2 and sh[2].parked == 2 and sh[3].parked == 2, 'shares: 6 parked over 3')
T.check(sh[10].traffic == 8 and sh[10].parked == 6 and sh[10].police == false, 'shares: alone in Johannesburg: all of it')
local total = 0
for _, s in pairs(sh) do total = total + s.traffic end
T.check(total == 16, 'shares: each area\'s cars once (2 areas)')
G.TRAFFIC_CARS = 0
T.check(G.trafficShares({ [1] = { lat = 0, lon = 0 } })[1].traffic == 0, 'shares: no traffic set: none')
G.TRAFFIC_CARS = 8

-- the shares sent when they change; the car limit: own cars and the share, the previous (larger) one for a while
G.shares, G.clock = {}, 100
local ch = G.shareChanges({ [1] = { traffic = 8, parked = 6, police = false } })
T.check(ch[1] and G.carLimit(1) == G.OWN_CARS + 14, 'limit: own cars and the share')
T.check(next(G.shareChanges({ [1] = { traffic = 8, parked = 6, police = false } })) == nil, 'shares: unchanged: not sent')
ch = G.shareChanges({ [1] = { traffic = 4, parked = 3, police = false }, [2] = { traffic = 4, parked = 3, police = false } })
T.check(ch[1] and ch[2] and G.carLimit(1) == G.OWN_CARS + 14 and G.carLimit(2) == G.OWN_CARS + 7,
  'limit: a smaller share: the previous one for LIMIT_GRACE_S')
G.clock = 100 + G.LIMIT_GRACE_S
T.check(G.carLimit(1) == G.OWN_CARS + 7, 'limit: then the new share')
G.shareChanges({ [2] = { traffic = 8, parked = 6, police = false } })
T.check(G.shares[1] == nil and G.carLimit(1) == G.OWN_CARS, 'limit: no share (gone): own cars only')
G.onLeave(2)
T.check(G.shares[2] == nil, 'left: the share forgotten')
G.shares, G.clock = {}, 0

-- bad input ignored; stale poses and players who left out
T.check(G.onPose(4, { v = 1, aLat = 1, aLon = 1, lat = 1, lon = 1 }, 'd') == nil and G.players[4] == nil,
  'another protocol: ignored')
T.check(G.onPose(5, { v = G.PROTO, aLat = 1, aLon = 1, lat = 95, lon = 1 }, 'e') == nil and G.players[5] == nil,
  'a bad latitude: ignored')
G.tick(G.STALE_S + 1)
T.check(next(G.tick(0)) == nil, 'no pose for STALE_S: left out')
G.onLeave(1)
T.check(G.players[1] == nil, 'left: forgotten')

T.done('test_beammp_plugin')
