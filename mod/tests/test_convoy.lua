-- Tests for convoy.lua:
-- 1. CB Radio channels and channel switching (CH 19, CH 1, CH 9).
-- 2. Preset callouts verification.
-- 3. Bearing and relative clock direction math (12 o'clock, 6 o'clock, etc.).
-- 4. Radio transmission, circular history buffer, and callsign attribution.
-- 5. Incoming radio message ingestion and channel filtering.
-- 6. Convoy radar target tracking and multi-truck fleet squad detection.

local dir = (arg and arg[0] or ''):match('^(.*)[/\\]') or '.'
local T = dofile(dir .. '/testlib.lua')

-- Stub dependencies
local storage = {}
function jsonReadFile(path) return storage[path] end
function jsonWriteFile(path, data) storage[path] = data; return true end

package.loaded['beamngEarth/gps'] = {
  setDestination = function() return true end
}

local freight = require('beamngEarth/freight')
local convoy = require('beamngEarth/convoy')

--------------------------------------------------------------------------------
-- 1. Channels & Channel Switching
--------------------------------------------------------------------------------
do
  convoy.reset()
  T.check(convoy.getChannel() == 19, 'default radio channel is 19')

  local ok, ch = convoy.setChannel(1)
  T.check(ok and ch == 1, 'switched to Channel 1 (Convoy Operations)')
  T.check(convoy.getChannel() == 1, 'active channel updated to 1')

  local ok9, ch9 = convoy.setChannel(9)
  T.check(ok9 and ch9 == 9, 'switched to Channel 9 (Emergency & Recovery)')

  local badOk, err = convoy.setChannel(99)
  T.check(badOk == false, 'rejected invalid channel 99')
  T.check(convoy.getChannel() == 9, 'channel remained 9 after invalid attempt')

  convoy.setChannel(19)
end

--------------------------------------------------------------------------------
-- 2. Presets Verification
--------------------------------------------------------------------------------
do
  local presets = convoy.PRESETS
  T.check(#presets >= 8, 'has at least 8 retro trucker callout presets')

  local codes = {}
  for _, p in ipairs(presets) do
    T.check(p.code ~= nil, 'preset has code')
    T.check(p.label ~= nil, 'preset has label')
    T.check(p.text ~= nil and #p.text > 0, 'preset has callout text')
    codes[p.code] = true
  end

  T.check(codes['10-4'] == true, 'contains 10-4 preset')
  T.check(codes['rolling'] == true, 'contains rolling preset')
  T.check(codes['smokey'] == true, 'contains smokey preset')
  T.check(codes['breakdown'] == true, 'contains breakdown preset')
end

--------------------------------------------------------------------------------
-- 3. Bearing & Clock Direction Math
--------------------------------------------------------------------------------
do
  -- Point B directly North of Point A
  local bNorth = convoy.calculateBearing(0.0, 0.0, 1.0, 0.0)
  T.check(math.abs(bNorth - 0) < 0.1, 'bearing North is 0 degrees')

  -- Point B directly East of Point A
  local bEast = convoy.calculateBearing(0.0, 0.0, 0.0, 1.0)
  T.check(math.abs(bEast - 90) < 0.1, 'bearing East is 90 degrees')

  -- Clock directions relative to truck heading
  -- Truck heading North (0 deg): Target at 0 deg is 12 o'clock
  local cAhead = convoy.bearingToClock(0, 0)
  T.check(cAhead == "12 o'clock (Ahead)", 'target ahead is 12 o\'clock')

  -- Truck heading North (0 deg): Target at 180 deg is 6 o'clock Behind
  local cBehind = convoy.bearingToClock(180, 0)
  T.check(cBehind == "6 o'clock (Behind)", 'target behind is 6 o\'clock')

  -- Truck heading North (0 deg): Target at 90 deg is 3 o'clock Right
  local cRight = convoy.bearingToClock(90, 0)
  T.check(cRight == "3 o'clock (Right)", 'target east is 3 o\'clock')
end

--------------------------------------------------------------------------------
-- 4. Radio Transmissions & History
--------------------------------------------------------------------------------
do
  convoy.reset()
  freight.reset()
  local comp = freight.getCompany()
  comp.name = 'Trans-Karoo Haulers'

  local ok, tx = convoy.transmit(19, 'Breaker 1-9, convoy rolling out!', 'Trans-Karoo Haulers', 'rolling')
  T.check(ok, 'transmission sent successfully')
  T.check(tx.channel == 19, 'transmission on channel 19')
  T.check(tx.callsign == 'Trans-Karoo Haulers', 'callsign matches company name')
  T.check(tx.isSelf == true, 'marked as local transmission')

  local history = convoy.getRadioHistory()
  T.check(#history == 1, 'transmission added to radio history')
  T.check(history[1].code == 'rolling', 'history preserves preset code')

  -- Transmit multiple messages to test history buffer
  for i = 1, 10 do
    convoy.transmit(19, 'Check #' .. i, 'Driver', 'custom')
  end
  local history2 = convoy.getRadioHistory()
  T.check(#history2 == 11, 'radio history accumulates entries')
  T.check(history2[1].message == 'Check #10', 'newest message is at top of log')
end

--------------------------------------------------------------------------------
-- 5. Incoming Radio Message Handling
--------------------------------------------------------------------------------
do
  convoy.setChannel(19)
  convoy.receiveRadioMessage({
    channel = 19,
    callsign = 'BigRig99',
    message = '10-4, road is clear ahead!',
    code = '10-4',
    time = os.time()
  })

  local history = convoy.getRadioHistory()
  T.check(history[1].callsign == 'BigRig99', 'received message from remote peer')
  T.check(history[1].isSelf == false, 'marked as remote transmission')
end

--------------------------------------------------------------------------------
-- 6. Convoy Radar & Multi-Truck Squad Target Detection
--------------------------------------------------------------------------------
do
  freight.reset()
  -- Set active 3-truck convoy contract
  local multiJob = {
    id = '#CV-300',
    origin = { name = 'Joburg Hub', lat = -26.2, lon = 28.0 },
    destination = { name = 'Durban Port', lat = -29.8, lon = 31.0 },
    cargo = { name = 'Ultra-Low Sulfur Diesel', category = 'tanker' },
    trucksRequired = 3,
    slots = {
      { slot = 1, status = 'in_transit', cargoHealth = 100 },
      { slot = 2, status = 'in_transit', cargoHealth = 95, claimedBy = 'Convoy Wingman' },
      { slot = 3, status = 'in_transit', cargoHealth = 90, claimedBy = 'Rear Guard' }
    }
  }
  freight.getCompany().name = 'OTBT Fleet'
  freight.onRemoteLogistics({
    type = 'sync_state',
    state = { activeContract = multiJob }
  })

  local targets = convoy.getRadarTargets(-26.2000, 28.0000, nil)
  T.check(#targets == 2, 'radar tracks 2 convoy escorts for 3-truck contract')
  T.check(targets[1].name == 'Convoy Wingman', 'identifies Wingman in slot 2')
  T.check(targets[1].cargoHealth == 95, 'reports Wingman health 95%')
  T.check(targets[2].name == 'Rear Guard', 'identifies Rear Guard in slot 3')
  T.check(targets[2].cargoHealth == 90, 'reports Rear Guard health 90%')
  T.check(targets[2].distanceM > targets[1].distanceM, 'rear guard staggered further back')
end

freight.reset()
beamngEarth_mpsession = require('beamngEarth/mpsession')
T.check(#convoy.getRadarTargets(-26, 28) == 0, 'real mpsession with no peers is safe')
beamngEarth_mpsession = {getPeers=function() return nil end}
T.check(#convoy.getRadarTargets(-26, 28) == 0, 'nil peers are safe')
beamngEarth_mpsession = {getPeers=function() return {} end}
T.check(#convoy.getRadarTargets(-26, 28) == 0, 'empty peers are safe')
beamngEarth_mpsession = nil
T.done('test_convoy')
