-- BeamNG.Earth: Overland Bush Camps & Rooftop Tent Simulation
-- Allows players to pull off the trail, deploy rooftop tents, awnings, LED camp lighting,
-- and crackling campfires. Resting at camp eliminates fatigue, advances time of day, and
-- grants the "Well-Rested Bush Explorer" buff (+10% payout bonus and 20% fatigue resistance).

local M = {}
local places = require('beamngEarth/places')

local campState = {
  deployed = false,
  lat = nil,
  lon = nil,
  deployedAt = 0,
  hasBuff = false,
  buffExpiresAt = 0,
  amenities = {
    rooftopTent = true,
    sideAwning = true,
    campfire = true,
    campChairs = true,
    floodlights = true
  }
}

-- Safe reference to freight & expeditions
local function getFreight()
  local fr = rawget(_G, 'beamngEarth_freight') or (extensions and extensions.beamngEarth_freight)
  if not fr then pcall(function() fr = require('beamngEarth/freight') end) end
  return fr
end

local function broadcastCamp(payload)
  local mps = rawget(_G, 'beamngEarth_mpsession') or (extensions and extensions.beamngEarth_mpsession)
  if mps and mps.isSessionActive and mps.isSessionActive() and mps.sendLogisticsEvent then
    pcall(mps.sendLogisticsEvent, payload)
  elseif rawget(_G, 'TriggerServerEvent') then
    local data = payload
    if rawget(_G, 'jsonEncode') then data = jsonEncode(payload) end
    pcall(TriggerServerEvent, 'bngeLogistics', data)
  end
end

-- Deploy camp at current vehicle location
function M.deployCamp(playerLat, playerLon, playerVeh)
  if campState.deployed then
    return false, 'Camp already deployed'
  end

  local speed = playerVeh and playerVeh.getVelocity and playerVeh:getVelocity():length() or 0
  if speed >= 0.8 then
    return false, 'Vehicle must be completely stopped to deploy camp'
  end

  if not playerLat or not playerLon then
    return false, 'Unknown coordinates'
  end

  campState.deployed = true
  campState.lat = playerLat
  campState.lon = playerLon
  campState.deployedAt = os.time()

  -- Send visual light / prop command to BeamNG vehicle if present
  if playerVeh then
    pcall(function()
      playerVeh:queueLuaCommand("if electrics then electrics.set_lightbar_signal(1) end")
    end)
  end

  broadcastCamp({
    type = 'bushcamp_deploy',
    lat = playerLat,
    lon = playerLon,
    amenities = campState.amenities
  })

  if rawget(_G, 'ui_message') then
    pcall(ui_message, "🏕️ BUSH CAMP DEPLOYED: Rooftop tent open, campfire lit, floodlights on. Sit back and enjoy the African bushveld!", 7, 'beamngEarthCamp')
  end

  return true, campState
end

-- Pack up camp and get back on the trail
function M.packCamp(playerVeh)
  if not campState.deployed then
    return false, 'No camp currently deployed'
  end

  campState.deployed = false
  campState.lat = nil
  campState.lon = nil

  if playerVeh then
    pcall(function()
      playerVeh:queueLuaCommand("if electrics then electrics.set_lightbar_signal(0) end")
    end)
  end

  broadcastCamp({
    type = 'bushcamp_pack'
  })

  if rawget(_G, 'ui_message') then
    pcall(ui_message, "⛺ CAMP PACKED: Rooftop tent stowed, fire extinguished. Safe travels on the trail!", 5, 'beamngEarthCamp')
  end

  return true
end

-- Rest by the campfire: advances time of day, wipes fatigue, and grants explorer buff
function M.restAtCamp(hours)
  hours = hours or 8
  if not campState.deployed then
    return false, 'Must deploy camp first to rest by campfire'
  end

  -- 1. Advance BeamNG TimeOfDay
  local scenetree = rawget(_G, 'scenetree')
  local names = scenetree and scenetree.findClassObjects and scenetree.findClassObjects('TimeOfDay')
  local tod = names and names[1] and scenetree.findObject(names[1])
  if tod then
    local currentT = tonumber(tod.time) or 0
    tod.time = (currentT + hours / 24) % 1.0
  end

  -- 2. Clear driver fatigue in freight module
  local fr = getFreight()
  if fr and fr.restDriver then
    pcall(fr.restDriver, hours)
  end

  -- 3. Grant "Well-Rested Bush Explorer" buff for 7200 seconds (2 real hours)
  campState.hasBuff = true
  campState.buffExpiresAt = os.time() + 7200

  if rawget(_G, 'ui_message') then
    pcall(ui_message, string.format("🌌 CAMP REST COMPLETED: Slept %d hours under the Southern Cross! Fatigue 0%%, 'Well-Rested Explorer' buff active (+10%% bonus).", hours), 7, 'beamngEarthCamp')
  end

  return true, {
    hours = hours,
    buffExpiresAt = campState.buffExpiresAt
  }
end

-- Check if active buff is running
function M.hasExplorerBuff()
  if campState.hasBuff and os.time() < campState.buffExpiresAt then
    return true
  end
  campState.hasBuff = false
  return false
end

-- UI State
function M.getUiState(playerLat, playerLon, playerVeh)
  local speed = playerVeh and playerVeh.getVelocity and playerVeh:getVelocity():length() or 0
  local canDeploy = not campState.deployed and (speed < 0.8) and (playerLat ~= nil)
  local canPack = campState.deployed
  local buffActive = M.hasExplorerBuff()

  return {
    deployed = campState.deployed,
    canDeploy = canDeploy,
    canPack = canPack,
    lat = campState.lat,
    lon = campState.lon,
    amenities = campState.amenities,
    hasBuff = buffActive,
    buffMinutesLeft = buffActive and math.max(1, math.floor((campState.buffExpiresAt - os.time()) / 60)) or 0
  }
end

function M.reset()
  campState.deployed = false
  campState.lat = nil
  campState.lon = nil
  campState.deployedAt = 0
  campState.hasBuff = false
  campState.buffExpiresAt = 0
end

return M
