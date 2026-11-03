-- BeamNG.Earth: Convoy Vehicle Recovery, Winch & Field Repair Simulation
-- Provides kinetic snatch-strap towing between stuck vehicles, field tire puncture repairs,
-- suspension tie-rod straightening with High-Lift jacks, and Channel 9 10-33 SOS broadcasts.

local M = {}
local places = require('beamngEarth/places')

local recoveryState = {
  lastRepairTime = 0,
  towActive = false,
  tetherTarget = nil,
  repairsCompleted = 0
}

local function getFreight()
  local fr = rawget(_G, 'beamngEarth_freight') or (extensions and extensions.beamngEarth_freight)
  if not fr then pcall(function() fr = require('beamngEarth/freight') end) end
  return fr
end

local function getConvoy()
  local cv = rawget(_G, 'beamngEarth_convoy') or (extensions and extensions.beamngEarth_convoy)
  if not cv then pcall(function() cv = require('beamngEarth/convoy') end) end
  return cv
end

-- Broadcast recovery event across BeamMP
local function broadcastRecovery(payload)
  local mps = rawget(_G, 'beamngEarth_mpsession') or (extensions and extensions.beamngEarth_mpsession)
  if mps and mps.isSessionActive and mps.isSessionActive() and mps.sendLogisticsEvent then
    pcall(mps.sendLogisticsEvent, payload)
  elseif rawget(_G, 'TriggerServerEvent') then
    local data = payload
    if rawget(_G, 'jsonEncode') then data = jsonEncode(payload) end
    pcall(TriggerServerEvent, 'bngeLogistics', data)
  end
end

-- 1. Field Tire Puncture Repair
function M.repairTires(playerVeh)
  if not playerVeh then
    return false, 'No player vehicle found'
  end

  local now = os.time()
  if now - recoveryState.lastRepairTime < 15 then
    return false, 'Repair kit cooldown active (wait a few seconds)'
  end
  recoveryState.lastRepairTime = now
  recoveryState.repairsCompleted = recoveryState.repairsCompleted + 1

  -- Reinflate tires via BeamNG vehicle Lua
  pcall(function()
    playerVeh:queueLuaCommand("if wheels then for _, w in pairs(wheels.wheels) do if w.setTirePressure then w:setTirePressure(w.targetPressure or 32) end end end")
  end)

  if rawget(_G, 'ui_message') then
    pcall(ui_message, "🔧 FIELD TIRE REPAIRED: Puncture plugged, tire reseated and pressurized to 32 PSI!", 6, 'beamngEarthRecovery')
  end

  return true, { status = 'repaired', timestamp = now }
end

-- 2. Kinetic Snatch-Strap & Tow Recovery
function M.connectSnatchStrap(playerLat, playerLon, playerVeh)
  if not playerVeh then return false, 'No player vehicle' end

  local cv = getConvoy()
  local targets = cv and cv.getRadarTargets and cv.getRadarTargets(playerLat, playerLon, playerVeh) or {}
  local closest = nil
  for _, t in ipairs(targets) do
    if t.distanceM and t.distanceM <= 45 then
      closest = t
      break
    end
  end

  local targetName = closest and closest.name or 'Convoy Lead Truck'

  -- Apply forward recovery winch impulse force to help pull vehicle out of mud/sand ruts
  pcall(function()
    local rot = playerVeh:getRotation()
    local fwd = rot * vec3(0, 1, 0)
    -- Apply gentle forward tug impulse
    playerVeh:applyClusterVelocityScaleAdd(playerVeh:getRefNodeId(), 1.0, vec3(fwd.x * 2.5, fwd.y * 2.5, 0.5))
  end)

  recoveryState.towActive = true
  recoveryState.tetherTarget = targetName

  broadcastRecovery({
    type = 'recovery_tow',
    target = targetName,
    lat = playerLat,
    lon = playerLon
  })

  if rawget(_G, 'ui_message') then
    pcall(ui_message, string.format("🪢 SNATCH-STRAP TETHERED: Hooked kinetic recovery rope to %s! Applying forward winch pull.", targetName), 6, 'beamngEarthRecovery')
  end

  return true, { target = targetName }
end

-- 3. Broadcast 10-33 Breakdown Emergency SOS on Channel 9
function M.sendEmergencySos(playerLat, playerLon, playerVeh)
  local cv = getConvoy()
  if not cv then return false, 'CB radio module unavailable' end

  local coords = (playerLat and playerLon) and string.format("%.4f, %.4f", playerLat, playerLon) or "Unknown GPS"
  local fr = getFreight()
  local comp = fr and fr.getCompany and fr.getCompany() or {}
  local callsign = comp.name or 'OTBT Driver'

  local msg = string.format("🚨 10-33 EMERGENCY! Vehicle disabled in terrain at [%s]. Requesting recovery assist!", coords)
  local ok, res = cv.transmit(9, msg, callsign, 'breakdown')

  if rawget(_G, 'ui_message') then
    pcall(ui_message, "🚨 10-33 SOS TRANSMITTED on Channel 9 Emergency Frequency!", 6, 'beamngEarthRecovery')
  end

  return ok, res
end

-- 4. High-Lift Jack & Suspension Realignment
function M.realignSuspension(playerVeh)
  if not playerVeh then return false, 'No player vehicle' end

  local speed = playerVeh.getVelocity and playerVeh:getVelocity():length() or 0
  if speed >= 0.5 then
    return false, 'Vehicle must be stopped to use High-Lift Jack'
  end

  pcall(function()
    playerVeh:queueLuaCommand("if wheels then for _, w in pairs(wheels.wheels) do if w.resetAlignment then w:resetAlignment() end end end")
  end)

  if rawget(_G, 'ui_message') then
    pcall(ui_message, "🔩 HIGH-LIFT JACK: Chassis lifted, steering tie-rods aligned, suspension centered!", 6, 'beamngEarthRecovery')
  end

  return true
end

-- UI State
function M.getUiState(playerLat, playerLon, playerVeh)
  local speed = playerVeh and playerVeh.getVelocity and playerVeh:getVelocity():length() or 0
  local cv = getConvoy()
  local targets = cv and cv.getRadarTargets and cv.getRadarTargets(playerLat, playerLon, playerVeh) or {}
  local nearTeammate = false
  for _, t in ipairs(targets) do
    if t.distanceM and t.distanceM <= 45 then
      nearTeammate = true
      break
    end
  end

  return {
    canRepair = os.time() - recoveryState.lastRepairTime >= 15,
    canTow = (speed < 4.0),
    canJack = (speed < 0.5),
    nearTeammate = nearTeammate,
    tetherTarget = recoveryState.tetherTarget,
    towActive = recoveryState.towActive,
    repairsCompleted = recoveryState.repairsCompleted
  }
end

function M.reset()
  recoveryState.towActive = false
  recoveryState.tetherTarget = nil
  recoveryState.lastRepairTime = 0
end

return M
