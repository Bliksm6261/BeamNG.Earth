local dir=(arg[0]:match('^(.*)[/\\]') or '.')
local T=dofile(dir..'/testlib.lua')
dofile(dir..'/stubs.lua')
package.loaded['beamngEarth/gps']={setDestination=function() end}
local freight=require('beamngEarth/freight')
local places=require('beamngEarth/places')
local economy=dofile(dir..'/../../beammp/Server/BeamNGEarth/otbt_economy.lua')
local company=freight.getCompany()
for _, upgrades in ipairs({{}, {license_reefer={},license_hazmat={},license_heavy_haul={},garage_repair_bay={}}}) do
  company.upgrades=upgrades
  for _, epoch in ipairs({100,498000}) do
    for _, hub in ipairs(places.SEED) do
      local localJobs=freight.generateJobs(hub,epoch)
      local serverJobs=economy.generateJobs(hub,epoch,nil,upgrades)
      for i, job in ipairs(localJobs) do
        local other=serverJobs[i]
        T.check(job.totalPayout==other.totalPayout and job.distanceKm==other.distanceKm
          and job.totalWeightKg==other.totalWeightKg and job.cargo.id==other.cargo.id
          and job.locked==other.locked,'client/server generator prices, cargo, weight and locks agree')
      end
    end
  end
end
company.upgrades={}
-- Exercise the actual MP sender: amount fields removed and op IDs fresh.
MPCoreNetwork={isMPSession=function() return true end}
local session=require('beamngEarth/mpsession')
local messages={}
jsonEncode=function(value) return value end
TriggerServerEvent=function(event,value) messages[#messages+1]=value end
T.check(session.isSessionActive(),'MP detection')
session.sendLogisticsEvent({type='refuel',litres=10,cost=-500,company={vault=1e9}})
session.sendLogisticsEvent({type='refuel',litres=10})
T.check(messages[1].cost==nil and messages[1].company==nil and messages[1].litres==10,'MP sends intents without amounts')
T.check(messages[1].opId~=messages[2].opId,'fresh operation IDs')
local vault=company.vault
freight.purchaseUpgrade('cert_safari_snorkel')
T.check(company.vault==vault and not company.upgrades.cert_safari_snorkel,'MP purchase does not debit or grant locally')
freight.setCompanyName('Pending')
T.check(company.name~='Pending','MP name awaits authority')
local j=economy.board(math.floor(os.time()/3600),{})[1]
freight.acceptContract(j,1,'A',1)
T.check(freight.getActiveContract()==nil,'MP accept awaits authority')
freight.onRemoteLogistics({type='ledger_state',company={name='Server',vault=123,reputation=100,upgrades={}},contract=j})
T.check(freight.getCompany().vault==123,'ledger reply applies authoritative balance')
local checkpoints=require('beamngEarth/checkpoints')
checkpoints.clearCheckpoint(checkpoints.CHECKPOINTS[1].id,0,0)
T.check(freight.getCompany().vault==123 and messages[#messages].type=='checkpoint_clear','MP checkpoint leaves balance to server')
local expeditions=require('beamngEarth/expeditions')
expeditions.startExpedition('sani_pass')
T.check(messages[#messages].expeditionId=='sani_pass' and expeditions.getActiveTour()==nil,'MP expedition start awaits authority')
local tour=economy.TOURS[1]; tour.stageIndex=2; tour.status='active'
expeditions.onRemoteExpedition({type='ledger_state',expedition=tour})
T.check(expeditions.getActiveTour().id==tour.id and expeditions.getCheckpointIndex()==2,'expedition ledger applies server progress')
expeditions.advanceCheckpoint()
T.check(expeditions.getCheckpointIndex()==2 and messages[#messages].stageIndex==3,'MP stage waits for authoritative update')
-- Saved replies are intentionally replayable; clients must not roll back later state.
freight.onRemoteLogistics({type='ledger_state',rev=10,playerKey='A',company={vault=1000,upgrades={}}})
freight.onRemoteLogistics({type='ledger_state',rev=9,company={vault=99999999,upgrades={}}})
T.check(freight.getCompany().vault==1000,'stale op reply cannot roll balance back')
freight.onRemoteLogistics({type='purchase_upgrade',cost=-1e9,upgradeId='forged'})
T.check(freight.getCompany().vault==1000 and not freight.getCompany().upgrades.forged,'MP ignores legacy economy broadcasts')
local active=economy.resolve(j.id,math.floor(os.time()/3600),{})
active.status='in_transit'
freight.onRemoteLogistics({type='slot_state',rev=9,contract=active})
T.check(freight.getActiveContract()==nil,'stale slot broadcast cannot restore completed contract')
expeditions.onRemoteExpedition({type='ledger_state',rev=10})
expeditions.onRemoteExpedition({type='ledger_state',rev=9,expedition=tour})
T.check(expeditions.getActiveTour()==nil,'stale reply cannot restore completed expedition')
-- Every MP economy action waits for authority, including delivery and fuel.
freight.onRemoteLogistics({type='ledger_state',rev=11,playerKey='A',company={vault=1000,upgrades={}},contract=active})
for _, action in ipairs({
  function() freight.recordDamage(1,25) end,
  function() freight.deliverSlot(1,true) end,
  function() freight.finalizeContract() end,
  function() freight.abandonContract() end,
  function() freight.claimSlot(1,1,'A') end
}) do
  action()
  T.check(freight.getCompany().vault==1000 and freight.getActiveContract()~=nil,'MP action leaves local economy unchanged')
end
local damageJob
for _, candidate in ipairs(economy.board(math.floor(os.time()/3600),{})) do
  if candidate.trucksRequired>=2 then damageJob=candidate; break end
end
damageJob.status='in_transit'
damageJob.slots[1].status='claimed'; damageJob.slots[1].claimedKey='B'
damageJob.slots[2].status='claimed'; damageJob.slots[2].claimedKey='A'
freight.onRemoteLogistics({type='ledger_state',rev=12,playerKey='A',company={vault=1000,upgrades={}},contract=damageJob})
local oldClock, oldDamage=os.clock, freight.getVehicleDamage
local clockValue, damage=100,0
os.clock=function() return clockValue end
freight.getVehicleDamage=function() return damage end
local veh={getID=function() return 123 end}
freight.update(nil,nil,veh)
clockValue=101; damage=1000
freight.update(nil,nil,veh)
T.check(messages[#messages].type=='damage' and messages[#messages].slotIndex==2,'automatic MP damage targets own stable-key slot')
os.clock,freight.getVehicleDamage=oldClock,oldDamage
freight._setDriverStatus({fuelLiters=300})
freight.refuelVehicle(places.SEED[1].lat,places.SEED[1].lon)
T.check(messages[#messages].type=='refuel' and messages[#messages].litres==100 and freight.getCompany().vault==1000,'MP refuel sends litres and awaits debit')
MPCoreNetwork=nil
T.check(not session.isSessionActive(),'SP detection')
T.done('test_beammp_economy_client')
