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

-- bad input ignored; stale poses and players who left out
T.check(G.onPose(4, { v = 1, aLat = 1, aLon = 1, lat = 1, lon = 1 }, 'd') == nil and G.players[4] == nil,
  'another protocol: ignored')
T.check(G.onPose(5, { v = G.PROTO, aLat = 1, aLon = 1, lat = 95, lon = 1 }, 'e') == nil and G.players[5] == nil,
  'a bad latitude: ignored')
G.tick(G.STALE_S + 1)
T.check(next(G.tick(0)) == nil, 'no pose for STALE_S: left out')
G.onLeave(1)
T.check(G.players[1] == nil, 'left: forgotten')

-- logistics and expedition multiplayer event handling (G.onLogistics)
do
  -- 1. sync_request
  local rep, target = G.onLogistics(2, { type = 'sync_request' }, 'player2')
  T.check(rep and rep.type == 'sync_state' and target == 2, 'sync_request returns state targeted to player')
  T.check(rep.state and rep.state.company and rep.state.company.vault == 25000, 'initial vault state in sync')

  -- 2. accept contract
  local testJob = {
    id = '#TST-101',
    trucksRequired = 2,
    slots = {
      { slot = 1, status = 'in_transit', claimedBy = 'Alpha' },
      { slot = 2, status = 'open', claimedBy = nil }
    }
  }
  rep, target = G.onLogistics(1, { type = 'accept', contract = testJob, slotIndex = 1 }, 'Alpha')
  T.check(rep and rep.type == 'accept' and target == -1, 'accept broadcasts to all players (-1)')
  T.check(G.logistics.activeContract ~= nil and G.logistics.activeContract.id == '#TST-101', 'server stored active contract')

  -- 3. claim slot 2
  rep, target = G.onLogistics(2, { type = 'claim', jobId = '#TST-101', slotIndex = 2 }, 'Bravo')
  T.check(rep and rep.type == 'claim' and target == -1, 'claim broadcasts to all players')
  T.check(G.logistics.activeContract.slots[2].claimedBy == 'Bravo', 'server updated slot 2 owner')

  -- 4. damage update
  rep, target = G.onLogistics(2, { type = 'damage', jobId = '#TST-101', slotIndex = 2, cargoHealth = 85, damagePenalty = 1500 }, 'Bravo')
  T.check(rep and rep.type == 'damage' and target == -1, 'damage broadcasts to all players')
  T.check(G.logistics.activeContract.slots[2].damagePenalty == 1500, 'server recorded penalty')

  -- 5. deliver slot
  rep, target = G.onLogistics(1, { type = 'deliver_slot', jobId = '#TST-101', slotIndex = 1 }, 'Alpha')
  T.check(rep and rep.type == 'deliver_slot' and target == -1, 'deliver_slot broadcast')
  T.check(G.logistics.activeContract.slots[1].status == 'delivered', 'server updated slot 1 delivered')

  -- 6. finalize contract
  local initVault = G.logistics.company.vault
  rep, target = G.onLogistics(2, { type = 'finalize', jobId = '#TST-101', netPayout = 12000, tonnes = 40, reputationDelta = 2 }, 'Bravo')
  T.check(rep and rep.type == 'finalize' and target == -1, 'finalize broadcast')
  T.check(G.logistics.activeContract == nil, 'active contract cleared on finalize')
  T.check(G.logistics.company.vault == initVault + 12000, 'server company vault credited')
  T.check(G.logistics.company.completedDeliveries == 1, 'delivery count incremented')

  -- 7. expedition events
  local testTour = { id = 'tour_test', checkpoints = { { name = 'Start' }, { name = 'End' } } }
  rep, target = G.onLogistics(1, { type = 'expedition_start', expedition = testTour }, 'Alpha')
  T.check(rep and rep.type == 'expedition_start' and target == -1, 'expedition_start broadcast')
  T.check(G.logistics.activeExpedition ~= nil, 'server stored active expedition')

  rep, target = G.onLogistics(1, { type = 'expedition_stage', expeditionId = 'tour_test', stage = 2, status = 'active' }, 'Alpha')
  T.check(rep and rep.type == 'expedition_stage' and target == -1, 'expedition_stage broadcast')
  T.check(G.logistics.activeExpedition.currentCheckpointIndex == 2, 'server updated checkpoint index')

  rep, target = G.onLogistics(1, { type = 'expedition_complete', expeditionId = 'tour_test' }, 'Alpha')
  T.check(rep and rep.type == 'expedition_complete' and target == -1, 'expedition_complete broadcast')
  T.check(G.logistics.activeExpedition == nil, 'active expedition cleared on complete')

  -- 8. set_company_name
  rep, target = G.onLogistics(1, { type = 'set_company_name', name = 'Kalahari Express' }, 'Alpha')
  T.check(rep and rep.type == 'set_company_name' and target == -1, 'set_company_name broadcast')
  T.check(G.logistics.company.name == 'Kalahari Express', 'server updated group name')

  -- 9. purchase_upgrade
  G.logistics.company.vault = 80000
  rep, target = G.onLogistics(1, { type = 'purchase_upgrade', upgradeId = 'license_hazmat', cost = 35000 }, 'Alpha')
  T.check(rep and rep.type == 'purchase_upgrade' and target == -1, 'purchase_upgrade broadcast')
  T.check(G.logistics.company.upgrades['license_hazmat'] ~= nil, 'server stored upgrade')
  T.check(G.logistics.company.vault == 45000, 'server vault deducted for upgrade')
end

T.done('test_beammp_plugin')
