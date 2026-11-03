-- luajit mod/tests/test_freight.lua
-- Tests for freight.lua:
-- 1. Deterministic generation across platforms and time epochs.
-- 2. Varied fleet requirements (1-truck solo, 2-truck duo, 3-truck convoy, 4-truck mega haul).
-- 3. Multi-consignment slot claiming.
-- 4. Cargo damage penalty calculation (including fragile and HazMat penalties).
-- 5. Team delivery finalization, company vault accounting, and reputation tracking.

local dir = (arg and arg[0] or ''):match('^(.*)[/\\]') or '.'
local T = dofile(dir .. '/testlib.lua')
local S = dofile(dir .. '/stubs.lua')

-- Stub JSON and GPS dependencies for test isolation
local storage = {}
function jsonReadFile(path) return storage[path] end
function jsonWriteFile(path, data) storage[path] = data; return true end

local gpsRoute = nil
package.loaded['beamngEarth/gps'] = {
  setDestination = function(lat, lon, name)
    gpsRoute = { lat = lat, lon = lon, name = name }
    return true
  end
}

local freight = require('beamngEarth/freight')
local places = require('beamngEarth/places')

--------------------------------------------------------------------------------
-- 1. Nearest Hub Detection
--------------------------------------------------------------------------------
do
  -- Slightly offset from Johannesburg center (-26.2041, 28.0473)
  local hub, dist = freight.findNearestHub(-26.2100, 28.0500)
  T.check(hub ~= nil, 'nearest hub found')
  T.check(hub.name == 'Johannesburg', 'identified Johannesburg as nearest hub')
  T.check(dist < 2000, 'distance within 2 km of city center')
end

--------------------------------------------------------------------------------
-- 2. Deterministic Consistency
--------------------------------------------------------------------------------
do
  local jhb = { name = 'Johannesburg', lat = -26.2041, lon = 28.0473 }
  local epoch = 1700000000

  local run1 = freight.generateJobs(jhb, epoch)
  local run2 = freight.generateJobs(jhb, epoch)

  T.check(#run1 == #freight.BOARD_DISTRIBUTION, 'board generated full job count')
  T.check(#run1 == #run2, 'both runs generated identical count')

  local identical = true
  for i = 1, #run1 do
    if run1[i].id ~= run2[i].id
       or run1[i].destination.name ~= run2[i].destination.name
       or run1[i].totalPayout ~= run2[i].totalPayout
       or run1[i].trucksRequired ~= run2[i].trucksRequired then
      identical = false
      break
    end
  end
  T.check(identical, 'two players at the same hub and epoch see 100% identical contracts')
end

--------------------------------------------------------------------------------
-- 3. Fleet Requirements Variation (1, 2, 3, 4 trucks)
--------------------------------------------------------------------------------
do
  local jhb = { name = 'Johannesburg', lat = -26.2041, lon = 28.0473 }
  local jobs = freight.generateJobs(jhb, 123456)

  local truckCounts = {}
  for _, j in ipairs(jobs) do
    truckCounts[j.trucksRequired] = (truckCounts[j.trucksRequired] or 0) + 1
  end

  T.check((truckCounts[1] or 0) >= 1, 'contains 1-truck solo/express jobs')
  T.check((truckCounts[2] or 0) >= 1, 'contains 2-truck duo/tandem jobs')
  T.check((truckCounts[3] or 0) >= 1, 'contains 3-truck convoy jobs')
  T.check((truckCounts[4] or 0) >= 1, 'contains 4-truck mega haul jobs')
end

--------------------------------------------------------------------------------
-- 4. Cargo Damage & Penalty Calculation
--------------------------------------------------------------------------------
do
  local slot = { grossPayout = 10000, cargoHealth = 100 }
  local normalCargo = { fragile = false, hazmat = false }
  local fragileCargo = { fragile = true, hazmat = false }
  local hazmatCargo = { fragile = false, hazmat = true }

  -- Undamaged: zero penalty
  T.check(freight.calculatePenalty(slot, normalCargo) == 0, 'undamaged cargo has zero penalty')

  -- 80% health (20% damage)
  slot.cargoHealth = 80
  local normalPen = freight.calculatePenalty(slot, normalCargo)
  local fragilePen = freight.calculatePenalty(slot, fragileCargo)

  T.check(normalPen == 2000, 'normal damage penalty is 20% of payout')
  T.check(fragilePen == 3000, 'fragile cargo has 1.5x penalty multiplier')

  -- Severe HazMat spill (<50% health)
  slot.cargoHealth = 40 -- 60% loss
  local hazmatPen = freight.calculatePenalty(slot, hazmatCargo)
  T.check(hazmatPen == 9000, 'severe HazMat damage incurs 1.5x penalty surcharge')
end

--------------------------------------------------------------------------------
-- 5. Multi-Consignment Co-op Lifecycle & Company Accounting
--------------------------------------------------------------------------------
do
  freight.reset()
  local initialVault = freight.getCompany().vault

  local jhb = { name = 'Johannesburg', lat = -26.2041, lon = 28.0473 }
  local jobs = freight.generateJobs(jhb, 9999)

  -- Find a 2-truck contract
  local duoJob = nil
  for _, j in ipairs(jobs) do
    if j.trucksRequired == 2 then duoJob = j; break end
  end
  T.check(duoJob ~= nil, 'found a 2-truck contract for co-op test')

  -- Player 1 accepts the contract and claims slot 1
  gpsRoute = nil
  local ok, err = freight.acceptContract(duoJob, 1, 'PlayerOne', 1)
  T.check(ok, 'contract accepted successfully')
  T.check(gpsRoute ~= nil and gpsRoute.name == duoJob.destination.name, 'GPS routed to delivery destination')

  -- Player 2 claims slot 2
  local claimOk = freight.claimSlot(2, 2, 'PlayerTwo')
  T.check(claimOk, 'teammate successfully claimed consignment slot 2')

  -- Player 1 delivers clean (100% health)
  freight.recordDamage(1, 0)

  -- Player 2 takes 20% damage
  freight.recordDamage(2, 20)

  -- Slot 1 delivered
  local d1Ok = freight.deliverSlot(1)
  T.check(d1Ok, 'slot 1 delivered')
  T.check(freight.getActiveContract() ~= nil, 'contract remains active until all slots delivered')

  -- Slot 2 delivered -> triggers contract finalization
  local d2Ok, manifest = freight.deliverSlot(2)
  T.check(d2Ok, 'slot 2 delivered')
  T.check(type(manifest) == 'table', 'manifest generated on final delivery')
  T.check(manifest.grossEarnings > 0, 'gross earnings recorded')
  T.check(manifest.totalPenalties > 0, 'damage penalty deducted for player 2')
  T.check(manifest.netPayout == manifest.grossEarnings - manifest.totalPenalties, 'net payout equals gross minus penalty')

  -- Check company vault was credited
  local newVault = freight.getCompany().vault
  T.check(newVault == initialVault + manifest.netPayout, 'company vault balance updated with net profit')
  T.check(freight.getCompany().completedDeliveries == 1, 'completed deliveries count incremented')
end

--------------------------------------------------------------------------------
-- 6. Remote Logistics Event Synchronization (BeamMP)
--------------------------------------------------------------------------------
do
  freight.reset()

  -- Remote sync_state
  freight.onRemoteLogistics({
    type = 'sync_state',
    state = {
      company = {
        name = 'OTBT Logistics Co-op',
        vault = 99000,
        completedDeliveries = 12,
        totalTonnesHauled = 240,
        totalEarnings = 145000,
        reputation = 95
      },
      activeContract = nil
    }
  })
  T.check(freight.getCompany().vault == 99000, 'remote sync_state updated company vault')
  T.check(freight.getCompany().completedDeliveries == 12, 'remote sync_state updated delivery count')

  -- Remote accept
  local dummyContract = {
    id = '#MP-9999',
    destination = { name = 'Durban Port', lat = -29.8587, lon = 31.0218 },
    cargo = { name = 'Mining Emulsion', category = 'tanker' },
    trucksRequired = 2,
    slots = {
      { slot = 1, status = 'in_transit', claimedBy = 'HostDriver' },
      { slot = 2, status = 'open', claimedBy = nil }
    }
  }
  freight.onRemoteLogistics({
    type = 'accept',
    contract = dummyContract,
    playerName = 'HostDriver'
  })
  local active = freight.getActiveContract()
  T.check(active ~= nil and active.id == '#MP-9999', 'remote accept set active contract')

  -- Remote claim slot 2
  freight.onRemoteLogistics({
    type = 'claim',
    jobId = '#MP-9999',
    slotIndex = 2,
    playerName = 'ConvoyMate'
  })
  T.check(active.slots[2].claimedBy == 'ConvoyMate', 'remote claim updated slot 2 owner')

  -- Remote finalize
  freight.onRemoteLogistics({
    type = 'finalize',
    jobId = '#MP-9999',
    netPayout = 15000,
    company = {
      name = 'OTBT Logistics Co-op',
      vault = 114000,
      completedDeliveries = 13,
      totalTonnesHauled = 280,
      totalEarnings = 160000,
      reputation = 97
    }
  })
  T.check(freight.getActiveContract() == nil, 'remote finalize cleared active contract')
  T.check(freight.getCompany().vault == 114000, 'remote finalize credited company vault')

  -- Set group name locally
  local setOk, newName = freight.setCompanyName('Kalahari Heavy Haulers')
  T.check(setOk, 'setCompanyName succeeded')
  T.check(freight.getCompany().name == 'Kalahari Heavy Haulers', 'company name updated locally')

  -- Remote group rename
  freight.onRemoteLogistics({
    type = 'set_company_name',
    name = 'Trans-Africa Convoy Co-op'
  })
  T.check(freight.getCompany().name == 'Trans-Africa Convoy Co-op', 'remote set_company_name synced')
end

--------------------------------------------------------------------------------
-- 7. Company Fleet Upgrades & Carrier Licensing
--------------------------------------------------------------------------------
do
  freight.reset()
  local comp = freight.getCompany()
  comp.vault = 100000 -- grant test funds
  comp.upgrades = {}

  -- Check initial upgrades catalog
  local list = freight.getUpgradesList()
  T.check(#list >= 8, 'upgrades catalog contains all licenses, garage bays, and certs')

  -- Generate jobs without HazMat license
  local jhb = { name = 'Johannesburg', lat = -26.2041, lon = 28.0473 }
  local jobs = freight.generateJobs(jhb, 100)
  local hazmatJob = nil
  for _, j in ipairs(jobs) do
    if j.cargo.hazmat then hazmatJob = j; break end
  end

  if hazmatJob then
    T.check(hazmatJob.locked == true, 'HazMat contract locked without carrier license')
    local acceptOk, err = freight.acceptContract(hazmatJob, 1, 'Driver 1')
    T.check(not acceptOk, 'blocked accepting locked HazMat contract')
  end

  -- Purchase HazMat license
  local buyOk, bought = freight.purchaseUpgrade('license_hazmat')
  T.check(buyOk and bought.id == 'license_hazmat', 'purchaseUpgrade succeeded')
  T.check(freight.hasUpgrade('license_hazmat'), 'hasUpgrade confirms license owned')
  T.check(comp.vault == 65000, 'vault debited correctly for HazMat license ($35,000)')

  -- Regenerate jobs: HazMat now unlocked
  local jobs2 = freight.generateJobs(jhb, 100)
  for _, j in ipairs(jobs2) do
    if j.cargo.hazmat then
      T.check(j.locked == false, 'HazMat contract unlocked with license')
      break
    end
  end

  -- Test Workshop Bay (-30% damage penalty)
  local testSlot = { grossPayout = 10000, cargoHealth = 80 }
  local cargo = { fragile = false, hazmat = false }
  local penaltyBefore = freight.calculatePenalty(testSlot, cargo)

  freight.purchaseUpgrade('garage_repair_bay')
  T.check(freight.hasUpgrade('garage_repair_bay'), 'garage_repair_bay owned')
  local penaltyAfter = freight.calculatePenalty(testSlot, cargo)
  T.check(penaltyAfter == math.floor(penaltyBefore * 0.70), 'heavy workshop bay applied 30% damage penalty discount')

  -- Test Remote upgrade synchronization
  freight.onRemoteLogistics({
    type = 'purchase_upgrade',
    upgradeId = 'license_reefer',
    cost = 25000,
    playerName = 'Teammate'
  })
  T.check(freight.hasUpgrade('license_reefer'), 'remote purchase_upgrade synced to local fleet')
end

--------------------------------------------------------------------------------
-- 8. Precision Reverse Docking Bonus
--------------------------------------------------------------------------------
do
  freight.reset()
  local comp = freight.getCompany()
  local startVault = comp.vault
  local startRep = comp.reputation

  local soloJob = {
    id = '#DK-101',
    origin = { name = 'Joburg Hub', lat = -26.2, lon = 28.0 },
    destination = { name = 'Pretoria Depot', lat = -25.7, lon = 28.2 },
    cargo = { name = 'Packaged Merchandise', category = 'dry', fragile = false, hazmat = false },
    trucksRequired = 1,
    weightPerTruckKg = 15000,
    totalWeightKg = 15000,
    distanceKm = 60,
    totalPayout = 10000,
    payoutPerTruck = 10000,
    slots = {
      {
        slot = 1,
        weightKg = 15000,
        claimedBy = 'ProDriver',
        status = 'open',
        cargoHealth = 100,
        damagePenalty = 0,
        grossPayout = 10000
      }
    },
    status = 'available'
  }

  local ok = freight.acceptContract(soloJob, 1, 'ProDriver', 1)
  T.check(ok, 'accepted solo job for docking test')

  -- Deliver with precision reverse docking = true
  local delOk, manifest = freight.deliverSlot(1, true)
  T.check(delOk, 'delivered slot with precision dock')
  T.check(type(manifest) == 'table', 'finalized contract manifest returned')
  T.check(manifest.dockBonus == 2000, 'awarded 20% precision docking bonus ($2,000 on $10,000 gross)')
  T.check(manifest.netPayout == 12000, 'net payout includes gross + 20% dock bonus ($12,000)')
  T.check(comp.vault == startVault + 12000, 'company vault received gross + precision bonus')
  T.check(comp.reputation >= startRep + 7, 'reputation rewarded with extra precision skill bonus (+7)')
end

T.done('test_freight')
