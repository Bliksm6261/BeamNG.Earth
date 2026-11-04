-- Server catalog. Keep pricing/generation aligned with freight.lua and places.SEED.
local M = {}
local places = {}
places.SEED = {
  { name = 'Johannesburg', lat = -26.2041, lon = 28.0473 },
  { name = 'Pretoria', lat = -25.7461, lon = 28.1881 },
  { name = 'Cape Town', lat = -33.9249, lon = 18.4241 },
  { name = 'Durban', lat = -29.8587, lon = 31.0218 },
  { name = 'Gqeberha (Port Elizabeth)', lat = -33.9608, lon = 25.6022 },
  { name = 'Bloemfontein', lat = -29.0852, lon = 26.1596 },
  { name = 'East London', lat = -33.0153, lon = 27.9116 },
  { name = 'Pietermaritzburg', lat = -29.6006, lon = 30.3794 },
  { name = 'Polokwane', lat = -23.9045, lon = 29.4689 },
  { name = 'Mbombela (Nelspruit)', lat = -25.4658, lon = 30.9853 },
  { name = 'Kimberley', lat = -28.7282, lon = 24.7499 },
  { name = 'George', lat = -33.9630, lon = 22.4617 },
  { name = 'Sani Pass, Sani Top (Lesotho)', lat = -29.5868, lon = 29.2886 },
  { name = 'Chapman\'s Peak Drive, Cape Town', lat = -34.0886, lon = 18.3606 },
  { name = 'Richtersveld, Sendelingsdrift', lat = -28.1167, lon = 16.8833 },
  { name = 'Kgalagadi, Twee Rivieren', lat = -26.4733, lon = 20.6122 },
  { name = 'Sossusvlei, Dune 45 (Namibia)', lat = -24.7348, lon = 15.4699 },
  { name = 'Swakopmund, Skeleton Coast road (Namibia)', lat = -22.6784, lon = 14.5266 },
  { name = 'Maun, Okavango gateway (Botswana)', lat = -19.9833, lon = 23.4167 },
  { name = 'Victoria Falls (Zimbabwe)', lat = -17.9318, lon = 25.8307 },
  { name = 'Livingstone (Zambia)', lat = -17.8419, lon = 25.8543 },
  { name = 'Tofo Beach (Mozambique)', lat = -23.8517, lon = 35.5442 },
  { name = 'Mbabane (Eswatini)', lat = -26.3167, lon = 31.1333 },
  { name = 'Cape Maclear, Lake Malawi', lat = -14.0222, lon = 34.8436 },
  { name = 'Serengeti, Seronera (Tanzania)', lat = -2.4500, lon = 34.8236 },
}
function places.distance(lat1, lon1, lat2, lon2)
  local r = math.pi / 180
  local a = math.sin((lat2 - lat1) * r / 2) ^ 2 + math.cos(lat1 * r) * math.cos(lat2 * r) * math.sin((lon2 - lon1) * r / 2) ^ 2
  return 2 * 6371008.8 * math.asin(math.min(1, math.sqrt(a)))
end
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
function M.generateJobs(originHub, epoch, allHubs, upgrades)
  local function hasUpgrade(id) return upgrades and upgrades[id] ~= nil end
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
    if cargo.hazmat and not hasUpgrade('license_hazmat') then
      isLocked = true
      lockReason = 'Requires HazMat Carrier License ($35,000)'
    elseif trucksReq == 4 and not hasUpgrade('license_heavy_haul') then
      isLocked = true
      lockReason = 'Requires Abnormal & Mega Haul Permit ($50,000)'
    end

    -- Cold Chain bonus (+15%) if license_reefer is owned
    if cargo.category == 'reefer' and hasUpgrade('license_reefer') then
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
function M.calculatePenalty(slot, cargo, upgrades)
  local health = math.max(0, math.min(100, slot.cargoHealth or 100))
  if health >= 98 then return 0 end
  local lostFrac = (100 - health) / 100
  local penaltyFactor = cargo.fragile and 1.5 or 1.0
  if cargo.hazmat and health < 50 then
    penaltyFactor = penaltyFactor * 1.5 -- severe HazMat spill penalty
  end
  local penalty = math.floor(slot.grossPayout * lostFrac * penaltyFactor)

  -- Apply Heavy Vehicle Workshop Bay bonus (-30% penalty)
  if upgrades and upgrades.garage_repair_bay then
    penalty = math.floor(penalty * 0.70)
  end

  return math.min(slot.grossPayout, penalty)
end


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

M.HUBS = places.SEED
M.FUEL_PRICE = 1.85
M.FUEL_CAP = 400
M.CHECKPOINT_REWARDS = {} -- clearances debit catalog fees; no cash rewards
M.EXPEDITION_REWARDS = {} -- tours currently award passport progress, no cash
for _, t in ipairs(M.TOURS) do M.EXPEDITION_REWARDS[t.id] = 0 end
function M.board(epoch, upgrades)
  local jobs = {}
  for h, hub in ipairs(M.HUBS) do
    for i, job in ipairs(M.generateJobs(hub, epoch, nil, upgrades)) do
      -- Old short IDs collide across hubs/epochs. Protocol 3 IDs are globally unambiguous.
      job.id = 'job:' .. epoch .. ':' .. h .. ':' .. i
      jobs[#jobs + 1] = job
    end
  end
  return jobs
end
function M.resolve(id, epoch, upgrades)
  for _, job in ipairs(M.board(epoch, upgrades)) do if job.id == id then return job end end
end
return M
