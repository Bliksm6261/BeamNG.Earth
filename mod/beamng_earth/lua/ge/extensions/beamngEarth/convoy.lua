-- BeamNG.Earth: In-Game CB Radio & Convoy Radar Simulation
-- Manages retro trucker CB radio channels (CH 19 Highway, CH 1 Convoy, CH 9 Emergency),
-- quick callout presets, live convoy radar tracking teammate distances/bearings/speeds/health.

local M = {}
local places = require('beamngEarth/places')

-- CB Channels
M.CHANNELS = {
  { id = 19, name = 'Channel 19', label = 'The Highway Channel (General Road Comms)' },
  { id = 1,  name = 'Channel 1',  label = 'Convoy Operations (Formation & Pace)' },
  { id = 9,  name = 'Channel 9',  label = 'Emergency & Recovery (10-33 Assistance)' }
}

-- CB Preset Callouts
M.PRESETS = {
  { code = '10-4',      label = '10-4 Acknowledged',  text = '10-4, copy that good buddy!' },
  { code = 'rolling',   label = 'Convoy Rolling',     text = 'Breaker 1-9, convoy rolling out!' },
  { code = 'smokey',    label = 'Speed Trap',         text = '⚠️ Smokey / speed trap spotted ahead! Keep it under the limit.' },
  { code = 'hazard',    label = 'Road Hazard',        text = '⚠️ Hazard on the tarmac / debris in lane. Slow down!' },
  { code = 'fuel',      label = 'Fuel / Rest Stop',   text = '⛽ Pulling off into the next truck stop for fuel and rest.' },
  { code = 'breakdown', label = '10-33 Breakdown',    text = '🔧 10-33! Mechanical emergency / breakdown in lane. Need assist!' },
  { code = 'docking',   label = 'Loading Bay Dock',   text = '🅿️ Arrived at destination depot, backing into loading bay.' },
  { code = 'location',  label = "What's Your 20?",    text = "What's your 20? Transmitting current position check." }
}

local currentChannel = 19
local radioHistory = {}
local MAX_HISTORY = 30

-- Safe reference to freight module
local function getFreight()
  local fr = rawget(_G, 'beamngEarth_freight') or (extensions and extensions.beamngEarth_freight)
  if not fr then pcall(function() fr = require('beamngEarth/freight') end) end
  return fr
end

-- Helper: Convert bearing in degrees to clock direction relative to truck heading
function M.bearingToClock(bearingDeg, truckHeadingDeg)
  truckHeadingDeg = truckHeadingDeg or 0
  local rel = (bearingDeg - truckHeadingDeg + 360) % 360
  local hour = math.floor((rel + 15) / 30) % 12
  if hour == 0 then return "12 o'clock (Ahead)" end
  if hour == 6 then return "6 o'clock (Behind)" end
  if hour == 3 then return "3 o'clock (Right)" end
  if hour == 9 then return "9 o'clock (Left)" end
  return string.format("%d o'clock", hour)
end

-- Helper: Calculate geographic bearing from (lat1, lon1) to (lat2, lon2)
function M.calculateBearing(lat1, lon1, lat2, lon2)
  if not lat1 or not lon1 or not lat2 or not lon2 then return 0 end
  local dLon = math.rad(lon2 - lon1)
  local y = math.sin(dLon) * math.cos(math.rad(lat2))
  local x = math.cos(math.rad(lat1)) * math.sin(math.rad(lat2)) -
            math.sin(math.rad(lat1)) * math.cos(math.rad(lat2)) * math.cos(dLon)
  local brng = math.deg(math.atan2(y, x))
  return (brng + 360) % 360
end

-- Set active radio channel
function M.setChannel(ch)
  if not require('beamngEarth/logistics').enabled() then return false, 'OTBT logistics disabled' end
  ch = tonumber(ch) or 19
  for _, c in ipairs(M.CHANNELS) do
    if c.id == ch then
      currentChannel = ch
      return true, ch
    end
  end
  return false, 'Invalid channel'
end

function M.getChannel()
  return currentChannel
end

-- Transmit CB radio message
function M.transmit(channel, message, callsign, code)
  if not require('beamngEarth/logistics').enabled() then return false, 'OTBT logistics disabled' end
  channel = tonumber(channel) or currentChannel
  message = tostring(message or ''):sub(1, 120)
  if #message == 0 then return false, 'Empty transmission' end

  local fr = getFreight()
  local comp = fr and fr.getCompany and fr.getCompany() or {}
  callsign = callsign or comp.name or 'OTBT Driver'

  local entry = {
    channel = channel,
    callsign = callsign,
    message = message,
    code = code or 'custom',
    time = os.time(),
    isSelf = true
  }

  table.insert(radioHistory, 1, entry)
  if #radioHistory > MAX_HISTORY then table.remove(radioHistory) end

  -- Broadcast via BeamMP if multiplayer active
  require('beamngEarth/mpsession').sendLogisticsEvent({
    type = 'cb_radio', channel = channel, callsign = callsign,
    message = message, code = code or 'custom'
  })

  if rawget(_G, 'ui_message') then
    pcall(ui_message, string.format("📻 [CH %d] %s: %s", channel, callsign, message), 6, 'beamngEarthCB')
  end

  return true, entry
end

-- Receive incoming radio message from server/peer
function M.receiveRadioMessage(msg)
  if not require('beamngEarth/logistics').enabled() then return false, 'OTBT logistics disabled' end
  if type(msg) ~= 'table' then return end
  local entry = {
    channel = tonumber(msg.channel) or 19,
    callsign = tostring(msg.callsign or msg.playerName or 'Convoy Member'),
    message = tostring(msg.message or ''),
    code = tostring(msg.code or ''),
    time = tonumber(msg.time) or os.time(),
    isSelf = false
  }

  table.insert(radioHistory, 1, entry)
  if #radioHistory > MAX_HISTORY then table.remove(radioHistory) end

  -- Only notify if on same channel or emergency channel (CH 9)
  if entry.channel == currentChannel or entry.channel == 9 then
    if rawget(_G, 'ui_message') then
      pcall(ui_message, string.format("📻 [CH %d] %s: %s", entry.channel, entry.callsign, entry.message), 6, 'beamngEarthCB')
    end
  end
end

-- Convoy radar target scanner
function M.getRadarTargets(playerLat, playerLon, playerVeh)
  local targets = {}
  if not playerLat or not playerLon then return targets end

  local truckHeading = 0
  local mySpeedKmh = 0
  if playerVeh and playerVeh.getVelocity then
    local vel = playerVeh:getVelocity()
    mySpeedKmh = math.floor(vel:length() * 3.6 + 0.5)
  end

  -- 1. Scan multiplayer peers if connected
  local mps = rawget(_G, 'beamngEarth_mpsession') or (extensions and extensions.beamngEarth_mpsession)
  local peers = mps and mps.getPeers and mps.getPeers()
  if type(peers) == 'table' then
    for id, peer in pairs(peers) do
      if type(peer) == 'table' and tonumber(peer.lat) and tonumber(peer.lon) then
        local distM = places.distance(playerLat, playerLon, peer.lat, peer.lon)
        local brng = M.calculateBearing(playerLat, playerLon, peer.lat, peer.lon)
        local clock = M.bearingToClock(brng, truckHeading)
        table.insert(targets, {
          id = tostring(id),
          name = peer.name or ('Teammate ' .. tostring(id)),
          type = peer.vehicleType or 'truck',
          distanceM = math.floor(distM + 0.5),
          bearingDeg = math.floor(brng + 0.5),
          clockDirection = clock,
          speedKmh = peer.speedKmh or 0,
          cargoHealth = peer.cargoHealth or 100,
          status = peer.status or 'in_transit'
        })
      end
    end
  end

  -- 2. If single-player or no peers, check active multi-truck contract
  local fr = getFreight()
  local contract = fr and fr.getActiveContract and fr.getActiveContract()
  if #targets == 0 and contract and contract.trucksRequired and contract.trucksRequired > 1 then
    -- Generate convoy squad representations for assigned fleet slots
    for s = 2, contract.trucksRequired do
      local slot = contract.slots and contract.slots[s]
      local offsetM = (s - 1) * 85 -- Staggered 85m convoy spacing behind leader
      local slotName = slot and slot.claimedBy or string.format("Fleet Truck #%d (%s)", s, contract.cargo.name)
      table.insert(targets, {
        id = 'squad_' .. tostring(s),
        name = slotName,
        type = 'truck',
        distanceM = offsetM,
        bearingDeg = 180,
        clockDirection = "6 o'clock (Behind)",
        speedKmh = mySpeedKmh,
        cargoHealth = slot and slot.cargoHealth or 100,
        status = slot and slot.status or 'in_transit'
      })
    end
  end

  -- Sort targets by distance ascending
  table.sort(targets, function(a, b) return (a.distanceM or 0) < (b.distanceM or 0) end)
  return targets
end

-- Get state for UI and HUD app
function M.getUiState(playerLat, playerLon, playerVeh)
  local speedKmh = 0
  if playerVeh and playerVeh.getVelocity then
    speedKmh = math.floor(playerVeh:getVelocity():length() * 3.6 + 0.5)
  end

  return {
    currentChannel = currentChannel,
    channels = M.CHANNELS,
    presets = M.PRESETS,
    recentChatter = radioHistory,
    radarTargets = M.getRadarTargets(playerLat, playerLon, playerVeh),
    speedKmh = speedKmh
  }
end

function M.getRadioHistory()
  return radioHistory
end

function M.reset()
  radioHistory = {}
  currentChannel = 19
end

return M
