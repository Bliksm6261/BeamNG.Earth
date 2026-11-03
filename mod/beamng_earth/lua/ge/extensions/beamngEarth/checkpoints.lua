-- BeamNG.Earth: Toll Plazas, Border Posts & Commercial Weigh Stations
-- Manages regional checkpoints across Southern & Eastern Africa (N1/N3/N4 freight corridors and cross-border customs).

local M = {}
local places = require('beamngEarth/places')

-- Checkpoint catalog
M.CHECKPOINTS = {
  -- BORDER POSTS (Cross-border customs & immigration)
  {
    id = 'border_beitbridge',
    type = 'border',
    name = 'Beitbridge Border Post',
    corridor = 'N1 / A4 Highway',
    countryA = 'South Africa 🇿🇦',
    countryB = 'Zimbabwe 🇿🇼',
    lat = -22.2173,
    lon = 29.9875,
    standardFee = 85,
    icon = '🛂'
  },
  {
    id = 'border_lebombo',
    type = 'border',
    name = 'Lebombo / Ressano Garcia Border',
    corridor = 'N4 Maputo Corridor',
    countryA = 'South Africa 🇿🇦',
    countryB = 'Mozambique 🇲🇿',
    lat = -25.4442,
    lon = 31.9908,
    standardFee = 75,
    icon = '🛂'
  },
  {
    id = 'border_chirundu',
    type = 'border',
    name = 'Chirundu Border Post',
    corridor = 'Zambezi River Bridge (T2)',
    countryA = 'Zimbabwe 🇿🇼',
    countryB = 'Zambia 🇿🇲',
    lat = -16.0389,
    lon = 28.8522,
    standardFee = 95,
    icon = '🛂'
  },
  {
    id = 'border_kazungula',
    type = 'border',
    name = 'Kazungula Quadripoint Border',
    corridor = 'Kazungula Bridge',
    countryA = 'Botswana 🇧🇼',
    countryB = 'Zambia 🇿🇲',
    lat = -17.7889,
    lon = 25.2639,
    standardFee = 90,
    icon = '🛂'
  },
  {
    id = 'border_nakonde',
    type = 'border',
    name = 'Nakonde / Tunduma Border',
    corridor = 'Great North Road (T2)',
    countryA = 'Zambia 🇿🇲',
    countryB = 'Tanzania 🇹🇿',
    lat = -9.3300,
    lon = 32.7667,
    standardFee = 110,
    icon = '🛂'
  },
  {
    id = 'border_maseru',
    type = 'border',
    name = 'Maseru Bridge Border',
    corridor = 'N8 Highway / Mohokare River',
    countryA = 'South Africa 🇿🇦',
    countryB = 'Lesotho 🇱🇸',
    lat = -29.2967,
    lon = 27.4667,
    standardFee = 50,
    icon = '🛂'
  },
  {
    id = 'border_martins_drift',
    type = 'border',
    name = 'Martins Drift Border Post',
    corridor = 'N11 / Limpopo Crossing',
    countryA = 'South Africa 🇿🇦',
    countryB = 'Botswana 🇧🇼',
    lat = -22.9983,
    lon = 27.9400,
    standardFee = 65,
    icon = '🛂'
  },

  -- TOLL PLAZAS (Class 4 Commercial Heavy Vehicle Tolls)
  {
    id = 'toll_mooi_river',
    type = 'toll',
    name = 'Mooi River Toll Plaza',
    corridor = 'N3 Freight Corridor (KZN Midlands)',
    lat = -29.2064,
    lon = 30.0053,
    standardFee = 38,
    icon = '💳'
  },
  {
    id = 'toll_tugela',
    type = 'toll',
    name = 'Tugela Toll Plaza',
    corridor = 'N3 Drakensberg Escarpment',
    lat = -28.6756,
    lon = 29.7433,
    standardFee = 32,
    icon = '💳'
  },
  {
    id = 'toll_kranskop',
    type = 'toll',
    name = 'Kranskop Toll Plaza',
    corridor = 'N1 North Highway (Limpopo)',
    lat = -24.7833,
    lon = 28.5333,
    standardFee = 45,
    icon = '💳'
  },
  {
    id = 'toll_pumula',
    type = 'toll',
    name = 'Pumula Toll Plaza',
    corridor = 'N2 South Coast Highway',
    lat = -30.6333,
    lon = 30.5167,
    standardFee = 24,
    icon = '💳'
  },
  {
    id = 'toll_capricorn',
    type = 'toll',
    name = 'Capricorn Toll Plaza',
    corridor = 'N1 Polokwane North',
    lat = -23.5167,
    lon = 29.7333,
    standardFee = 30,
    icon = '💳'
  },
  {
    id = 'toll_machado',
    type = 'toll',
    name = 'Machado Toll Plaza',
    corridor = 'N4 Mpumalanga Highlands',
    lat = -25.6833,
    lon = 30.2500,
    standardFee = 40,
    icon = '💳'
  },

  -- WEIGH STATIONS (Commercial Axle Weight Inspection - 34,000 kg legal limit)
  {
    id = 'weigh_heidelberg',
    type = 'weigh',
    name = 'Heidelberg Traffic Control & Weighbridge',
    corridor = 'N3 Southbound',
    lat = -26.5167,
    lon = 28.3500,
    maxGrossKg = 34000,
    icon = '⚖️'
  },
  {
    id = 'weigh_mantsole',
    type = 'weigh',
    name = 'Mantsole Weighbridge',
    corridor = 'N1 Northbound',
    lat = -24.9667,
    lon = 28.3833,
    maxGrossKg = 34000,
    icon = '⚖️'
  },
  {
    id = 'weigh_midway',
    type = 'weigh',
    name = 'Midway Weighbridge',
    corridor = 'N4 Middelburg',
    lat = -25.7500,
    lon = 29.4667,
    maxGrossKg = 34000,
    icon = '⚖️'
  },
  {
    id = 'weigh_beitbridge',
    type = 'weigh',
    name = 'Beitbridge North Commercial Weigh Station',
    corridor = 'A4 Beitbridge Approach',
    lat = -22.2050,
    lon = 29.9920,
    maxGrossKg = 34000,
    icon = '⚖️'
  }
}

-- Runtime checkpoint state
local activeNearby = nil
local lastClearedId = nil
local lastClearedTime = 0
local approachWarned = {}
local stopDuration = 0

-- Helper: Find nearest checkpoint
function M.findNearestCheckpoint(lat, lon)
  if not lat or not lon then return nil, math.huge end
  local best, bestDist = nil, math.huge
  for _, cp in ipairs(M.CHECKPOINTS) do
    local d = places.distance(lat, lon, cp.lat, cp.lon)
    if d < bestDist then
      best = cp
      bestDist = d
    end
  end
  return best, bestDist
end

-- Get freight reference safely
local function getFreight()
  local fr = rawget(_G, 'beamngEarth_freight') or (extensions and extensions.beamngEarth_freight)
  if not fr then pcall(function() fr = require('beamngEarth/freight') end) end
  return fr
end

-- Broadcast checkpoint clearance event
local function broadcastCheckpoint(payload)
  local mps = rawget(_G, 'beamngEarth_mpsession') or (extensions and extensions.beamngEarth_mpsession)
  if mps and mps.isSessionActive and mps.isSessionActive() and mps.sendLogisticsEvent then
    pcall(mps.sendLogisticsEvent, payload)
  elseif rawget(_G, 'TriggerServerEvent') then
    local data = payload
    if rawget(_G, 'jsonEncode') then data = jsonEncode(payload) end
    pcall(TriggerServerEvent, 'bngeLogistics', data)
  end
end

-- Process checkpoint clearance
function M.clearCheckpoint(cpId, playerLat, playerLon)
  local cp = nil
  for _, c in ipairs(M.CHECKPOINTS) do
    if c.id == cpId then cp = c; break end
  end
  if not cp then return false, 'Checkpoint not found' end

  local fr = getFreight()
  local comp = fr and fr.getCompany and fr.getCompany() or { vault = 10000, reputation = 100 }
  local activeContract = fr and fr.getActiveContract and fr.getActiveContract()

  local result = {
    checkpointId = cp.id,
    type = cp.type,
    name = cp.name,
    feePaid = 0,
    finePaid = 0,
    reputationDelta = 0,
    message = '',
    exempt = false
  }

  if cp.type == 'toll' then
    local fee = cp.standardFee or 35
    -- HazMat surcharge +25%
    if activeContract and activeContract.cargo and activeContract.cargo.hazmat then
      fee = math.floor(fee * 1.25)
    end
    -- Commercial fleet reputation rebate (-10% if rep >= 90)
    if (comp.reputation or 100) >= 90 then
      fee = math.floor(fee * 0.90)
    end

    if (comp.vault or 0) < fee then
      return false, string.format("Insufficient funds in company vault for toll ($%d needed)", fee)
    end

    comp.vault = comp.vault - fee
    result.feePaid = fee
    result.message = string.format("💳 TOLL CLEARED: $%d toll fee deducted. Gate open!", fee)

  elseif cp.type == 'border' then
    local hasCarnet = fr and fr.hasUpgrade and fr.hasUpgrade('license_cross_border')
    if hasCarnet then
      -- SADC Carnet Carrier License waives border fee and grants +2 reputation
      result.exempt = true
      result.feePaid = 0
      result.reputationDelta = 2
      comp.reputation = math.min(100, (comp.reputation or 100) + 2)
      result.message = string.format("🛂 SADC CARNET CLEARANCE: Cross-border carrier license verified! $0 fee, +2 Rep.", cp.name)
    else
      local fee = cp.standardFee or 80
      if (comp.vault or 0) < fee then
        return false, string.format("Insufficient funds for cross-border clearance ($%d needed)", fee)
      end
      comp.vault = comp.vault - fee
      result.feePaid = fee
      result.message = string.format("🛂 BORDER CLEARED: $%d customs duty paid. Welcome to %s!", fee, cp.countryB or 'destination country')
    end

  elseif cp.type == 'weigh' then
    -- Determine total gross mass
    local grossKg = 18000 -- Tare weight of tractor + empty trailer
    if activeContract and activeContract.slots and activeContract.slots[1] then
      grossKg = grossKg + (activeContract.slots[1].weightKg or 15000)
    end

    local maxLegalKg = cp.maxGrossKg or 34000
    if grossKg > maxLegalKg then
      local hasHeavyHaul = fr and fr.hasUpgrade and fr.hasUpgrade('license_heavy_haul')
      if hasHeavyHaul then
        result.exempt = true
        result.finePaid = 0
        result.message = string.format("⚖️ WEIGH-IN PASSED: %s kg (Heavy Haul Carrier Permit Verified). Axle clearance approved!", grossKg)
      else
        local fine = 2500
        comp.vault = math.max(0, (comp.vault or 0) - fine)
        comp.reputation = math.max(0, (comp.reputation or 100) - 5)
        result.finePaid = fine
        result.reputationDelta = -5
        result.message = string.format("⚠️ OVERWEIGHT CITATION: %s kg exceeds 34,000 kg legal limit without Heavy Haul permit! -$%d, -5 Rep.", grossKg, fine)
      end
    else
      result.exempt = true
      result.message = string.format("⚖️ WEIGH-IN PASSED: Axle weight %s kg within legal limits (<= 34,000 kg). Proceed!", grossKg)
    end
  end

  if fr and fr.saveState then pcall(fr.saveState) end

  lastClearedId = cp.id
  lastClearedTime = os.time()

  broadcastCheckpoint({
    type = 'checkpoint_clear',
    checkpointId = cp.id,
    checkpointType = cp.type,
    name = cp.name,
    fee = result.feePaid,
    fine = result.finePaid,
    company = comp
  })

  if rawget(_G, 'ui_message') then
    pcall(ui_message, result.message, 6, 'beamngEarthCheckpoint')
  end

  return true, result
end

-- Update per-frame/tick (called by freight.lua)
function M.update(playerLat, playerLon, playerVeh)
  if not playerLat or not playerLon then
    activeNearby = nil
    return
  end

  local cp, dist = M.findNearestCheckpoint(playerLat, playerLon)
  if not cp or dist > 150 then
    activeNearby = nil
    stopDuration = 0
    return
  end

  local now = os.time()
  local speed = playerVeh and playerVeh.getVelocity and playerVeh:getVelocity():length() or 0

  -- Approach warning (between 40m and 120m)
  if dist <= 120 and dist > 40 and not approachWarned[cp.id] then
    approachWarned[cp.id] = true
    if rawget(_G, 'ui_message') then
      pcall(ui_message, string.format("%s Approaching %s (%s). Slow down for inspection lane.", cp.icon, cp.name, cp.corridor or ''), 6, 'beamngEarthCheckpoint')
    end
  elseif dist > 150 then
    approachWarned[cp.id] = nil
  end

  -- In barrier zone (< 40m)
  if dist <= 40 then
    activeNearby = {
      checkpoint = cp,
      distanceM = math.floor(dist + 0.5),
      canClear = (dist <= 35) and (lastClearedId ~= cp.id or (now - lastClearedTime > 60))
    }

    -- Auto-clear if vehicle stopped in lane for > 2 seconds
    if activeNearby.canClear and speed < 1.0 then
      stopDuration = stopDuration + 0.5
      if stopDuration >= 2.0 then
        stopDuration = 0
        M.clearCheckpoint(cp.id, playerLat, playerLon)
      end
    else
      stopDuration = 0
    end
  else
    activeNearby = {
      checkpoint = cp,
      distanceM = math.floor(dist + 0.5),
      canClear = false
    }
  end
end

-- Get state for UI
function M.getUiState(playerLat, playerLon)
  local cp, dist = M.findNearestCheckpoint(playerLat, playerLon)
  local inRange = cp and dist <= 150
  return {
    nearby = inRange and {
      id = cp.id,
      type = cp.type,
      name = cp.name,
      corridor = cp.corridor,
      countryA = cp.countryA,
      countryB = cp.countryB,
      distanceM = math.floor(dist + 0.5),
      fee = cp.standardFee or 0,
      icon = cp.icon,
      canClear = (dist <= 35) and (lastClearedId ~= cp.id or (os.time() - lastClearedTime > 60))
    } or nil,
    allCheckpoints = M.CHECKPOINTS
  }
end

function M.reset()
  activeNearby = nil
  lastClearedId = nil
  lastClearedTime = 0
  approachWarned = {}
  stopDuration = 0
end

return M
