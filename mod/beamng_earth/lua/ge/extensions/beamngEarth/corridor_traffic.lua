-- BeamNG.Earth: African Freight Corridor Traffic & Wildlife Hazard Simulation
-- Manages regional highway traffic mixes (interlink b-doubles, Quantum minibus taxis, safari 4x4s)
-- and environmental wildlife/livestock crossing hazard zones near national parks and rural verges.

local M = {}
local places = require('beamngEarth/places')

-- Wildlife & Rural Hazard Zones Catalog
M.HAZARD_ZONES = {
  {
    id = 'kruger_fringe',
    name = 'Greater Kruger Wildlife Corridor',
    corridor = 'R40 / N4 Corridor (Mpumalanga / Limpopo)',
    lat = -24.9900,
    lon = 31.5900,
    radiusM = 35000,
    type = 'wildlife',
    hazard = 'Elephants, Impala & Giraffe crossings',
    speedLimitKmh = 60,
    icon = '🐘'
  },
  {
    id = 'chobe_transit',
    name = 'Chobe - Zambezi Migration Corridor',
    corridor = 'A33 Highway (Kasane / Kazungula)',
    lat = -17.8200,
    lon = 25.1500,
    radiusM = 25000,
    type = 'wildlife',
    hazard = 'Buffalo herds & African elephant migration',
    speedLimitKmh = 50,
    icon = '🦬'
  },
  {
    id = 'serengeti_plains',
    name = 'Serengeti - Mara Open Plains',
    corridor = 'B144 Arusha - Musoma Highway',
    lat = -2.3300,
    lon = 34.8300,
    radiusM = 40000,
    type = 'wildlife',
    hazard = 'Wildebeest, Zebra & migratory gazelle crossings',
    speedLimitKmh = 50,
    icon = '🦓'
  },
  {
    id = 'karoo_livestock',
    name = 'Great Karoo Unfenced Range',
    corridor = 'N1 Beaufort West - Colesberg',
    lat = -31.5000,
    lon = 23.5000,
    radiusM = 50000,
    type = 'livestock',
    hazard = 'Unfenced sheep & nocturnal kudu leaps across road',
    speedLimitKmh = 80,
    icon = '🦌'
  },
  {
    id = 'trans_kalahari_drift',
    name = 'Trans-Kalahari Desert Highway',
    corridor = 'A2 Jwaneng - Kang - Mamuno',
    lat = -23.7000,
    lon = 22.8000,
    radiusM = 60000,
    type = 'livestock',
    hazard = 'Free-roaming Brahman cattle and loose dune washouts',
    speedLimitKmh = 80,
    icon = '🐂'
  }
}

-- Regional Corridor Traffic Vehicle Archetypes
M.TRAFFIC_ARCHETYPES = {
  {
    model = 'us_semi',
    name = 'B-Double Interlink Freight Hauler',
    category = 'commercial',
    weight = 50,
    speedFactor = 0.85,
    icon = '🚛'
  },
  {
    model = 'van',
    name = 'Regional Commuter Minibus Taxi',
    category = 'commuter',
    weight = 30,
    speedFactor = 1.15, -- Minibus taxis drive briskly with frequent overtakes
    icon = '🚐'
  },
  {
    model = 'roamer',
    name = 'Overland Safari 4x4 Cruiser',
    category = 'overland',
    weight = 20,
    speedFactor = 0.95,
    icon = '🚙'
  }
}

local currentHazard = nil
local trafficDensity = 0.65 -- 0.0 (off) to 1.0 (rush hour)
local lastHazardCheck = 0
local warnedHazards = {}

-- Helper: Find nearest hazard zone
function M.findNearestHazard(lat, lon)
  if not lat or not lon then return nil, math.huge end
  local best, bestDist = nil, math.huge
  for _, hz in ipairs(M.HAZARD_ZONES) do
    local d = places.distance(lat, lon, hz.lat, hz.lon)
    if d < bestDist then
      best = hz
      bestDist = d
    end
  end
  return best, bestDist
end

-- Update loop: detects approach into wildlife/livestock hazard zones
function M.update(playerLat, playerLon, playerVeh)
  if not require('beamngEarth/logistics').enabled() then return false, 'OTBT logistics disabled' end
  if not playerLat or not playerLon then
    currentHazard = nil
    return
  end

  local now = os.time()
  if now - lastHazardCheck < 3 then return end
  lastHazardCheck = now

  local hz, dist = M.findNearestHazard(playerLat, playerLon)
  if hz and dist <= hz.radiusM then
    currentHazard = {
      zone = hz,
      distanceM = math.floor(dist + 0.5)
    }

    if not warnedHazards[hz.id] then
      warnedHazards[hz.id] = true
      if rawget(_G, 'ui_message') then
        pcall(ui_message, string.format("%s CAUTION: %s (%s). %s — Recommended max speed %d km/h!", hz.icon, hz.name, hz.corridor, hz.hazard, hz.speedLimitKmh), 8, 'beamngEarthTraffic')
      end
    end
  else
    currentHazard = nil
  end
end

-- Spawns or configures regional AI corridor traffic
function M.spawnCorridorTraffic(density)
  if not require('beamngEarth/logistics').enabled() then return false, 'OTBT logistics disabled' end
  density = tonumber(density) or trafficDensity
  trafficDensity = math.max(0.0, math.min(1.0, density))

  local gt = rawget(_G, 'gameplay_traffic')
  if gt and gt.setupTraffic then
    pcall(function()
      local amount = math.max(2, math.floor(trafficDensity * 8))
      gt.setupTraffic(amount, 0, 0)
    end)
  end

  if rawget(_G, 'ui_message') then
    pcall(ui_message, string.format("🚦 CORRIDOR TRAFFIC: Regional African freight & commuter flow active (Density: %d%%).", math.floor(trafficDensity * 100)), 6, 'beamngEarthTraffic')
  end

  return true, { density = trafficDensity }
end

-- UI State
function M.getUiState(playerLat, playerLon)
  local hz, dist = M.findNearestHazard(playerLat, playerLon)
  local inZone = hz and dist <= hz.radiusM

  return {
    density = trafficDensity,
    activeHazard = inZone and {
      id = hz.id,
      name = hz.name,
      corridor = hz.corridor,
      type = hz.type,
      hazard = hz.hazard,
      icon = hz.icon,
      speedLimitKmh = hz.speedLimitKmh,
      distanceM = math.floor(dist + 0.5)
    } or nil,
    hazardZones = M.HAZARD_ZONES,
    archetypes = M.TRAFFIC_ARCHETYPES
  }
end

function M.setDensity(val)
  if not require('beamngEarth/logistics').enabled() then return false, 'OTBT logistics disabled' end
  trafficDensity = math.max(0.0, math.min(1.0, tonumber(val) or 0.65))
  return trafficDensity
end

function M.reset()
  currentHazard = nil
  lastHazardCheck = 0
  warnedHazards = {}
end

return M
