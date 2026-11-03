-- BeamNG.Earth: African Regional Weather, Severe Bush Storms & Mud Surface Physics
-- Manages specialized Southern/Eastern African weather phenomena (Highveld Supercells,
-- Kalahari Haboobs, Drakensberg Mountain Fog, Karoo Scorcher) and dynamically simulates
-- wet red clay/mud tire friction degradation and heatwave thermal stress.

local M = {}
local places = require('beamngEarth/places')

-- Weather presets catalog
M.PRESETS = {
  {
    id = 'highveld_thunderstorm',
    name = 'Highveld Summer Supercell',
    category = 'storm',
    icon = '⛈️',
    description = 'Violent afternoon thunderstorm with torrential rain, lightning flashes, purple anvil clouds, and slick red mud ruts.',
    rainMmH = 55.0,
    visM = 1500,
    windMs = 18.0,
    gustMs = 28.0,
    tempC = 19,
    coverLow = 95,
    coverMid = 90,
    coverHigh = 85,
    mudFactor = 0.85, -- Greasy slick mud on dirt tracks (friction ~0.48)
    skyTint = { r = 0.45, g = 0.42, b = 0.55 }
  },
  {
    id = 'kalahari_haboob',
    name = 'Kalahari Dust Haboob',
    category = 'dust',
    icon = '🌪️',
    description = 'Towering wall of desert sand and red dust. Strong howling winds with extreme low visibility and loose sand drift.',
    rainMmH = 0.0,
    visM = 350,
    windMs = 22.0,
    gustMs = 34.0,
    tempC = 34,
    coverLow = 20,
    coverMid = 50,
    coverHigh = 70,
    mudFactor = 0.10,
    sandFactor = 0.75, -- Soft sand resistance
    skyTint = { r = 0.82, g = 0.55, b = 0.32 }
  },
  {
    id = 'escarpment_fog',
    name = 'Drakensberg Escarpment Mist',
    category = 'fog',
    icon = '🌫️',
    description = 'Dense mountain pea-soup mist along Long Tom Pass and Sani Pass. Damp road tarmac with near-zero visibility.',
    rainMmH = 3.5,
    visM = 110,
    windMs = 3.5,
    gustMs = 6.0,
    tempC = 11,
    coverLow = 100,
    coverMid = 80,
    coverHigh = 60,
    mudFactor = 0.40,
    skyTint = { r = 0.70, g = 0.72, b = 0.75 }
  },
  {
    id = 'karoo_scorcher',
    name = 'Great Karoo Heatwave',
    category = 'arid',
    icon = '☀️',
    description = 'Blistering 42°C arid heat with shimmering mirage haze, dry dust, and high thermal stress on heavy semi radiators.',
    rainMmH = 0.0,
    visM = 35000,
    windMs = 5.0,
    gustMs = 9.0,
    tempC = 42,
    coverLow = 0,
    coverMid = 10,
    coverHigh = 15,
    mudFactor = 0.0,
    thermalStress = 1.35,
    skyTint = { r = 1.0, g = 0.98, b = 0.92 }
  },
  {
    id = 'savanna_clear',
    name = 'Golden Bushveld Fair Sky',
    category = 'fair',
    icon = '🌤️',
    description = 'Crisp sunny African sky over the open acacia savanna with gentle warm breeze and optimum driving grip.',
    rainMmH = 0.0,
    visM = 40000,
    windMs = 4.0,
    gustMs = 7.0,
    tempC = 27,
    coverLow = 15,
    coverMid = 20,
    coverHigh = 25,
    mudFactor = 0.0,
    skyTint = { r = 0.95, g = 0.95, b = 1.0 }
  }
}

local activePreset = nil
local activeMudFriction = 1.0
local lastPhysicsTick = 0
local autoWeatherEnabled = true

-- Get weather extension safely
local function getWeatherExt()
  local w = rawget(_G, 'beamngEarth_weather') or (extensions and extensions.beamngEarth_weather)
  if not w then pcall(function() w = require('beamngEarth/weather') end) end
  return w
end

-- Apply preset to BeamNG weather system
function M.applyPreset(presetId)
  local preset = nil
  for _, p in ipairs(M.PRESETS) do
    if p.id == presetId then preset = p; break end
  end
  if not preset then return false, 'Preset not found' end

  activePreset = preset

  local w = getWeatherExt()
  if w and w.onWeather then
    local msg = {
      rainMmH = preset.rainMmH,
      snowCmH = 0,
      visM = preset.visM,
      slTempC = preset.tempC,
      cover = {
        low = preset.coverLow,
        mid = preset.coverMid,
        high = preset.coverHigh
      },
      wind = {
        ms = preset.windMs,
        gustMs = preset.gustMs,
        fromDeg = 135
      },
      aloft = {
        ms = preset.windMs * 1.5,
        fromDeg = 145
      },
      baseAglM = (preset.category == 'fog') and 150 or ((preset.category == 'storm') and 600 or 2200),
      fog = (preset.category == 'fog' or preset.category == 'dust')
    }
    pcall(w.onWeather, msg)
  end

  -- Apply mud surface friction based on precipitation
  if preset.mudFactor and preset.mudFactor > 0 then
    activeMudFriction = math.max(0.42, 1.0 - (preset.mudFactor * 0.58))
  else
    activeMudFriction = 1.0
  end

  if rawget(_G, 'ui_message') then
    pcall(ui_message, string.format("%s Weather Active: %s — %s", preset.icon, preset.name, preset.description), 7, 'beamngEarthWeather')
  end

  return true, preset
end

-- Get current active weather preset
function M.getActivePreset()
  return activePreset or M.PRESETS[5] -- default savanna clear
end

-- Dynamic weather regional detector
function M.detectRegionalWeather(lat, lon, timeOfDayRatio)
  if not lat or not lon then return M.PRESETS[5].id end

  -- 1. Drakensberg / Lesotho / Eastern Highlands (-28 to -31 lat, 27 to 30 lon)
  if lat <= -28.0 and lat >= -31.5 and lon >= 27.5 and lon <= 30.5 then
    -- High chance of mountain mist in mornings/evenings (timeOfDay < 0.35 or > 0.75)
    if timeOfDayRatio and (timeOfDayRatio < 0.35 or timeOfDayRatio > 0.75) then
      return 'escarpment_fog'
    end
  end

  -- 2. Namib & Kalahari Desert regions (lon < 22, lat -20 to -28)
  if lon <= 22.0 and lat <= -19.0 and lat >= -28.5 then
    -- Dust haboob or scorching sun
    if timeOfDayRatio and (timeOfDayRatio >= 0.40 and timeOfDayRatio <= 0.65) then
      return 'kalahari_haboob'
    else
      return 'karoo_scorcher'
    end
  end

  -- 3. Highveld / Gauteng / Free State plateau (lat -25 to -28, lon 26 to 29)
  if lat <= -25.0 and lat >= -28.0 and lon >= 26.0 and lon <= 29.5 then
    -- Mid-afternoon Highveld thunderstorm (timeOfDay between 0.55 and 0.75: ~13:00 - 18:00)
    if timeOfDayRatio and timeOfDayRatio >= 0.55 and timeOfDayRatio <= 0.75 then
      return 'highveld_thunderstorm'
    end
  end

  return 'savanna_clear'
end

-- Per-tick update: manages dynamic tire friction on mud and thermal engine strain
function M.update(playerLat, playerLon, playerVeh)
  local now = os.time()
  if now - lastPhysicsTick < 3 then return end
  lastPhysicsTick = now

  -- Auto regional weather updates if enabled
  if autoWeatherEnabled and playerLat and playerLon then
    local scenetree = rawget(_G, 'scenetree')
    local names = scenetree and scenetree.findClassObjects and scenetree.findClassObjects('TimeOfDay')
    local tod = names and names[1] and scenetree.findObject(names[1])
    local todVal = tod and tonumber(tod.time) or 0.5

    local targetPresetId = M.detectRegionalWeather(playerLat, playerLon, todVal)
    if not activePreset or activePreset.id ~= targetPresetId then
      M.applyPreset(targetPresetId)
    end
  end

  -- Apply mud surface friction to player vehicle
  if playerVeh and activeMudFriction < 0.98 then
    -- Send friction scale to vehicle Lua wheels controller
    local cmd = string.format("if wheels and wheels.wheels then for _, wd in pairs(wheels.wheels) do if wd.tireFrictionCoef then wd.tireFrictionCoef = %.2f end end end", activeMudFriction)
    pcall(function() playerVeh:queueLuaCommand(cmd) end)
  elseif playerVeh and activeMudFriction >= 0.98 then
    local cmd = "if wheels and wheels.wheels then for _, wd in pairs(wheels.wheels) do if wd.tireFrictionCoef then wd.tireFrictionCoef = 1.0 end end end"
    pcall(function() playerVeh:queueLuaCommand(cmd) end)
  end

  -- Karoo Scorcher thermal stress simulation
  if activePreset and activePreset.thermalStress and playerVeh then
    local vel = playerVeh.getVelocity and playerVeh:getVelocity():length() or 0
    if vel > 10.0 then
      -- Heavy engine load under extreme ambient heat warms coolant faster
      local cmd = "if powertrain and powertrain.getDevice('mainEngine') then local e = powertrain.getDevice('mainEngine'); if e.radiator and e.radiator.coolantTemperature then e.radiator.coolantTemperature = math.min(118, e.radiator.coolantTemperature + 0.1) end end"
      pcall(function() playerVeh:queueLuaCommand(cmd) end)
    end
  end
end

-- UI state representation
function M.getUiState()
  return {
    presets = M.PRESETS,
    activePreset = M.getActivePreset(),
    mudFriction = activeMudFriction,
    autoEnabled = autoWeatherEnabled
  }
end

function M.setAutoWeather(enabled)
  autoWeatherEnabled = enabled and true or false
  return autoWeatherEnabled
end

function M.reset()
  activePreset = nil
  activeMudFriction = 1.0
  lastPhysicsTick = 0
  autoWeatherEnabled = true
end

return M
