-- Freight & Logistics Co-op Simulation for BeamNG.Earth (Off the Beaten Track edition).
-- Provides deterministic contract generation across regional hubs (seeded by origin and epoch hour),
-- varied fleet requirements (1-truck solo/express, 2-truck tandem, 3-truck convoy, 4-truck mega haul),
-- cargo categories (dry, flatbed, tanker, reefer, heavy), multi-consignment slots, real-time cargo
-- integrity tracking, team damage penalties, and shared company treasury accounting.
local M = {}

local places = require('beamngEarth/places')
local gps = require('beamngEarth/gps')
local checkpoints = require('beamngEarth/checkpoints')

M.FILE = '/settings/beamngEarth_logistics.json'
M.VERSION = 1
M.EPOCH_INTERVAL_S = 3600 -- contracts rotate every hour (in-game/real-world epoch)

local lastBroadcastPenalty = {}
local serverJobs = {}
local ledgerRev, slotRev, ledgerPlayerKey = -1, -1, nil
local requestedEpoch
local function multiplayer()
  local session = require('beamngEarth/mpsession')
  return session.isSessionActive and session.isSessionActive()
end

local function broadcastLogistics(payload)
  return require('beamngEarth/mpsession').sendLogisticsEvent(payload)
end

-- Cargo catalog with characteristics and fleet suitability
M.CARGOS = {
  -- Solo / Express (1 Truck)
  { id = 'electronics', name = 'Consumer Electronics', category = 'dry', fragile = true, hazmat = false, minKg = 6000, maxKg = 14000, ratePerKm = 14.5, truckCounts = {1} },
  { id = 'produce', name = 'Fresh Citrus & Table Grapes', category = 'reefer', fragile = true, hazmat = false, minKg = 12000, maxKg = 22000, ratePerKm = 12.0, truckCounts = {1, 2} },
  { id = 'auto_parts', name = 'Automotive Assembly Spares', category = 'dry', fragile = false, hazmat = false, minKg = 10000, maxKg = 20000, ratePerKm = 11.0, truckCounts = {1, 2} },
  { id = 'med_supplies', name = 'Pharmaceuticals & Vaccines', category = 'reefer', fragile = true, hazmat = false, minKg = 5000, maxKg = 12000, ratePerKm = 18.0, truckCounts = {1} },

  -- Duo / Tandem (2 Trucks)
  { id = 'timber', name = 'Treated Pine Timber & Logs', category = 'flatbed', fragile = false, hazmat = false, minKg = 18000, maxKg = 26000, ratePerKm = 10.5, truckCounts = {2} },
  { id = 'packaged_goods', name = 'Packaged Retail Merchandise', category = 'dry', fragile = false, hazmat = false, minKg = 14000, maxKg = 22000, ratePerKm = 10.0, truckCounts = {1, 2} },
  { id = 'beverages', name = 'Bottled Water & Soft Drinks', category = 'dry', fragile = false, hazmat = false, minKg = 16000, maxKg = 25000, ratePerKm = 9.5, truckCounts = {2} },

  -- Convoy / Heavy (3 Trucks)
  { id = 'diesel', name = 'Refinery Ultra-Low Sulfur Diesel', category = 'tanker', fragile = false, hazmat = true, minKg = 20000, maxKg = 28000, ratePerKm = 16.0, truckCounts = {2, 3} },
  { id = 'cement', name = 'Bulk Construction Cement', category = 'tanker', fragile = false, hazmat = false, minKg = 22000, maxKg = 28000, ratePerKm = 11.5, truckCounts = {3} },
  { id = 'mining_explosives', name = 'Commercial Mining Emulsion', category = 'tanker', fragile = true, hazmat = true, minKg = 18000, maxKg = 25000, ratePerKm = 22.0, truckCounts = {3} },

  -- Mega Haul / Heavy Industrial (4 Trucks)
  { id = 'structural_steel', name = 'Bridge I-Beams & Structural Steel', category = 'flatbed', fragile = false, hazmat = false, minKg = 24000, maxKg = 30000, ratePerKm = 14.0, truckCounts = {3, 4} },
  { id = 'mining_crusher', name = 'Quarry Jaw Crusher Components', category = 'heavy', fragile = true, hazmat = false, minKg = 25000, maxKg = 32000, ratePerKm = 20.0, truckCounts = {4} },
  { id = 'copper_cathodes', name = 'Refined Copper Cathode Bundles', category = 'flatbed', fragile = false, hazmat = false, minKg = 22000, maxKg = 28000, ratePerKm = 15.5, truckCounts = {3, 4} },
  { id = 'wind_blades', name = 'Wind Turbine Hubs & Nacelles', category = 'heavy', fragile = true, hazmat = false, minKg = 20000, maxKg = 28000, ratePerKm = 25.0, truckCounts = {4} }
}

-- Company Fleet Upgrades & Carrier Licensing Catalog
M.UPGRADES = {
  {
    id = 'license_hazmat',
    category = 'license',
    name = 'Commercial HazMat Carrier License',
    icon = '☣️',
    cost = 35000,
    description = 'Authorizes transport of hazardous materials (commercial explosives, bulk diesel, and refinery chemicals). High gross payouts with strict spill liabilities.',
    benefit = 'Unlocks HazMat transport contracts'
  },
  {
    id = 'license_heavy_haul',
    category = 'license',
    name = 'Abnormal & Mega Haul Certification',
    icon = '🚜',
    cost = 50000,
    description = 'Government permit for multi-truck convoys and oversized mining/industrial loads over 100 metric tonnes.',
    benefit = 'Unlocks 4-truck Mega Haul contracts'
  },
  {
    id = 'license_reefer',
    category = 'license',
    name = 'Cold Chain & Perishables Certification',
    icon = '❄️',
    cost = 25000,
    description = 'Sanitary and temperature-controlled transport standards for high-value pharmaceuticals, vaccines, and fresh export produce.',
    benefit = 'Unlocks premium reefer loads with +15% payout'
  },
  {
    id = 'license_cross_border',
    category = 'license',
    name = 'SADC Cross-Border Carnet & Customs Bond',
    icon = '🛂',
    cost = 40000,
    description = 'Expedited border transit permits across South Africa, Namibia, Botswana, Zimbabwe, Mozambique, Zambia, and Tanzania.',
    benefit = 'Eliminates cross-border customs surcharges and delay penalties'
  },
  {
    id = 'garage_repair_bay',
    category = 'garage',
    name = 'Heavy Vehicle Workshop & Crane Bay',
    icon = '🔧',
    cost = 30000,
    description = 'Equips Home Base with specialized heavy truck repair lifts, laser wheel alignment, and body straightening jacks.',
    benefit = '-30% damage penalty deduction on all company hauls'
  },
  {
    id = 'garage_bulk_fuel',
    category = 'garage',
    name = 'Depot Bulk Fuel Tank & Fast Pump',
    icon = '⛽',
    cost = 20000,
    description = '50,000-litre wholesale diesel storage tank installed at Home Base HQ with commercial high-flow nozzle.',
    benefit = '-40% fuel refill cost at Home Base'
  },
  {
    id = 'cert_rock_crawl',
    category = 'overland',
    name = 'Extreme Rock Crawling Certification',
    icon = '🪨',
    cost = 18000,
    description = 'Advanced technical driver training and heavy-duty rock armor (underbody skid plates, differential locks, winch kit).',
    benefit = 'Unlocks Grade 5 extreme wilderness trails (Richtersveld)'
  },
  {
    id = 'cert_safari_snorkel',
    category = 'overland',
    name = 'Expedition Snorkel & Fording Gear',
    icon = '🌊',
    cost = 12000,
    description = 'Raised cold-air intake snorkel, extended differential breathers, and waterproofed electronic harnesses.',
    benefit = 'Enables deep river fording on Okavango and Zambezi expeditions'
  }
}

-- Target truck distribution for an 8-job board:
-- 3x 1-truck solo jobs, 2x 2-truck duo jobs, 2x 3-truck convoys, 1x 4-truck mega haul
M.BOARD_DISTRIBUTION = { 1, 1, 1, 2, 2, 3, 3, 4 }

-- 31-bit Lehmer/Park-Miller PRNG (deterministic across platforms and architectures)
function M.makeRng(seed)
  local state = math.abs(math.floor(seed)) % 2147483647
  if state == 0 then state = 123456789 end
  local function nextInt()
    state = (state * 48271) % 2147483647
    return state
  end
  local function nextFloat()
    return nextInt() / 2147483647
  end
  local function range(minVal, maxVal)
    if minVal >= maxVal then return minVal end
    return minVal + math.floor(nextFloat() * (maxVal - minVal + 1))
  end
  return { nextInt = nextInt, nextFloat = nextFloat, range = range }
end

-- String hash to uint31
function M.hashString(str)
  local h = 5381
  for i = 1, #str do
    h = ((h * 33) + str:byte(i)) % 2147483647
  end
  return h
end

-- Nearest logistics hub from player position
function M.findNearestHub(lat, lon, hubs)
  hubs = hubs or places.SEED
  local best, bestDist = nil, math.huge
  for _, h in ipairs(hubs) do
    local d = places.distance(lat, lon, h.lat, h.lon)
    if d < bestDist then
      best = h
      bestDist = d
    end
  end
  return best, bestDist
end

-- Filter candidate cargos matching the truck count
function M.cargosForTrucks(trucksRequired)
  local list = {}
  for _, c in ipairs(M.CARGOS) do
    for _, req in ipairs(c.truckCounts) do
      if req == trucksRequired then
        list[#list + 1] = c
        break
      end
    end
  end
  if #list == 0 then return M.CARGOS end
  return list
end

-- Pure: generate deterministic jobs for a hub and epoch
function M.generateJobs(originHub, epoch, allHubs)
  allHubs = allHubs or places.SEED
  local seed = (M.hashString(originHub.name) * 65537 + epoch * 31) % 2147483647
  local rng = M.makeRng(seed)

  -- Destination candidates (all hubs except origin)
  local destCandidates = {}
  for _, h in ipairs(allHubs) do
    if h.name ~= originHub.name then
      destCandidates[#destCandidates + 1] = h
    end
  end
  if #destCandidates == 0 then return {} end

  local jobs = {}
  for i, trucksReq in ipairs(M.BOARD_DISTRIBUTION) do
    -- Pick destination
    local destIdx = rng.range(1, #destCandidates)
    local dest = destCandidates[destIdx]

    -- Distance estimation (with road curvature factor ~1.25)
    local straightM = places.distance(originHub.lat, originHub.lon, dest.lat, dest.lon)
    local roadDistKm = math.max(30, math.floor(straightM * 1.25 / 1000 + 0.5))

    -- Pick cargo for this truck requirement
    local suitableCargos = M.cargosForTrucks(trucksReq)
    local cargo = suitableCargos[rng.range(1, #suitableCargos)]

    -- Weight and payout calculations
    local weightPerTruck = rng.range(cargo.minKg, cargo.maxKg)
    local totalWeightKg = weightPerTruck * trucksReq

    -- Rate modifiers: Fragile (+25%), HazMat (+40%), Multi-truck group bonus
    local rateMod = 1.0
    if cargo.fragile then rateMod = rateMod + 0.25 end
    if cargo.hazmat then rateMod = rateMod + 0.40 end
    if trucksReq == 2 then rateMod = rateMod + 0.10
    elseif trucksReq == 3 then rateMod = rateMod + 0.15
    elseif trucksReq >= 4 then rateMod = rateMod + 0.25
    end

    local baseHandlingFee = 600 -- flat terminal fee per vehicle
    local payoutPerTruck = math.floor((roadDistKm * cargo.ratePerKm * rateMod) + baseHandlingFee)
    local totalPayout = payoutPerTruck * trucksReq

    -- Consignment slots
    local slots = {}
    for s = 1, trucksReq do
      slots[s] = {
        slot = s,
        label = string.format("Consignment %d/%d: %s (%dt)", s, trucksReq, cargo.name, math.floor(weightPerTruck / 1000)),
        weightKg = weightPerTruck,
        claimedBy = nil,
        status = 'open', -- 'open', 'claimed', 'in_transit', 'delivered', 'failed'
        cargoHealth = 100.0,
        damagePenalty = 0,
        grossPayout = payoutPerTruck
      }
    end

    -- Deterministic Contract ID (e.g. #JH-8401)
    local prefix = originHub.name:sub(1, 2):upper()
    local jobId = string.format("#%s-%04d", prefix, (seed + i * 137) % 9000 + 1000)

    -- License requirement checks
    local isLocked = false
    local lockReason = nil
    if cargo.hazmat and not M.hasUpgrade('license_hazmat') then
      isLocked = true
      lockReason = 'Requires HazMat Carrier License ($35,000)'
    elseif trucksReq == 4 and not M.hasUpgrade('license_heavy_haul') then
      isLocked = true
      lockReason = 'Requires Abnormal & Mega Haul Permit ($50,000)'
    end

    -- Cold Chain bonus (+15%) if license_reefer is owned
    if cargo.category == 'reefer' and M.hasUpgrade('license_reefer') then
      payoutPerTruck = math.floor(payoutPerTruck * 1.15)
      totalPayout = payoutPerTruck * trucksReq
      for _, s in ipairs(slots) do s.grossPayout = payoutPerTruck end
    end

    jobs[#jobs + 1] = {
      id = jobId,
      origin = { name = originHub.name, lat = originHub.lat, lon = originHub.lon },
      destination = { name = dest.name, lat = dest.lat, lon = dest.lon },
      cargo = cargo,
      trucksRequired = trucksReq,
      weightPerTruckKg = weightPerTruck,
      totalWeightKg = totalWeightKg,
      distanceKm = roadDistKm,
      totalPayout = totalPayout,
      payoutPerTruck = payoutPerTruck,
      slots = slots,
      locked = isLocked,
      lockReason = lockReason,
      status = 'available' -- 'available', 'accepted', 'in_transit', 'completed', 'failed'
    }
  end

  return jobs
end

-- Calculate financial penalty for damaged cargo on a consignment
function M.calculatePenalty(slot, cargo)
  local health = math.max(0, math.min(100, slot.cargoHealth or 100))
  if health >= 98 then return 0 end
  local lostFrac = (100 - health) / 100
  local penaltyFactor = cargo.fragile and 1.5 or 1.0
  if cargo.hazmat and health < 50 then
    penaltyFactor = penaltyFactor * 1.5 -- severe HazMat spill penalty
  end
  local penalty = math.floor(slot.grossPayout * lostFrac * penaltyFactor)

  -- Apply Heavy Vehicle Workshop Bay bonus (-30% penalty)
  if M.hasUpgrade and M.hasUpgrade('garage_repair_bay') then
    penalty = math.floor(penalty * 0.70)
  end

  return math.min(slot.grossPayout, penalty)
end

-- Company State & Persistence
local companyState = {
  company = {
    name = 'OTBT Logistics Co-op',
    vault = 25000, -- startup working capital
    completedDeliveries = 0,
    totalTonnesHauled = 0,
    totalEarnings = 0,
    reputation = 100,
    upgrades = {}
  },
  activeContract = nil
}

function M.getCompany()
  return companyState.company
end

function M.hasUpgrade(upgradeId)
  local c = companyState.company
  return c and c.upgrades and c.upgrades[upgradeId] ~= nil
end

function M.getUpgradesList()
  local c = companyState.company
  local vault = c and c.vault or 0
  local list = {}
  for _, up in ipairs(M.UPGRADES) do
    local isBought = c and c.upgrades and c.upgrades[up.id] ~= nil
    list[#list + 1] = {
      id = up.id,
      category = up.category,
      name = up.name,
      icon = up.icon,
      cost = up.cost,
      description = up.description,
      benefit = up.benefit,
      purchased = isBought,
      purchasedAt = isBought and c.upgrades[up.id].purchasedAt or nil,
      canAfford = not isBought and (vault >= up.cost)
    }
  end
  return list
end

function M.purchaseUpgrade(upgradeId)
  if multiplayer() then return broadcastLogistics({type='purchase_upgrade',upgradeId=upgradeId}), 'pending' end
  local c = companyState.company
  if not c then return false, 'Company not initialized' end
  c.upgrades = c.upgrades or {}

  if c.upgrades[upgradeId] then
    return false, 'Upgrade already purchased'
  end

  local target = nil
  for _, up in ipairs(M.UPGRADES) do
    if up.id == upgradeId then target = up; break end
  end
  if not target then return false, 'Upgrade not found' end

  if (c.vault or 0) < target.cost then
    return false, string.format("Insufficient company funds ($%d needed, vault has $%d)", target.cost, c.vault or 0)
  end

  c.vault = c.vault - target.cost
  c.upgrades[upgradeId] = {
    purchasedAt = os.time(),
    cost = target.cost
  }
  M.saveState()

  broadcastLogistics({
    type = 'purchase_upgrade',
    upgradeId = upgradeId,
    cost = target.cost,
    company = c
  })

  return true, target
end

function M.setCompanyName(name)
  if multiplayer() then return broadcastLogistics({type='set_company_name',name=name}), 'pending' end
  if type(name) ~= 'string' then return false, 'Name must be a string' end
  name = name:match('^%s*(.-)%s*$') or ''
  if #name == 0 then return false, 'Name cannot be empty' end
  if #name > 64 then name = name:sub(1, 64) end

  companyState.company.name = name
  M.saveState()

  broadcastLogistics({
    type = 'set_company_name',
    name = name
  })

  return true, name
end

function M.getActiveContract()
  return companyState.activeContract
end

-- Load state from JSON file
function M.loadState()
  if rawget(_G, 'jsonReadFile') then
    local data = jsonReadFile(M.FILE)
    if type(data) == 'table' and data.company then
      companyState = data
      return true
    end
  end
  return false
end

-- Save state to JSON file
function M.saveState()
  if rawget(_G, 'jsonWriteFile') then
    return jsonWriteFile(M.FILE, companyState, true)
  end
  return false
end

-- Get current market jobs for the player's coordinate
function M.getAvailableJobs(lat, lon, epoch)
  if multiplayer() then
    local currentEpoch=math.floor(os.time()/3600)
    if requestedEpoch~=currentEpoch then
      requestedEpoch=currentEpoch; broadcastLogistics({type='sync_request'})
    end
    local hub = M.findNearestHub(lat, lon)
    local jobs = {}
    for _, job in ipairs(serverJobs) do if hub and job.origin.name == hub.name then jobs[#jobs+1] = job end end
    return jobs
  end
  epoch = epoch or math.floor(os.time() / M.EPOCH_INTERVAL_S)
  local originHub = M.findNearestHub(lat, lon)
  if not originHub then return {} end
  return M.generateJobs(originHub, epoch)
end

-- Trailer models matching cargo categories
function M.trailerModelForCategory(cat)
  if cat == 'tanker' then return 'tanker' end
  if cat == 'flatbed' or cat == 'heavy' then return 'flatbed' end
  return 'dryvan'
end

-- Spawn a matching trailer hitched behind the current player vehicle
function M.spawnContractTrailer()
  local c = companyState.activeContract
  if not c or not c.cargo then return false, 'No active contract' end
  local pVeh = rawget(_G, 'getPlayerVehicle') and getPlayerVehicle(0)
  if not pVeh then return false, 'No player vehicle found' end

  local pos = pVeh:getPosition()
  local dir = pVeh:getDirectionVector()
  -- place trailer ~8.5m behind the truck
  local spawnPos = vec3(pos.x - dir.x * 8.5, pos.y - dir.y * 8.5, pos.z + 0.5)
  local rot = quat(0, 0, 1, 0) * quat(pVeh:getRefNodeRotation())

  local model = M.trailerModelForCategory(c.cargo.category)
  if rawget(_G, 'core_vehicles') and core_vehicles.spawnNewVehicle then
    local ok, trailer = pcall(core_vehicles.spawnNewVehicle, model, {
      pos = spawnPos,
      rot = rot,
      autoEnterVehicle = false
    })
    return ok, trailer
  end
  return false, 'core_vehicles unavailable'
end

-- Accept a contract from the market
function M.acceptContract(job, playerPid, playerName, slotIndex)
  if multiplayer() then return broadcastLogistics({type='accept',jobId=job and job.id,slotIndex=slotIndex or 1}), 'pending' end
  if job and job.locked then
    return false, job.lockReason or 'Company lacks required carrier certification'
  end

  if companyState.activeContract and companyState.activeContract.status == 'in_transit' then
    return false, 'A contract is already in transit'
  end

  slotIndex = slotIndex or 1
  if slotIndex < 1 or slotIndex > job.trucksRequired then
    return false, 'Invalid consignment slot'
  end

  job.status = 'in_transit'
  job.acceptedAt = os.time()
  job.slots[slotIndex].claimedPid = playerPid
  job.slots[slotIndex].claimedBy = playerName or tostring(playerPid or 'Driver 1')
  job.slots[slotIndex].status = 'in_transit'

  companyState.activeContract = job
  M.saveState()

  -- Broadcast accept to convoy/server
  broadcastLogistics({
    type = 'accept',
    contract = job,
    slotIndex = slotIndex,
    playerName = job.slots[slotIndex].claimedBy,
    pid = playerPid
  })

  -- Route GPS to destination
  if gps and gps.setDestination then
    gps.setDestination(job.destination.lat, job.destination.lon, job.destination.name)
  end

  return true, job
end

-- Claim an open consignment slot in an active multi-truck contract
function M.claimSlot(slotIndex, playerPid, playerName)
  if multiplayer() then return broadcastLogistics({type='claim',jobId=companyState.activeContract and companyState.activeContract.id,slotIndex=slotIndex}), 'pending' end
  local c = companyState.activeContract
  if not c or c.status ~= 'in_transit' then return false, 'No active contract in transit' end
  if slotIndex < 1 or slotIndex > c.trucksRequired then return false, 'Invalid slot' end
  local slot = c.slots[slotIndex]
  if slot.claimedBy ~= nil and slot.status ~= 'open' then return false, 'Slot already claimed' end

  slot.claimedPid = playerPid
  slot.claimedBy = playerName or tostring(playerPid or 'Teammate')
  slot.status = 'in_transit'
  M.saveState()

  broadcastLogistics({
    type = 'claim',
    jobId = c.id,
    slotIndex = slotIndex,
    playerName = slot.claimedBy,
    pid = playerPid
  })

  return true, slot
end

-- Record cargo damage on a claimed slot
function M.recordDamage(slotIndex, damagePercent)
  if multiplayer() then return broadcastLogistics({type='damage',jobId=companyState.activeContract and companyState.activeContract.id,slotIndex=slotIndex,cargoHealth=math.max(0,100-damagePercent)}) end
  local c = companyState.activeContract
  if not c or not c.slots[slotIndex] then return false end
  local slot = c.slots[slotIndex]
  slot.cargoHealth = math.max(0, math.min(100, 100 - damagePercent))
  slot.damagePenalty = M.calculatePenalty(slot, c.cargo)

  if lastBroadcastPenalty[slotIndex] ~= slot.damagePenalty then
    lastBroadcastPenalty[slotIndex] = slot.damagePenalty
    broadcastLogistics({
      type = 'damage',
      jobId = c.id,
      slotIndex = slotIndex,
      cargoHealth = slot.cargoHealth,
      damagePenalty = slot.damagePenalty
    })
  end

  return true, slot.cargoHealth, slot.damagePenalty
end

-- Complete delivery for a slot
function M.deliverSlot(slotIndex, precisionDock)
  if multiplayer() then return broadcastLogistics({type='deliver_slot',jobId=companyState.activeContract and companyState.activeContract.id,slotIndex=slotIndex,cargoHealth=companyState.activeContract and companyState.activeContract.slots[slotIndex] and companyState.activeContract.slots[slotIndex].cargoHealth}), 'pending' end
  local c = companyState.activeContract
  if not c or not c.slots[slotIndex] then return false, 'Invalid slot' end
  local slot = c.slots[slotIndex]
  if c.status ~= 'in_transit' or slot.status ~= 'in_transit' or slot.claimedBy == nil then
    return false, 'Slot is not currently claimed'
  end
  local cfg = rawget(_G, 'MPConfig')
  local pid = cfg and cfg.getPlayerServerID and cfg.getPlayerServerID()
  if pid ~= nil and slot.claimedPid ~= nil and tostring(pid) ~= tostring(slot.claimedPid) then
    return false, 'Slot belongs to another player'
  end
  slot.status = 'delivered'

  local isDock = (precisionDock == true) or (c.precisionDockCompleted == true)
  slot.precisionDock = isDock
  if isDock then
    slot.dockBonus = math.floor(slot.grossPayout * 0.20)
    slot.grossPayout = slot.grossPayout + slot.dockBonus
  else
    slot.dockBonus = 0
  end

  slot.damagePenalty = M.calculatePenalty(slot, c.cargo)

  broadcastLogistics({
    type = 'deliver_slot',
    jobId = c.id,
    slotIndex = slotIndex,
    cargoHealth = slot.cargoHealth,
    damagePenalty = slot.damagePenalty,
    playerName = slot.claimedBy,
    pid = slot.claimedPid,
    precisionDock = slot.precisionDock,
    dockBonus = slot.dockBonus
  })

  -- Every consignment must be delivered; open slots still need a driver.
  local allDone = true
  for _, s in ipairs(c.slots) do
    if s.status ~= 'delivered' then
      allDone = false
      break
    end
  end

  if allDone then
    return M.finalizeContract()
  end

  M.saveState()
  return true, 'slot_delivered'
end

-- Finalize entire contract, deposit to company treasury, update stats
function M.finalizeContract()
  if multiplayer() then return broadcastLogistics({type='finalize',jobId=companyState.activeContract and companyState.activeContract.id}), 'pending' end
  local c = companyState.activeContract
  if not c then return false, 'No active contract' end
  for _, slot in ipairs(c.slots) do
    if slot.status ~= 'delivered' then return false, 'Undelivered slots remain' end
  end

  local grossEarnings = 0
  local totalPenalties = 0
  local totalDockBonus = 0
  local deliveredWeightKg = 0

  for _, s in ipairs(c.slots) do
    if s.status == 'delivered' then
      grossEarnings = grossEarnings + s.grossPayout
      local pen = M.calculatePenalty(s, c.cargo)
      totalPenalties = totalPenalties + pen
      totalDockBonus = totalDockBonus + (s.dockBonus or 0)
      deliveredWeightKg = deliveredWeightKg + s.weightKg
    end
  end

  local netPayout = math.max(0, grossEarnings - totalPenalties)

  -- Update company vault and stats
  local comp = companyState.company
  comp.vault = comp.vault + netPayout
  comp.totalEarnings = comp.totalEarnings + netPayout
  comp.completedDeliveries = comp.completedDeliveries + 1
  comp.totalTonnesHauled = comp.totalTonnesHauled + math.floor(deliveredWeightKg / 1000)

  -- Reputation adjustment based on penalties and precision reverse docking
  local repGain = 2
  if totalDockBonus > 0 then
    repGain = repGain + 5 -- Precision Docking skill bonus!
  end
  if totalPenalties > (grossEarnings * 0.3) then
    repGain = -5
    comp.reputation = math.max(10, comp.reputation - 5)
  else
    comp.reputation = math.min(100, comp.reputation + repGain)
  end

  local manifest = {
    contractId = c.id,
    origin = c.origin.name,
    destination = c.destination.name,
    cargo = c.cargo.name,
    grossEarnings = grossEarnings,
    totalPenalties = totalPenalties,
    dockBonus = totalDockBonus,
    netPayout = netPayout,
    companyVault = comp.vault,
    reputation = comp.reputation
  }

  broadcastLogistics({
    type = 'finalize',
    jobId = c.id,
    netPayout = netPayout,
    tonnes = math.floor(deliveredWeightKg / 1000),
    reputationDelta = repGain
  })

  c.status = 'completed'
  c.manifest = manifest
  companyState.activeContract = nil
  M.saveState()

  return true, manifest
end

-- Update loop: monitors active contract, tracks damage, and detects arrival
local lastDamageCheck = 0
local baselineDamage = {}

-- Driver Fatigue & Fuel Simulation State
local driverStatus = {
  fatiguePercent = 0.0,
  fuelPercent = 100.0,
  fuelLiters = 400.0,
  tankCapacityLiters = 400.0,
  lastCheckTime = 0,
  fatigueWarned = false
}

function M.getDriverStatus(lat, lon)
  local isAtBase = false
  local exp = rawget(_G, 'beamngEarth_expeditions') or (extensions and extensions.beamngEarth_expeditions)
  if not exp then pcall(function() exp = require('beamngEarth/expeditions') end) end
  local hb = exp and exp.getHomeBase and exp.getHomeBase()
  if hb and lat and lon then
    if places.distance(lat, lon, hb.lat, hb.lon) <= 300 then
      isAtBase = true
    end
  end

  local isNearTown = isAtBase
  if not isNearTown and lat and lon then
    local nearestHub, hubDist = M.findNearestHub(lat, lon)
    if nearestHub and hubDist <= 2500 then
      isNearTown = true
    end
  end

  local pricePerLiter = 1.85
  if isAtBase and M.hasUpgrade and M.hasUpgrade('garage_bulk_fuel') then
    pricePerLiter = 1.10 -- 40% wholesale discount
  end

  local litersNeeded = math.max(0, driverStatus.tankCapacityLiters - driverStatus.fuelLiters)
  local refillCost = math.floor(litersNeeded * pricePerLiter)

  return {
    fatiguePercent = math.floor(driverStatus.fatiguePercent + 0.5),
    fuelPercent = math.floor(driverStatus.fuelPercent + 0.5),
    fuelLiters = math.floor(driverStatus.fuelLiters + 0.5),
    tankCapacity = driverStatus.tankCapacityLiters,
    isAtBase = isAtBase,
    isNearTown = isNearTown,
    pricePerLiter = pricePerLiter,
    refillCost = refillCost,
    canRest = true,
    canRefuel = (isNearTown or isAtBase) and (litersNeeded >= 5)
  }
end

-- Refuel truck at station or Home Base
function M.refuelVehicle(lat, lon)
  local status = M.getDriverStatus(lat, lon)
  if not status.canRefuel then
    return false, 'Must be near a town or Home Base with at least 5L fuel deficit'
  end

  if multiplayer() then return broadcastLogistics({type='refuel',litres=math.max(0,driverStatus.tankCapacityLiters-driverStatus.fuelLiters)}), 'pending' end
  local comp = companyState.company
  if (comp.vault or 0) < status.refillCost then
    return false, string.format("Insufficient company funds ($%d needed)", status.refillCost)
  end

  comp.vault = comp.vault - status.refillCost
  driverStatus.fuelLiters = driverStatus.tankCapacityLiters
  driverStatus.fuelPercent = 100.0
  M.saveState()

  -- Send refuel command to BeamNG vehicle if present
  local pVeh = rawget(_G, 'getPlayerVehicle') and getPlayerVehicle(0)
  if pVeh then
    pVeh:queueLuaCommand("if energyStorage then for _, s in pairs(energyStorage.getStorages()) do if s.type == 'fuelTank' then s:setRemainingRatio(1.0) end end end")
  end

  broadcastLogistics({
    type = 'refuel',
    cost = status.refillCost,
    company = comp
  })

  if rawget(_G, 'ui_message') then
    pcall(ui_message, string.format("⛽ TANK REFUELED! Refilled to 100%% for $%d.", status.refillCost), 6, 'beamngEarthFreight')
  end

  return true, status.refillCost
end

-- Rest / sleep to eliminate driver fatigue and advance time of day
function M.restDriver(hours)
  hours = hours or 8
  local pVeh = rawget(_G, 'getPlayerVehicle') and getPlayerVehicle(0)
  local speed = pVeh and pVeh.getVelocity and pVeh:getVelocity():length() or 0
  if speed >= 1.0 then
    return false, 'Vehicle must be stopped to rest'
  end

  driverStatus.fatiguePercent = 0.0

  -- Advance BeamNG TimeOfDay
  local scenetree = rawget(_G, 'scenetree')
  local names = scenetree and scenetree.findClassObjects and scenetree.findClassObjects('TimeOfDay')
  local tod = names and names[1] and scenetree.findObject(names[1])
  if tod then
    local currentT = tonumber(tod.time) or 0
    tod.time = (currentT + hours / 24) % 1.0
  end

  if rawget(_G, 'ui_message') then
    pcall(ui_message, string.format("💤 REST COMPLETED: Slept for %d hours. Driver refreshed!", hours), 6, 'beamngEarthFreight')
  end

  return true, hours
end

function M.getVehicleDamage(veh)
  if not veh then return 0 end
  local id = veh:getID()
  local o = id and rawget(_G, 'map') and map.objects and map.objects[id]
  local total = o and tonumber(o.damage) or 0

  -- If a trailer is coupled via core_trailerRespawn, check its damage too
  local tr = rawget(_G, 'core_trailerRespawn')
  local getC = tr and (tr.getCouplingDetails or tr.getCouplings)
  local cMap = getC and pcall(getC) and getC()
  if type(cMap) == 'table' and cMap[id] and cMap[id].trailerId then
    local tid = tonumber(cMap[id].trailerId)
    local to = tid and rawget(_G, 'map') and map.objects and map.objects[tid]
    total = total + (to and tonumber(to.damage) or 0)
  end
  return total
end

function M.update(playerLat, playerLon, playerVeh)
  local c = companyState.activeContract
  if not c or c.status ~= 'in_transit' then return end

  local now = os.clock()

  -- Check vehicle damage accumulation every 0.5s
  if now - lastDamageCheck >= 0.5 then
    lastDamageCheck = now
    if playerVeh then
      local vehId = playerVeh:getID()
      local currentDmg = M.getVehicleDamage(playerVeh)

      if baselineDamage[vehId] == nil then
        baselineDamage[vehId] = currentDmg
      else
        local delta = math.max(0, currentDmg - baselineDamage[vehId])
        -- Damage curve: <200 = 0% loss, 200..10000 = scaled 1%..100% loss
        local damagePercent = 0
        if delta > 200 then
          damagePercent = math.min(100, (delta - 200) / 7800 * 100)
        end
        -- Find our claimed slot (default to slot 1 if solo)
        for sIdx, slot in ipairs(c.slots) do
          if slot.status == 'in_transit' and (not multiplayer() or slot.claimedKey == ledgerPlayerKey) then
            M.recordDamage(sIdx, damagePercent)
            break
          end
        end
      end
    end
  end

  -- Arrival detection: within 40m of destination coordinates
  if playerLat and playerLon and c.destination then
    local distM = places.distance(playerLat, playerLon, c.destination.lat, c.destination.lon)
    c.currentDistanceM = distM

    if distM <= 40 then
      local speed = playerVeh and playerVeh.getVelocity and playerVeh:getVelocity():length() or 0

      -- Detect trailer uncoupling inside depot loading bay
      if playerVeh then
        local vehId = playerVeh:getID()
        local tr = rawget(_G, 'core_trailerRespawn')
        local getC = tr and (tr.getCouplingDetails or tr.getCouplings)
        local cMap = getC and pcall(getC) and getC()
        local coupledNow = type(cMap) == 'table' and cMap[vehId] and cMap[vehId].trailerId ~= nil

        if c.wasCoupledOnArrival == nil then
          c.wasCoupledOnArrival = coupledNow
        elseif c.wasCoupledOnArrival and not coupledNow and speed < 0.5 then
          if not c.precisionDockCompleted and not multiplayer() then
            c.precisionDockCompleted = true
            if rawget(_G, 'ui_message') then
              pcall(ui_message, "🅿️ PRECISION DOCK COMPLETE! Trailer uncoupled in loading bay (+20% Payout Bonus).", 8, 'beamngEarthFreight')
            end
          end
        end
      end

      if speed < 1.0 and not c.canDeliverPrompted then
        c.canDeliverPrompted = true
        if rawget(_G, 'ui_message') then
          pcall(ui_message, string.format("Destination reached: %s. Standard drop-off or precision dock in logistics menu.", c.destination.name), 8, 'beamngEarthFreight')
        end
      end
    end
  end

  -- Fuel consumption and driver fatigue simulation (every 2s)
  if now - driverStatus.lastCheckTime >= 2.0 then
    local dt = (driverStatus.lastCheckTime > 0) and (now - driverStatus.lastCheckTime) or 2.0
    driverStatus.lastCheckTime = now

    local speed = playerVeh and playerVeh.getVelocity and playerVeh:getVelocity():length() or 0
    if speed > 2.0 then
      -- Driving: accumulate fatigue (~1% per 30s of highway driving)
      driverStatus.fatiguePercent = math.min(100.0, driverStatus.fatiguePercent + (dt / 30.0))

      -- Fuel consumption based on speed and load
      local kmDriven = (speed * dt) / 1000.0
      local ratePerKm = 0.38 -- ~38 L/100km for commercial heavy semi
      local litersBurned = kmDriven * ratePerKm
      driverStatus.fuelLiters = math.max(0, driverStatus.fuelLiters - litersBurned)
      driverStatus.fuelPercent = (driverStatus.fuelLiters / driverStatus.tankCapacityLiters) * 100.0

      -- Fatigue warning toast
      if driverStatus.fatiguePercent >= 85 and not driverStatus.fatigueWarned then
        driverStatus.fatigueWarned = true
        if rawget(_G, 'ui_message') then
          pcall(ui_message, "⚠️ DRIVER FATIGUE CRITICAL (85%): Pull over at a rest stop or Home Base to sleep!", 8, 'beamngEarthFreight')
        end
      elseif driverStatus.fatiguePercent < 80 then
        driverStatus.fatigueWarned = false
      end
    end
  end

  -- Regional checkpoints (toll plazas, border posts, weigh stations)
  if checkpoints and checkpoints.update then
    checkpoints.update(playerLat, playerLon, playerVeh)
  end
end

-- UI State representation for HUD and menus
function M.getUiState(playerLat, playerLon)
  local c = companyState.activeContract
  local available = {}
  if playerLat and playerLon then
    available = M.getAvailableJobs(playerLat, playerLon)
  end

  return {
    company = companyState.company,
    activeContract = c,
    availableJobs = available,
    canDeliver = c and c.currentDistanceM and c.currentDistanceM <= 40,
    precisionDockCompleted = c and c.precisionDockCompleted == true,
    driverStatus = M.getDriverStatus(playerLat, playerLon),
    upgrades = M.getUpgradesList(),
    checkpoints = checkpoints and checkpoints.getUiState and checkpoints.getUiState(playerLat, playerLon)
  }
end

-- Abandon contract
function M.abandonContract()
  if multiplayer() then return broadcastLogistics({type='abandon',jobId=companyState.activeContract and companyState.activeContract.id}), 'pending' end
  local c = companyState.activeContract
  if not c then return false end
  broadcastLogistics({
    type = 'abandon',
    jobId = c.id
  })
  companyState.company.reputation = math.max(10, companyState.company.reputation - 10)
  companyState.activeContract = nil
  M.saveState()
  return true
end

-- Remote event handler from BeamMP server
function M.onRemoteLogistics(msg)
  if type(msg) ~= 'table' or type(msg.type) ~= 'string' then return end

  if msg.type == 'slot_state' then
    if msg.rev and msg.rev < math.max(ledgerRev, slotRev) then return end
    slotRev = msg.rev or slotRev
    if companyState.activeContract and msg.contract and companyState.activeContract.id ~= msg.contract.id then return end
    if msg.contract then
      companyState.activeContract = msg.contract.status == 'in_transit' and msg.contract or nil
      for _, slot in ipairs(msg.contract.slots) do if slot.status == 'claimed' then slot.status = 'in_transit' end end
    end
    return
  end
  if msg.type == 'ledger_state' then
    if msg.rev and msg.rev <= ledgerRev then return end
    ledgerRev = msg.rev or ledgerRev
    ledgerPlayerKey = msg.playerKey or ledgerPlayerKey
    if checkpoints and checkpoints.onRemoteLogistics then checkpoints.onRemoteLogistics(msg) end
    if msg.jobs then serverJobs = msg.jobs end
    if msg.company then companyState.company = msg.company end
    companyState.activeContract = msg.contract and msg.contract.status == 'in_transit' and msg.contract or nil
    if companyState.activeContract then
      for _, slot in ipairs(companyState.activeContract.slots) do if slot.status == 'claimed' then slot.status = 'in_transit' end end
      if msg.intent == 'accept' and gps and gps.setDestination then
        local dest = companyState.activeContract.destination
        gps.setDestination(dest.lat, dest.lon, dest.name)
      end
    end
    if msg.intent == 'refuel' then
      driverStatus.fuelLiters = driverStatus.tankCapacityLiters; driverStatus.fuelPercent = 100
      local veh = rawget(_G, 'getPlayerVehicle') and getPlayerVehicle(0)
      if veh then veh:queueLuaCommand("if energyStorage then for _, s in pairs(energyStorage.getStorages()) do if s.type == 'fuelTank' then s:setRemainingRatio(1.0) end end end") end
    end
    M.saveState()
    return
  end
  if msg.type == 'sync_state' then
    ledgerRev, slotRev = msg.rev or -1, msg.rev or -1
    ledgerPlayerKey = msg.playerKey
    serverJobs = msg.jobs or {}
    companyState.activeContract = nil
    if msg.state and msg.state.activeContract then
      for _, slot in ipairs(msg.state.activeContract.slots) do if slot.status == 'claimed' then slot.status = 'in_transit' end end
    end
    if msg.state and type(msg.state.company) == 'table' then
      companyState.company = msg.state.company
    end
    if msg.state and msg.state.activeContract ~= nil then
      companyState.activeContract = msg.state.activeContract
    end
    M.saveState()
    return
  end

  if multiplayer() and msg.type ~= 'cb_radio' then return end

  if msg.type == 'purchase_upgrade' then
    if msg.company then
      companyState.company = msg.company
    elseif msg.upgradeId then
      companyState.company.upgrades = companyState.company.upgrades or {}
      companyState.company.upgrades[msg.upgradeId] = { purchasedAt = os.time(), cost = msg.cost }
      if msg.cost then
        companyState.company.vault = math.max(0, (companyState.company.vault or 0) - msg.cost)
      end
    end
    M.saveState()
    if rawget(_G, 'guihooks') and guihooks.trigger then
      guihooks.trigger('Message', { ttl = 6, msg = string.format("[OTBT Fleet] %s purchased: %s!", msg.playerName or 'Teammate', msg.upgradeId), category = 'freight' })
    end
    return
  end

  if msg.type == 'set_company_name' then
    if type(msg.name) == 'string' and #msg.name > 0 then
      companyState.company.name = msg.name
      M.saveState()
      if rawget(_G, 'guihooks') and guihooks.trigger then
        guihooks.trigger('Message', { ttl = 5, msg = string.format("[OTBT Freight] Group renamed to: %s", msg.name), category = 'freight' })
      end
    end
    return
  end

  if msg.type == 'accept' then
    if type(msg.contract) == 'table' then
      companyState.activeContract = msg.contract
      M.saveState()
      if rawget(_G, 'guihooks') and guihooks.trigger then
        guihooks.trigger('Message', { ttl = 6, msg = string.format("[OTBT Freight] %s accepted convoy contract: %s", msg.playerName or 'Teammate', msg.contract.cargo.name), category = 'freight' })
      end
      if gps and gps.setDestination and msg.contract.destination then
        gps.setDestination(msg.contract.destination.lat, msg.contract.destination.lon, msg.contract.destination.name)
      end
    end
    return
  end

  if msg.type == 'claim' then
    local c = companyState.activeContract
    local sIdx = tonumber(msg.slotIndex)
    if c and c.id == msg.jobId and c.slots and sIdx and c.slots[sIdx]
        and c.slots[sIdx].status == 'open' then
      c.slots[sIdx].claimedPid = msg.pid
      c.slots[sIdx].claimedBy = msg.playerName
      c.slots[sIdx].status = 'in_transit'
      M.saveState()
      if rawget(_G, 'guihooks') and guihooks.trigger then
        guihooks.trigger('Message', { ttl = 5, msg = string.format("[OTBT Freight] %s claimed Consignment %d/%d", msg.playerName or 'Teammate', sIdx, c.trucksRequired), category = 'freight' })
      end
    end
    return
  end

  if msg.type == 'damage' then
    local c = companyState.activeContract
    local sIdx = tonumber(msg.slotIndex)
    if c and c.slots and sIdx and c.slots[sIdx] then
      c.slots[sIdx].cargoHealth = tonumber(msg.cargoHealth) or c.slots[sIdx].cargoHealth
      c.slots[sIdx].damagePenalty = tonumber(msg.damagePenalty) or c.slots[sIdx].damagePenalty
      M.saveState()
    end
    return
  end

  if msg.type == 'deliver_slot' then
    local c = companyState.activeContract
    local sIdx = tonumber(msg.slotIndex)
    local slot = c and c.slots and sIdx and c.slots[sIdx]
    if not slot or c.id ~= msg.jobId or c.status ~= 'in_transit'
        or slot.status ~= 'in_transit' or slot.claimedBy == nil then
      return false, 'Slot is not currently claimed'
    end
    if slot.claimedPid ~= nil and tostring(slot.claimedPid) ~= tostring(msg.pid) then
      return false, 'Slot belongs to another player'
    end
    if slot then
      slot.precisionDock = msg.precisionDock == true
      slot.dockBonus = slot.precisionDock and math.floor(slot.grossPayout * 0.20) or 0
      slot.grossPayout = slot.grossPayout + slot.dockBonus
      c.slots[sIdx].status = 'delivered'
      c.slots[sIdx].cargoHealth = tonumber(msg.cargoHealth) or c.slots[sIdx].cargoHealth
      c.slots[sIdx].damagePenalty = tonumber(msg.damagePenalty) or c.slots[sIdx].damagePenalty
      M.saveState()
      if rawget(_G, 'guihooks') and guihooks.trigger then
        guihooks.trigger('Message', { ttl = 6, msg = string.format("[OTBT Freight] %s delivered Consignment %d/%d!", msg.playerName or 'Teammate', sIdx, c.trucksRequired), category = 'freight' })
      end
    end
    return
  end

  if msg.type == 'finalize' then
    local c = companyState.activeContract
    if not c or c.id ~= msg.jobId then return false, 'No matching active contract' end
    for _, slot in ipairs(c.slots) do
      if slot.status ~= 'delivered' then return false, 'Undelivered slots remain' end
    end
    if msg.company then
      companyState.company = msg.company
    end
    companyState.activeContract = nil
    M.saveState()
    if rawget(_G, 'guihooks') and guihooks.trigger then
      guihooks.trigger('Message', { ttl = 8, msg = string.format("[OTBT Freight] Contract completed! +$%d added to Company Vault by %s", tonumber(msg.netPayout) or 0, msg.playerName or 'Team'), category = 'freight' })
    end
    return
  end

  if msg.type == 'cb_radio' then
    local convoy = require('beamngEarth/convoy')
    if convoy and convoy.receiveRadioMessage then
      convoy.receiveRadioMessage(msg)
    end
    return
  end

  if msg.type == 'abandon' then
    companyState.activeContract = nil
    M.saveState()
    if rawget(_G, 'guihooks') and guihooks.trigger then
      guihooks.trigger('Message', { ttl = 5, msg = string.format("[OTBT Freight] Contract abandoned by %s", msg.playerName or 'Teammate'), category = 'freight' })
    end
    return
  end
end

-- Reset session
function M.reset()
  ledgerRev, slotRev, ledgerPlayerKey = -1, -1, nil
  serverJobs, requestedEpoch = {}, nil
  companyState.activeContract = nil
  driverStatus.fatiguePercent = 0.0
  driverStatus.fuelPercent = 100.0
  driverStatus.fuelLiters = driverStatus.tankCapacityLiters
  driverStatus.lastCheckTime = 0
  driverStatus.fatigueWarned = false
  if checkpoints and checkpoints.reset then checkpoints.reset() end
end

function M.clearCheckpoint(cpId, playerLat, playerLon)
  if checkpoints and checkpoints.clearCheckpoint then
    return checkpoints.clearCheckpoint(cpId, playerLat, playerLon)
  end
  return false, 'Checkpoints module not loaded'
end

function M._setDriverStatus(t)
  if type(t) == 'table' then
    if t.fatiguePercent ~= nil then driverStatus.fatiguePercent = t.fatiguePercent end
    if t.fuelPercent ~= nil then driverStatus.fuelPercent = t.fuelPercent end
    if t.fuelLiters ~= nil then driverStatus.fuelLiters = t.fuelLiters end
    if t.tankCapacityLiters ~= nil then driverStatus.tankCapacityLiters = t.tankCapacityLiters end
  end
end

return M
