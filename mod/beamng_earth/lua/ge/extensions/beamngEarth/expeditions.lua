-- Overlanding Expeditions & Home Base System for BeamNG.Earth (OTBT Edition).
-- Manages curated overlanding tours, 4x4 trail ratings, sequential checkpoint progression,
-- milestone discoveries, trail passport stamps, vehicle rig spawning, and Home Base HQ operations.
local M = {}

local places = require('beamngEarth/places')
local gps = require('beamngEarth/gps')

M.FILE = '/settings/beamngEarth_expeditions.json'
M.CHECKPOINT_ARRIVE_M = 45 -- within 45m: checkpoint reached

local ledgerRev = -1
local function multiplayer()
  local session=require('beamngEarth/mpsession')
  return session.isSessionActive and session.isSessionActive()
end

local function broadcastExpedition(payload)
  return require('beamngEarth/mpsession').sendLogisticsEvent(payload)
end

-- Curated Overlanding Expeditions
M.TOURS = {
  {
    id = 'sani_pass',
    name = 'Sani Pass 4x4 Mountain Ascent',
    region = 'South Africa to Lesotho',
    grade = 4,
    gradeLabel = 'Grade 4 - Extreme Mountain Pass',
    distanceKm = 45,
    terrain = 'Steep rocky switchbacks, high altitude, cliff ledges',
    description = 'The legendary mountain pass climbing from the Underberg foothills to the summit of the Drakensberg escarpment, finishing at the highest pub in Africa.',
    recommendedVehicle = 'High-clearance 4x4 with low-range transfer case and all-terrain tires',
    checkpoints = {
      { name = 'Underberg Valley Trailhead', lat = -29.7892, lon = 29.4975, desc = 'Base camp and tire air-down station' },
      { name = 'South Africa Border Post', lat = -29.6105, lon = 29.3510, desc = 'Passport clearance before the rocky climb' },
      { name = 'The Black Switchbacks', lat = -29.5930, lon = 29.2990, desc = 'Hairpin turns over loose shale and rock' },
      { name = 'Sani Top Summit (2,874m)', lat = -29.5868, lon = 29.2886, desc = 'Highest Pub in Africa overlooking the gorge' }
    }
  },
  {
    id = 'namib_dunes',
    name = 'Namib Desert & Dune 45 Expedition',
    region = 'Namibia',
    grade = 3,
    gradeLabel = 'Grade 3 - Deep Sand & Desert Trails',
    distanceKm = 180,
    terrain = 'Desert gravel highways, soft sand tracks, iconic red dunes',
    description = 'Cross the ancient Namib desert from Solitaire down through Sesriem Canyon to the towering star dunes of Sossusvlei.',
    recommendedVehicle = '4x4 SUV or bakkie with sand recovery boards and deflated tires',
    checkpoints = {
      { name = 'Solitaire Desert Outpost', lat = -23.8940, lon = 16.0050, desc = 'Famous desert bakery and fuel depot' },
      { name = 'Sesriem Canyon Gateway', lat = -24.5160, lon = 15.7990, desc = 'Entrance gate into the Namib-Naukluft Park' },
      { name = 'Dune 45 Red Star Dune', lat = -24.7348, lon = 15.4699, desc = 'The iconic 85-meter reddish-orange desert dune' }
    }
  },
  {
    id = 'okavango_zambezi',
    name = 'Okavango to Victoria Falls Safari',
    region = 'Botswana to Zimbabwe',
    grade = 3,
    gradeLabel = 'Grade 3 - Bushveld & Deep Sand Two-Track',
    distanceKm = 360,
    terrain = 'Kalahari sand ruts, bushveld riverbanks, wildlife corridors',
    description = 'Traverse from the fringes of the Okavango Delta through the salt pans and Chobe riverfront to the thundering Victoria Falls.',
    recommendedVehicle = 'Long-range expedition rig with dual fuel tanks and snorkel',
    checkpoints = {
      { name = 'Maun Okavango Base', lat = -19.9833, lon = 23.4167, desc = 'The safari capital on the Thamalakane River' },
      { name = 'Nata Pan Oasis', lat = -20.2100, lon = 26.1800, desc = 'Edge of the great Makgadikgadi Salt Pans' },
      { name = 'Chobe Riverfront Transit', lat = -17.8100, lon = 25.1500, desc = 'Kasane elephant trail along the Zambezi' },
      { name = 'Victoria Falls Mosi-oa-Tunya', lat = -17.9318, lon = 25.8307, desc = 'The Smoke that Thunders viewpoint' }
    }
  },
  {
    id = 'richtersveld_crawl',
    name = 'Richtersveld Transfrontier Wilderness Crawl',
    region = 'Northern Cape, South Africa',
    grade = 5,
    gradeLabel = 'Grade 5 - Hardcore Rock Crawling',
    distanceKm = 85,
    terrain = 'Jagged mountain desert canyons, dry river boulder fields, extreme heat',
    description = 'South Africa\'s most rugged off-road wilderness. Slow-speed rock crawling through jagged volcanic mountain scenery along the Orange River.',
    recommendedVehicle = 'Locked differentials, heavy rock sliders, and 33"+ mud-terrain tires',
    checkpoints = {
      { name = 'Sendelingsdrift Pontoon Depot', lat = -28.1167, lon = 16.8833, desc = 'Border crossing and river basecamp' },
      { name = 'Akkedis Pass Canyon', lat = -28.2100, lon = 17.0200, desc = 'Narrow boulder-strewn canyon descent' },
      { name = 'Tatasberg Granite Monoliths', lat = -28.3200, lon = 17.1800, desc = 'Gigantic weather-sculpted granite boulders' }
    }
  },
  {
    id = 'chapmans_cape_point',
    name = 'Chapman\'s Peak & Cape Peninsula Explorer',
    region = 'Western Cape, South Africa',
    grade = 1,
    gradeLabel = 'Grade 1 - Scenic Coastal Pass',
    distanceKm = 65,
    terrain = 'Carved cliffside asphalt, ocean drop-offs, coastal nature reserve tracks',
    description = 'One of the world\'s most breathtaking scenic drives, hugging the vertical Atlantic cliffs before heading into Cape of Good Hope nature reserve.',
    recommendedVehicle = 'Any vehicle or overland cruiser',
    checkpoints = {
      { name = 'Hout Bay Fishing Harbour', lat = -34.0500, lon = 18.3550, desc = 'Harbor entry and trailhead' },
      { name = 'Chapman\'s Peak Marine Lookout', lat = -34.0886, lon = 18.3606, desc = 'High cliff overhang over the Atlantic surf' },
      { name = 'Scarborough Atlantic Beach Track', lat = -34.1980, lon = 18.3750, desc = 'Windswept coastal road and dunes' },
      { name = 'Cape Point Lighthouse', lat = -34.3570, lon = 18.4975, desc = 'The dramatic southwestern tip of Africa' }
    }
  }
}

-- Major city bases across the 10 OTBT countries
M.CITY_BASES = {
  { id = 'jhb', name = 'Johannesburg (Central Base)', country = 'South Africa', lat = -26.2041, lon = 28.0473 },
  { id = 'cpt', name = 'Cape Town (Table Bay Base)', country = 'South Africa', lat = -33.9249, lon = 18.4241 },
  { id = 'dur', name = 'Durban (Port Gateway Base)', country = 'South Africa', lat = -29.8587, lon = 31.0218 },
  { id = 'pta', name = 'Pretoria (Capital Base)', country = 'South Africa', lat = -25.7461, lon = 28.1881 },
  { id = 'plz', name = 'Gqeberha / Port Elizabeth (Eastern Cape)', country = 'South Africa', lat = -33.9608, lon = 25.6022 },
  { id = 'bfn', name = 'Bloemfontein (Free State Hub)', country = 'South Africa', lat = -29.0852, lon = 26.1596 },
  { id = 'nlp', name = 'Mbombela / Nelspruit (Kruger Base)', country = 'South Africa', lat = -25.4658, lon = 30.9853 },
  { id = 'grg', name = 'George (Garden Route Base)', country = 'South Africa', lat = -33.9630, lon = 22.4617 },
  { id = 'wdh', name = 'Windhoek (Namibia HQ)', country = 'Namibia', lat = -22.5609, lon = 17.0658 },
  { id = 'swk', name = 'Swakopmund (Skeleton Coast Base)', country = 'Namibia', lat = -22.6784, lon = 14.5266 },
  { id = 'gbe', name = 'Gaborone (Botswana Capital Base)', country = 'Botswana', lat = -24.6282, lon = 25.9231 },
  { id = 'mub', name = 'Maun (Okavango Delta Base)', country = 'Botswana', lat = -19.9833, lon = 23.4167 },
  { id = 'vfa', name = 'Victoria Falls (Zambezi Base)', country = 'Zimbabwe', lat = -17.9318, lon = 25.8307 },
  { id = 'hre', name = 'Harare (Zimbabwe Capital Base)', country = 'Zimbabwe', lat = -17.8252, lon = 31.0335 },
  { id = 'lvi', name = 'Livingstone (Zambia Outpost)', country = 'Zambia', lat = -17.8419, lon = 25.8543 },
  { id = 'mpm', name = 'Maputo (Mozambique Coast Base)', country = 'Mozambique', lat = -25.9692, lon = 32.5732 },
  { id = 'qwe', name = 'Mbabane (Eswatini Mountain Base)', country = 'Eswatini', lat = -26.3167, lon = 31.1333 },
  { id = 'msu', name = 'Maseru (Lesotho Highland Base)', country = 'Lesotho', lat = -29.3151, lon = 27.4869 },
  { id = 'llw', name = 'Lilongwe (Lake Malawi Hub)', country = 'Malawi', lat = -13.9626, lon = 33.7741 },
  { id = 'dar', name = 'Dar es Salaam (Tanzania Coast Base)', country = 'Tanzania', lat = -6.7924, lon = 39.2083 },
  { id = 'ark', name = 'Arusha (Serengeti Safari Base)', country = 'Tanzania', lat = -3.3869, lon = 36.6830 }
}

-- Persisted State: Home Base and Expedition Passport
local state = {
  homeBase = {
    name = 'OTBT Expedition HQ (Johannesburg)',
    lat = -26.2041,
    lon = 28.0473,
    kind = 'city_base',
    facilityTier = 1
  },
  passport = {
    stamps = {}, -- tourId -> { completedAt, fastestTimeS }
    totalOffroadKm = 0,
    milestonesDiscovered = 0
  },
  activeTour = nil,
  checkpointIndex = 1
}

function M.getHomeBase()
  return state.homeBase
end

function M.getPassport()
  return state.passport
end

function M.getActiveTour()
  return state.activeTour
end

function M.getCheckpointIndex()
  return state.checkpointIndex
end

-- Load state from JSON
function M.loadState()
  if rawget(_G, 'jsonReadFile') then
    local data = jsonReadFile(M.FILE)
    if type(data) == 'table' and data.homeBase then
      state = data
      return true
    end
  end
  return false
end

-- Save state to JSON
function M.saveState()
  if rawget(_G, 'jsonWriteFile') then
    return jsonWriteFile(M.FILE, state, true)
  end
  return false
end

-- Set Home Base location (address-specific, coordinates, or major city)
function M.setHomeBase(name, lat, lon, kind, address)
  lat, lon = tonumber(lat), tonumber(lon)
  if not lat or not lon then return false, 'Invalid coordinates' end
  state.homeBase = {
    name = name or 'My Overland Base',
    lat = lat,
    lon = lon,
    kind = kind or 'custom',
    address = address or nil,
    facilityTier = state.homeBase.facilityTier or 1
  }
  M.saveState()
  return true, state.homeBase
end

-- Set Home Base from a preset major city
function M.setHomeBaseByCity(cityId)
  for _, c in ipairs(M.CITY_BASES) do
    if c.id == cityId then
      return M.setHomeBase(c.name, c.lat, c.lon, 'city_base')
    end
  end
  return false, 'City base not found'
end

-- Teleport player directly to Home Base
function M.teleportToHomeBase()
  local hb = state.homeBase
  if not hb or not hb.lat then return false, 'No home base defined' end
  return places.goTo(hb.lat, hb.lon, hb.name)
end

-- Start or plan an overlanding tour (sets transit to trailhead)
function M.startExpedition(tourId)
  if multiplayer() then return broadcastExpedition({type='expedition_start',expeditionId=tourId}), 'pending' end
  local tour = nil
  for _, t in ipairs(M.TOURS) do
    if t.id == tourId then tour = t; break end
  end
  if not tour then return false, 'Tour not found' end

  -- Grade 5 extreme trail certification check
  if tour.grade and tour.grade >= 5 then
    local fr = rawget(_G, 'beamngEarth_freight') or (extensions and extensions.beamngEarth_freight)
    if not fr then pcall(function() fr = require('beamngEarth/freight') end) end
    if fr and fr.hasUpgrade and not fr.hasUpgrade('cert_rock_crawl') then
      return false, 'Requires Extreme Rock Crawling Certification ($18,000 in Fleet Upgrades)'
    end
  end

  state.activeTour = {
    id = tour.id,
    name = tour.name,
    region = tour.region,
    grade = tour.grade,
    gradeLabel = tour.gradeLabel,
    distanceKm = tour.distanceKm,
    terrain = tour.terrain,
    description = tour.description,
    recommendedVehicle = tour.recommendedVehicle,
    checkpoints = tour.checkpoints,
    status = 'transit', -- 'transit' (driving to trailhead) -> 'active' (on the trail)
    atTrailhead = false,
    distToTrailheadM = math.huge,
    plannedAt = os.time(),
    startedAt = nil
  }
  state.checkpointIndex = 1

  -- Route GPS to Trailhead (checkpoint 1)
  local trailhead = tour.checkpoints[1]
  if gps and gps.setDestination then
    gps.setDestination(trailhead.lat, trailhead.lon, trailhead.name)
  end

  if rawget(_G, 'ui_message') then
    pcall(ui_message, string.format("🧭 Trip Planned: %s\nDrive to the trailhead at %s to begin!", tour.name, trailhead.name), 8, 'beamngEarthExpedition')
  end

  broadcastExpedition({
    type = 'expedition_start',
    expedition = state.activeTour
  })

  M.saveState()
  return true, state.activeTour
end

-- Teleport directly to the active tour's trailhead
function M.fastTravelToTrailhead()
  local tour = state.activeTour
  if not tour or not tour.checkpoints or not tour.checkpoints[1] then
    return false, 'No active trip planned'
  end
  local th = tour.checkpoints[1]
  return places.goTo(th.lat, th.lon, th.name)
end

-- Officially begin the expedition once at the trailhead
function M.beginTrail()
  local tour = state.activeTour
  if not tour then return false, 'No active trip' end

  if multiplayer() then return broadcastExpedition({type='expedition_stage',expeditionId=tour.id,stageIndex=2}), 'pending' end

  tour.status = 'active'
  tour.startedAt = os.time()
  state.checkpointIndex = 2 -- first trail milestone after trailhead

  local nextChk = tour.checkpoints[state.checkpointIndex]
  if nextChk and gps and gps.setDestination then
    gps.setDestination(nextChk.lat, nextChk.lon, nextChk.name)
  end

  if rawget(_G, 'ui_message') then
    pcall(ui_message, string.format("⭐ EXPEDITION UNDERWAY!\nStage 1: Heading to %s", nextChk.name), 9, 'beamngEarthExpedition')
  end

  broadcastExpedition({
    type = 'expedition_stage',
    expeditionId = tour.id,
    stage = state.checkpointIndex,
    status = 'active'
  })

  M.saveState()
  return true, tour
end

-- Abandon active expedition
function M.abandonExpedition()
  if not state.activeTour then return false end
  local tourId = state.activeTour.id
  if multiplayer() then return broadcastExpedition({type='abandon_expedition',expeditionId=tourId}), 'pending' end
  state.activeTour = nil
  state.checkpointIndex = 1
  if gps and gps.clear then pcall(gps.clear) end
  broadcastExpedition({
    type = 'abandon_expedition',
    expeditionId = tourId
  })
  M.saveState()
  return true
end

-- Advance to next checkpoint or complete tour
function M.advanceCheckpoint()
  local tour = state.activeTour
  if not tour or tour.status ~= 'active' then return false end

  if multiplayer() then
    if state.checkpointIndex < #tour.checkpoints then
      return broadcastExpedition({type='expedition_stage',expeditionId=tour.id,stageIndex=state.checkpointIndex+1}), 'pending'
    end
    return broadcastExpedition({type='expedition_complete',expeditionId=tour.id}), 'pending'
  end
  local currentChk = tour.checkpoints[state.checkpointIndex]
  state.passport.milestonesDiscovered = (state.passport.milestonesDiscovered or 0) + 1

  if state.checkpointIndex < #tour.checkpoints then
    -- Advance to next milestone
    state.checkpointIndex = state.checkpointIndex + 1
    local nextChk = tour.checkpoints[state.checkpointIndex]

    if gps and gps.setDestination then
      gps.setDestination(nextChk.lat, nextChk.lon, nextChk.name)
    end

    if rawget(_G, 'ui_message') then
      pcall(ui_message, string.format("⭐ Milestone Reached: %s!\nNext Stage: %s", currentChk.name, nextChk.name), 8, 'beamngEarthExpedition')
    end

    broadcastExpedition({
      type = 'expedition_stage',
      expeditionId = tour.id,
      stage = state.checkpointIndex,
      status = 'active'
    })

    M.saveState()
    return true, 'advanced', nextChk
  else
    -- Tour Complete!
    local durS = os.time() - (tour.startedAt or os.time())
    state.passport.stamps[tour.id] = {
      completedAt = os.time(),
      durationSeconds = durS
    }
    state.passport.totalOffroadKm = (state.passport.totalOffroadKm or 0) + tour.distanceKm

    if rawget(_G, 'ui_message') then
      pcall(ui_message, string.format("🏆 EXPEDITION COMPLETED: %s!\nPassport Stamp Earned!", tour.name), 10, 'beamngEarthExpedition')
    end

    broadcastExpedition({
      type = 'expedition_complete',
      expeditionId = tour.id,
      stamp = state.passport.stamps[tour.id]
    })

    state.activeTour = nil
    state.checkpointIndex = 1
    M.saveState()
    return true, 'completed', tour
  end
end

-- Spawn a ready-to-roll 4x4 Overland Rig (Gavril Roamer 4x4)
function M.spawnOverlandRig()
  local pVeh = rawget(_G, 'getPlayerVehicle') and getPlayerVehicle(0)
  local pos = pVeh and pVeh:getPosition() or vec3(0, 0, 50)
  local rot = pVeh and quat(0, 0, 1, 0) * quat(pVeh:getRefNodeRotation()) or quat(0, 0, 0, 1)

  if rawget(_G, 'core_vehicles') and core_vehicles.spawnNewVehicle then
    local ok, rig = pcall(core_vehicles.spawnNewVehicle, 'roamer', {
      pos = vec3(pos.x + 3, pos.y + 3, pos.z + 0.5),
      rot = rot,
      autoEnterVehicle = true
    })
    return ok, rig
  end
  return false, 'core_vehicles unavailable'
end

-- Spawn a Commercial Semi Truck (Gavril T-Series)
function M.spawnSemiTruck()
  local pVeh = rawget(_G, 'getPlayerVehicle') and getPlayerVehicle(0)
  local pos = pVeh and pVeh:getPosition() or vec3(0, 0, 50)
  local rot = pVeh and quat(0, 0, 1, 0) * quat(pVeh:getRefNodeRotation()) or quat(0, 0, 0, 1)

  if rawget(_G, 'core_vehicles') and core_vehicles.spawnNewVehicle then
    local ok, truck = pcall(core_vehicles.spawnNewVehicle, 'us_semi', {
      pos = vec3(pos.x + 4, pos.y + 4, pos.z + 0.5),
      rot = rot,
      autoEnterVehicle = true
    })
    return ok, truck
  end
  return false, 'core_vehicles unavailable'
end

-- Frame update loop: monitors distance to trailhead or active checkpoint
local lastChkDist = nil

function M.update(playerLat, playerLon)
  local tour = state.activeTour
  if not tour or not playerLat or not playerLon then return end

  if tour.status == 'transit' then
    local trailhead = tour.checkpoints[1]
    if trailhead then
      local distM = places.distance(playerLat, playerLon, trailhead.lat, trailhead.lon)
      tour.distToTrailheadM = distM
      if distM <= 100 then
        if not tour.atTrailhead then
          tour.atTrailhead = true
          if rawget(_G, 'ui_message') then
            pcall(ui_message, string.format("📍 Arrived at Trailhead: %s!\nOpen OTBT HQ (M) to begin the expedition.", trailhead.name), 8, 'beamngEarthExpedition')
          end
        end
      else
        tour.atTrailhead = false
      end
    end
  elseif tour.status == 'active' then
    local chk = tour.checkpoints[state.checkpointIndex]
    if not chk then return end

    local distM = places.distance(playerLat, playerLon, chk.lat, chk.lon)
    lastChkDist = distM

    if distM <= M.CHECKPOINT_ARRIVE_M then
      M.advanceCheckpoint()
    end
  end
end

-- UI State payload for the unified hub
function M.getUiState(playerLat, playerLon)
  local tour = state.activeTour
  local currentChk = tour and tour.checkpoints[state.checkpointIndex]
  local distToChk = nil
  if currentChk and playerLat and playerLon then
    distToChk = places.distance(playerLat, playerLon, currentChk.lat, currentChk.lon)
  end

  local fr = rawget(_G, 'beamngEarth_freight') or (extensions and extensions.beamngEarth_freight)
  if not fr then pcall(function() fr = require('beamngEarth/freight') end) end

  local toursWithLocks = {}
  for _, t in ipairs(M.TOURS) do
    local isLocked = false
    local lockReason = nil
    if t.grade and t.grade >= 5 and fr and fr.hasUpgrade and not fr.hasUpgrade('cert_rock_crawl') then
      isLocked = true
      lockReason = 'Requires Grade 5 Rock Crawling Certification ($18,000)'
    end
    toursWithLocks[#toursWithLocks + 1] = {
      id = t.id,
      name = t.name,
      region = t.region,
      grade = t.grade,
      gradeLabel = t.gradeLabel,
      distanceKm = t.distanceKm,
      terrain = t.terrain,
      description = t.description,
      recommendedVehicle = t.recommendedVehicle,
      checkpoints = t.checkpoints,
      locked = isLocked,
      lockReason = lockReason
    }
  end

  return {
    homeBase = state.homeBase,
    cityBases = M.CITY_BASES,
    passport = state.passport,
    tours = toursWithLocks,
    activeTour = tour,
    checkpointIndex = state.checkpointIndex,
    currentCheckpoint = currentChk,
    distanceToCheckpointM = distToChk,
    atTrailhead = tour and tour.atTrailhead,
    isTransit = tour and tour.status == 'transit'
  }
end

-- Handle remote BeamMP expedition events
function M.onRemoteExpedition(msg)
  if type(msg) ~= 'table' or type(msg.type) ~= 'string' then return end

  if msg.type == 'ledger_state' then
    if msg.rev and msg.rev <= ledgerRev then return end
    ledgerRev = msg.rev or ledgerRev
    state.activeTour = msg.expedition
    state.checkpointIndex = msg.expedition and msg.expedition.stageIndex or 1
    if msg.intent == 'expedition_complete' and msg.expeditionId then
      state.passport.stamps[msg.expeditionId] = {completedAt=os.time()}
    end
    local chk = state.activeTour and state.activeTour.checkpoints[state.checkpointIndex]
    if chk and gps and gps.setDestination then gps.setDestination(chk.lat,chk.lon,chk.name) end
    M.saveState()
    return
  end
  if msg.type == 'sync_state' then
    ledgerRev = msg.rev or -1
    state.activeTour = nil
    if msg.state and msg.state.activeExpedition ~= nil then
      state.activeTour = msg.state.activeExpedition
      state.checkpointIndex = state.activeTour.stageIndex or 1
      M.saveState()
    end
    return
  end

  if msg.type == 'expedition_start' then
    if type(msg.expedition) == 'table' then
      state.activeTour = msg.expedition
      state.checkpointIndex = 1
      M.saveState()
      local trailhead = msg.expedition.checkpoints and msg.expedition.checkpoints[1]
      if trailhead and gps and gps.setDestination then
        gps.setDestination(trailhead.lat, trailhead.lon, trailhead.name)
      end
      if rawget(_G, 'guihooks') and guihooks.trigger then
        guihooks.trigger('Message', { ttl = 6, msg = string.format("[OTBT Tour] %s started convoy expedition: %s", msg.playerName or 'Teammate', msg.expedition.name), category = 'expedition' })
      end
    end
    return
  end

  if msg.type == 'expedition_stage' then
    if state.activeTour and state.activeTour.id == msg.expeditionId then
      state.checkpointIndex = tonumber(msg.stage) or state.checkpointIndex
      state.activeTour.status = msg.status or state.activeTour.status
      local nextChk = state.activeTour.checkpoints and state.activeTour.checkpoints[state.checkpointIndex]
      if nextChk and gps and gps.setDestination then
        gps.setDestination(nextChk.lat, nextChk.lon, nextChk.name)
      end
      M.saveState()
      if rawget(_G, 'guihooks') and guihooks.trigger then
        guihooks.trigger('Message', { ttl = 5, msg = string.format("[OTBT Tour] Convoy advanced to Stage %s (%s)", tostring(state.checkpointIndex), nextChk and nextChk.name or 'Checkpoint'), category = 'expedition' })
      end
    end
    return
  end

  if msg.type == 'expedition_complete' then
    if state.activeTour and state.activeTour.id == msg.expeditionId then
      state.passport.milestonesDiscovered = (state.passport.milestonesDiscovered or 0) + 1
      state.passport.stamps[msg.expeditionId] = msg.stamp or { completedAt = os.time() }
      state.activeTour = nil
      state.checkpointIndex = 1
      M.saveState()
      if rawget(_G, 'guihooks') and guihooks.trigger then
        guihooks.trigger('Message', { ttl = 8, msg = string.format("[OTBT Tour] Convoy completed expedition %s! Passport stamp earned!", tostring(msg.expeditionId)), category = 'expedition' })
      end
    end
    return
  end

  if msg.type == 'abandon_expedition' then
    state.activeTour = nil
    state.checkpointIndex = 1
    if gps and gps.clear then pcall(gps.clear) end
    M.saveState()
    if rawget(_G, 'guihooks') and guihooks.trigger then
      guihooks.trigger('Message', { ttl = 5, msg = "[OTBT Tour] Active expedition cancelled by convoy teammate", category = 'expedition' })
    end
    return
  end
end

-- Reset session
function M.reset()
  state.activeTour = nil
  state.checkpointIndex = 1
end

return M
