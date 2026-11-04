-- Tests for checkpoints.lua:
-- 1. Regional Checkpoint Catalog (Toll Plazas, Border Posts, Weigh Stations).
-- 2. Proximity detection & corridor tracking.
-- 3. Highway Toll Plaza clearance, HazMat surcharges, and fleet reputation rebates.
-- 4. Cross-border customs & SADC Carnet Carrier License fast-track clearance.
-- 5. Commercial axle weigh station compliance and Heavy Haul permit exemptions.

local dir = (arg and arg[0] or ''):match('^(.*)[/\\]') or '.'
local T = dofile(dir .. '/testlib.lua')
package.loaded['beamngEarth/settings'] = { get = function(key) return key == 'otbtLogisticsEnabled' end }

-- Stub dependencies
local storage = {}
function jsonReadFile(path) return storage[path] end
function jsonWriteFile(path, data) storage[path] = data; return true end

package.loaded['beamngEarth/gps'] = {
  setDestination = function() return true end
}

local freight = require('beamngEarth/freight')
local checkpoints = require('beamngEarth/checkpoints')

--------------------------------------------------------------------------------
-- 1. Catalog Verification
--------------------------------------------------------------------------------
do
  local list = checkpoints.CHECKPOINTS
  T.check(#list >= 12, 'checkpoint catalog contains at least 12 regional checkpoints')

  local counts = { border = 0, toll = 0, weigh = 0 }
  for _, cp in ipairs(list) do
    T.check(cp.id ~= nil, 'checkpoint has valid id')
    T.check(cp.type == 'border' or cp.type == 'toll' or cp.type == 'weigh', 'valid checkpoint type')
    T.check(cp.name ~= nil, 'checkpoint has descriptive name')
    T.check(cp.lat ~= nil and cp.lon ~= nil, 'checkpoint has geographic coordinates')
    counts[cp.type] = (counts[cp.type] or 0) + 1
  end

  T.check(counts.border >= 5, 'contains major cross-border customs posts (Beitbridge, Lebombo, etc.)')
  T.check(counts.toll >= 4, 'contains major freight highway toll plazas (Mooi River, Tugela, etc.)')
  T.check(counts.weigh >= 3, 'contains commercial weigh stations (Heidelberg, Mantsole, etc.)')
end

--------------------------------------------------------------------------------
-- 2. Proximity Detection
--------------------------------------------------------------------------------
do
  -- Mooi River Toll Plaza: (-29.2064, 30.0053)
  local cp, dist = checkpoints.findNearestCheckpoint(-29.2060, 30.0050)
  T.check(cp ~= nil, 'found nearest checkpoint')
  T.check(cp.id == 'toll_mooi_river', 'identified Mooi River Toll Plaza')
  T.check(dist < 100, 'distance calculated accurately (<100m)')
end

--------------------------------------------------------------------------------
-- 3. Toll Plaza Clearance & Surcharges
--------------------------------------------------------------------------------
do
  freight.reset()
  local comp = freight.getCompany()
  comp.vault = 10000
  comp.reputation = 80 -- Normal rep, no commercial rebate
  comp.upgrades = {}

  -- Standard Toll: Mooi River ($38)
  local ok, res = checkpoints.clearCheckpoint('toll_mooi_river')
  T.check(ok, 'cleared Mooi River toll')
  T.check(res.feePaid == 38, 'standard toll fee $38 deducted')
  T.check(comp.vault == 10000 - 38, 'company vault updated after toll payment')

  -- High-reputation commercial rebate (>= 90 rep gets 10% discount)
  comp.reputation = 95
  local ok2, res2 = checkpoints.clearCheckpoint('toll_mooi_river')
  T.check(ok2, 'cleared toll with high fleet reputation')
  T.check(res2.feePaid == math.floor(38 * 0.90), 'received 10% commercial reputation rebate ($34)')
end

--------------------------------------------------------------------------------
-- 4. Cross-Border Customs & SADC Carnet Carrier License
--------------------------------------------------------------------------------
do
  freight.reset()
  local comp = freight.getCompany()
  comp.vault = 10000
  comp.reputation = 85
  comp.upgrades = {}

  -- 1. Without Cross-Border License: standard customs duty ($85 for Beitbridge)
  local ok, res = checkpoints.clearCheckpoint('border_beitbridge')
  T.check(ok, 'cleared Beitbridge border without license')
  T.check(res.exempt == false, 'customs duty required without carrier license')
  T.check(res.feePaid == 85, 'standard customs duty of $85 paid')
  T.check(comp.vault == 10000 - 85, 'vault updated for border fee')

  -- 2. With Cross-Border Carrier License (SADC Carnet): $0 fee + 2 reputation
  comp.vault = 10000
  local repBefore = comp.reputation
  comp.upgrades = { license_cross_border = { purchasedAt = 1000, cost = 40000 } }

  local ok2, res2 = checkpoints.clearCheckpoint('border_beitbridge')
  T.check(ok2, 'cleared border with SADC Carnet carrier license')
  T.check(res2.exempt == true, 'exempt from border duty with SADC Carnet')
  T.check(res2.feePaid == 0, '$0 fee charged')
  T.check(res2.reputationDelta == 2, 'earned +2 reputation for regulatory compliance')
  T.check(comp.reputation == repBefore + 2, 'company reputation increased')
  T.check(comp.vault == 10000, 'vault was not charged')
end

--------------------------------------------------------------------------------
-- 5. Commercial Weigh Station & Heavy Haul Permit
--------------------------------------------------------------------------------
do
  freight.reset()
  local comp = freight.getCompany()
  comp.vault = 20000
  comp.reputation = 90
  comp.upgrades = {}

  -- 1. Standard legal load (<= 34,000 kg) passes with no fine
  local ok, res = checkpoints.clearCheckpoint('weigh_heidelberg')
  T.check(ok, 'weighed in at Heidelberg')
  T.check(res.finePaid == 0, 'legal axle weight passed with zero citation')

  -- 2. Overweight load without Heavy Haul permit: $2,500 citation and -5 reputation
  local fakeHeavyContract = {
    id = '#HW-99',
    slots = { { slot = 1, weightKg = 28000 } } -- Tare 18t + 28t = 46,000 kg > 34,000 kg
  }
  freight.onRemoteLogistics({
    type = 'sync_state',
    state = { company = comp, activeContract = fakeHeavyContract }
  })

  local ok2, res2 = checkpoints.clearCheckpoint('weigh_heidelberg')
  T.check(ok2, 'processed overweight vehicle')
  T.check(res2.finePaid == 2500, 'issued $2,500 non-compliance citation')
  T.check(res2.reputationDelta == -5, 'deducted -5 reputation for safety non-compliance')
  T.check(comp.vault == 20000 - 2500, 'citation deducted from company vault')
  T.check(comp.reputation == 85, 'reputation penalized')

  -- 3. Overweight load WITH Heavy Haul permit: exempt with zero fine
  comp.upgrades = { license_heavy_haul = { purchasedAt = 1000, cost = 50000 } }
  local vaultNow = comp.vault
  local repNow = comp.reputation

  local ok3, res3 = checkpoints.clearCheckpoint('weigh_heidelberg')
  T.check(ok3, 'processed heavy vehicle with Heavy Haul permit')
  T.check(res3.finePaid == 0, 'permit verified: zero fine issued')
  T.check(comp.vault == vaultNow, 'vault unaffected')
  T.check(comp.reputation == repNow, 'reputation preserved')
end

T.done('test_checkpoints')
