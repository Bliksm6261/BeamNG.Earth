local dir=(arg[0]:match('^(.*)[/\\]') or '.')
local T=dofile(dir..'/testlib.lua')
local plugin=dir..'/../../beammp/Server/BeamNGEarth/'
local json=dofile(plugin..'lib/otbt_json.lua')
OTBT_LEDGER_PATH=os.tmpname(); os.remove(OTBT_LEDGER_PATH)
local ids={[1]='account-A',[2]='account-B'}
local sent={}
MP={GetPlayerIdentifiers=function(pid) return {beammp=ids[pid]} end,
  TriggerClientEvent=function(pid,event,data) sent[#sent+1]={pid=pid,data=json.decode(data)} end}
Util={JsonEncode=json.encode,JsonDecode=json.decode}
local G=dofile(plugin..'main.lua')
G.players={[1]={name='A'},[2]={name='B'}}
local clock=os.time()
G.now=function() return clock end
local counter=0
local function intent(pid,t,fields,op)
  clock=clock+1
  counter=counter+1
  local m=fields or {}; m.type=t; m.opId=op or tostring(counter)
  return G.onLogistics(pid,m,pid==1 and 'A' or 'B')
end
local function company(pid) return G.account(pid,pid==1 and 'A' or 'B').company end
local function job(trucks)
  for _, j in ipairs(G.economy.board(math.floor(clock/3600),company(1).upgrades)) do
    if not j.locked and j.trucksRequired==trucks and not G.ledger.contracts[j.id] then return j end
  end
  error('no suitable job')
end
T.check(G.PROTO==3,'protocol bumped to three')
local sync=G.onLogistics(1,{type='sync_request'},'A')
T.check(sync.playerKey=='account-A' and sync.state.company.vault==25000,'join sync contains own company and stable identity')
T.check(not intent(1,'accept',{jobId='invented',contract={totalPayout=1e9}}),'unresolvable client job rejected')
T.check(not G.onLogistics(1,{type='refuel',litres=10},'A'),'mutation requires opId')
for _, field in ipairs({'litres','cargoHealth','slotIndex','stageIndex'}) do
  for _, value in ipairs({-1,math.huge,-math.huge,0/0}) do
    local fields={[field]=value,name='untouched'}
    T.check(not intent(1,'set_company_name',fields),'reject invalid numeric '..field)
  end
end
T.check(not intent(1,'accept',{jobId=job(1).id,slotIndex=1.5}),'fractional slot rejected')
local j=job(2)
local r=intent(1,'accept',{jobId=j.id,slotIndex=1,contract={totalPayout=99999999}})
T.check(r and r.contract.owner=='account-A' and r.contract.totalPayout==j.totalPayout,'accept resolves server contract')
local c=G.ledger.contracts[j.id]
T.check(c.slots[1].status=='claimed' and c.slots[2].status=='open','accept slot states')
T.check(sent[#sent].data.type=='slot_state','slot changes broadcast')
T.check(sent[#sent].data.contract.slots[1].claimedKey==nil and sent[#sent].data.contract.owner==nil
  and sent[#sent].data.contract.slots[1].claimedBy=='A','broadcast hides identity and retains name')
T.check(c.slots[1].claimedAt==clock,'server records accept time')
T.check(not intent(1,'deliver_slot',{jobId=j.id,slotIndex=1}),'instant delivery rejected')
T.check(not intent(1,'claim',{jobId=j.id,slotIndex=2}),'one undelivered slot per player')
T.check(not intent(1,'accept',{jobId=job(1).id}),'cannot accept another contract while holding a slot')
T.check(not intent(2,'abandon',{jobId=j.id}), 'B cannot abandon A contract')
T.check(not intent(2,'finalize',{jobId=j.id,netPayout=99999999}), 'B cannot finalize A contract')
T.check(not intent(2,'deliver_slot',{jobId=j.id,slotIndex=1}), 'B cannot deliver A slot')
T.check(not intent(2,'damage',{jobId=j.id,slotIndex=1,cargoHealth=0}), 'B cannot damage A slot')
T.check(intent(2,'claim',{jobId=j.id,slotIndex=2})~=nil,'co-op claim succeeds')
T.check(c.slots[2].claimedAt==clock,'claim records server time')
T.check(not intent(1,'claim',{jobId=j.id,slotIndex=2}),'claimed slot cannot be stolen')
intent(2,'damage',{jobId=j.id,slotIndex=2,cargoHealth=60,damagePenalty=-1e9})
local penalty=G.economy.calculatePenalty(c.slots[2],c.cargo,{})
intent(2,'damage',{jobId=j.id,slotIndex=2,cargoHealth=100})
T.check(c.slots[2].cargoHealth==60 and c.slots[2].damagePenalty==penalty,'health cannot recover, penalty server priced')
T.check(not intent(1,'finalize',{jobId=j.id,netPayout=99999999}),'premature finalize rejected')
local minimum=G.economy.minimumTransitSeconds(c)
T.check(minimum>=120 and minimum>=c.distanceKm/100*3600,'transit derived from distance and floor')
clock=c.slots[1].claimedAt+minimum-2
T.check(not intent(1,'deliver_slot',{jobId=j.id,slotIndex=1}),'delivery one second before minimum rejected')
local before=company(1).vault
T.check(intent(1,'deliver_slot',{jobId=j.id,slotIndex=1,netPayout=99999999,dockBonus=99999999,precisionDock=true})~=nil,'delivery at exact minimum accepted')
clock=math.max(clock,c.slots[2].claimedAt+minimum)
T.check(company(1).vault==before,'partial delivery pays nothing')
local last=intent(2,'deliver_slot',{jobId=j.id,slotIndex=2,netPayout=99999999},'last-delivery')
T.check(last.rev==G.ledger.rev,'stored reply revision matches committed ledger')
local ownerReply
for _, message in ipairs(sent) do
  if message.pid==1 and message.data.type=='ledger_state' then ownerReply=message.data end
end
T.check(ownerReply and ownerReply.company.vault==company(1).vault,'co-op completion sends owner personal authoritative balance')
local expected=j.totalPayout-penalty
T.check(company(1).vault==before+expected and company(2).vault==25000,'exact server payout goes to owner')
T.check(company(1).completedDeliveries==1 and company(1).totalEarnings==expected,'stats recorded once')
T.check(G.ledger.paid['contract:'..j.id] and c.status=='completed','contract marked paid')
T.check(not intent(2,'deliver_slot',{jobId=j.id,slotIndex=2}),'repeat delivery rejected')
T.check(not intent(1,'finalize',{jobId=j.id,netPayout=99999999}),'second finalize rejected')
local replay=intent(2,'deliver_slot',{jobId='forged',slotIndex=1},'last-delivery')
T.check(replay and replay.opId==last.opId and company(1).vault==before+expected,'op replay returns stored result without payment')
local vault=company(1).vault
local cost=12000
T.check(intent(1,'purchase_upgrade',{upgradeId='cert_safari_snorkel',cost=-1e9})~=nil,'forged negative upgrade cost ignored')
T.check(company(1).vault==vault-cost,'upgrade charged catalog price')
T.check(not intent(1,'purchase_upgrade',{upgradeId='cert_safari_snorkel',cost=0}),'owned upgrade rejected')
vault=company(2).vault
intent(2,'purchase_upgrade',{upgradeId='cert_safari_snorkel',cost=0})
T.check(company(2).vault==vault-cost,'zero upgrade cost ignored')
T.check(not intent(2,'purchase_upgrade',{upgradeId='license_heavy_haul',cost=0}),'insufficient funds rejected')
vault=company(1).vault
T.check(not intent(1,'refuel',{litres=-500,cost=-1e9}),'negative fuel rejected')
T.check(not intent(1,'refuel',{litres=math.huge}),'infinite fuel rejected')
T.check(not intent(1,'refuel',{litres=0/0}),'NaN fuel rejected')
T.check(not intent(1,'refuel',{litres=401}),'fuel cap enforced')
intent(1,'refuel',{litres=100,cost=0})
T.check(company(1).vault==vault-185,'fuel uses server price')
local cp=G.economy.CHECKPOINTS[1]
vault=company(1).vault
intent(1,'checkpoint_clear',{checkpointId=cp.id,reward=1e9,fee=-1e9})
T.check(company(1).vault==vault-cp.standardFee,'forged checkpoint reward ignored')
T.check(not intent(1,'checkpoint_clear',{checkpointId=cp.id}),'checkpoint once per epoch/player')
T.check(intent(2,'checkpoint_clear',{checkpointId=cp.id})~=nil,'checkpoint independent per player')
local realTime=os.time
clock=clock+3600
T.check(intent(1,'checkpoint_clear',{checkpointId=cp.id})~=nil,'checkpoint available in next epoch')
clock=clock-3600
local oldName=company(1).name
intent(2,'set_company_name',{name='B\nCompany',company={name='A stolen'},playerKey='account-A'})
T.check(company(1).name==oldName and company(2).name=='BCompany','rename only sender, strips controls')
intent(1,'set_company_name',{name=string.rep('x',80)})
T.check(#company(1).name==64,'name length capped')
local exp=G.economy.TOURS[1]
intent(1,'expedition_start',{expeditionId=exp.id,expedition={reward=1e9}})
T.check(not intent(2,'expedition_complete',{expeditionId=exp.id}),'B cannot complete A expedition')
T.check(not intent(2,'expedition_stage',{expeditionId=exp.id,stageIndex=2}),'B cannot advance A expedition')
T.check(not intent(1,'expedition_complete',{expeditionId=exp.id}),'expedition requires stages')
T.check(not intent(1,'expedition_stage',{expeditionId=exp.id,stageIndex=99}),'stage skipping rejected')
for i=2,#exp.checkpoints do intent(1,'expedition_stage',{expeditionId=exp.id,stageIndex=i}) end
vault=company(1).vault
T.check(intent(1,'expedition_complete',{expeditionId=exp.id,reward=1e9})~=nil,'owner completes ordered expedition')
T.check(company(1).vault==vault and G.ledger.paid['expedition:'..exp.id],'expedition server reward recorded once')
T.check(not intent(1,'expedition_complete',{expeditionId=exp.id}),'repeat expedition rejected')
local abandoned=job(1)
intent(1,'accept',{jobId=abandoned.id})
T.check(intent(1,'abandon',{jobId=abandoned.id})~=nil and G.ledger.contracts[abandoned.id].slots[1].status=='abandoned','owner abandonment transitions remaining slots')
local oldVault=company(2).vault
company(2).vault=0
T.check(not intent(2,'refuel',{litres=100}),'insufficient fuel funds rejected')
company(2).vault=oldVault
-- Test rename failure separately from open failure, retaining the accepted memory state.
local rename=os.rename
os.rename=function() return nil,'simulated rename failure' end
local prior=company(1).vault
intent(1,'refuel',{litres=10})
T.check(company(1).vault==prior-18,'rename failure keeps in-memory debit')
os.rename=rename
G.saveLedger()
vault=company(1).vault
local file=io.open(OTBT_LEDGER_PATH,'r'); T.check(file~=nil,'ledger written'); if file then file:close() end
G=dofile(plugin..'main.lua')
G.now=function() return clock end
T.check(company(1).vault==vault and G.ledger.paid['contract:'..j.id],'reload restores balance and paid set')
T.check(not intent(1,'finalize',{jobId=j.id}),'restart cannot repay contract')
T.check(not intent(1,'checkpoint_clear',{checkpointId=cp.id}),'restart retains checkpoint paid protection')
T.check(not intent(1,'expedition_start',{expeditionId=exp.id}),'restart retains expedition paid protection')
local replay2=intent(2,'deliver_slot',{jobId=j.id,slotIndex=2},'last-delivery')
T.check(replay2 and company(1).vault==vault,'restart retains op replay protection')
ids[1]='new-account'
T.check(company(1).vault==25000,'recycled pid cannot inherit balance')
ids[1]=nil
T.check(G.playerKey(1,'A')=='guest:A','guest identity uses name')
local f=assert(io.open(OTBT_LEDGER_PATH,'w')); f:write('{corrupt'); f:close()
G=dofile(plugin..'main.lua')
T.check(next(G.ledger.players)==nil,'corrupt ledger starts fresh')
f=io.open(OTBT_LEDGER_PATH..'.bad','r')
T.check(f and f:read('*a')=='{corrupt','corrupt ledger preserved'); if f then f:close() end
-- Schema corruption and filesystem failures are handled without crashing.
f=assert(io.open(OTBT_LEDGER_PATH,'w')); f:write(json.encode({rev=1,players={broken={}},contracts={},paid={}})); f:close()
G=dofile(plugin..'main.lua')
T.check(next(G.ledger.players)==nil,'invalid ledger schema starts fresh')
local open=io.open
io.open=function() return nil,'simulated open failure' end
local fresh=G.account(1,'A').company
local starting=fresh.vault
intent(1,'refuel',{litres=10})
T.check(fresh.vault==starting-18,'write failure keeps accepted in-memory state')
io.open=open
local events={}
MP.RegisterEvent=function(event,handler) events[event]=handler end
MP.CreateEventTimer=function() end
MP.GetPlayerName=function(pid) return pid==1 and 'A' or 'B' end
G=dofile(plugin..'main.lua')
T.check(events.bngeLogistics=='BNGE_onLogistics','logistics wire handler registered')
BNGE_onPose(1,json.encode({v=3,aLat=0,aLon=0,lat=0,lon=0}))
local found=false
for _, message in ipairs(sent) do
  if message.pid==1 and message.data.type=='sync_state' then found=message.data.state.company.vault==25000 end
end
T.check(found,'first pose sends authoritative personal sync')
BNGE_onLogistics(1,json.encode({type='refuel',opId='wire-fuel',litres=10,cost=0}))
T.check(sent[#sent].pid==1 and sent[#sent].data.type=='ledger_state' and sent[#sent].data.company.vault==24982,'wire intent decoded and personal authority returned')
-- Rate limiting counts invalid intents too, before any account/ledger writes.
clock=clock+1; G.now=function() return clock end
local priorRev=G.ledger.rev
for i=1,20 do
  T.check(G.onLogistics(1,{type='set_company_name',name='Rate',opId='rate-'..i},'A')~=nil,'within rate limit '..i)
end
T.check(G.onLogistics(2,{type='sync_request'},'B')~=nil,'rate limits independent per identity')
local rev=G.ledger.rev
T.check(not G.onLogistics(1,{type='set_company_name',name='Flood',opId='flood'},'A') and G.ledger.rev==rev,'21st intent rejected without write')
clock=clock+1
T.check(G.onLogistics(1,{type='set_company_name',name='Next',opId='next'},'A')~=nil,'new rate window accepted')
for i=1,210 do intent(1,'set_company_name',{name='Bounded'},'bounded-'..i) end
local account=G.account(1,'A'); local count=0
for _ in pairs(account.ops) do count=count+1 end
T.check(count==200 and #account.opOrder==200 and not account.ops['bounded-1'],'operation history capped at 200')
rev=G.ledger.rev
local recent=intent(1,'set_company_name',{name='Must not apply'},'bounded-210')
T.check(recent and recent.opId=='bounded-210' and G.ledger.rev==rev and account.company.name=='Bounded','recent replay returns result without mutation')
G=dofile(plugin..'main.lua'); G.now=function() return clock end
T.check(intent(1,'set_company_name',{name='Must not apply'},'bounded-210')~=nil and G.account(1,'A').company.name=='Bounded','capped history replays after restart')
local migrated=G.account(1,'A')
migrated.opOrder=nil
for i=1,250 do migrated.ops['legacy-'..i]={type='ledger_state',rev=i} end
G.saveLedger(); G=dofile(plugin..'main.lua')
local retained=0
for _ in pairs(G.account(1,'A').ops) do retained=retained+1 end
T.check(retained==200,'legacy operation maps capped on load')
os.remove(OTBT_LEDGER_PATH); os.remove(OTBT_LEDGER_PATH..'.bad'); os.remove(OTBT_LEDGER_PATH..'.tmp')
T.done('test_beammp_ledger')
