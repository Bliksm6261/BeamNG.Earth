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
end

T.done('test_freight')
