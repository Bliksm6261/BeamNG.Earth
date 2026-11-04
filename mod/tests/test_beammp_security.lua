local dir=arg[0]:match('^(.*)[/\\]') or '.'
local T=dofile(dir..'/testlib.lua')
local root=dir..'/../../beammp/Server/BeamNGEarth/'
local json=dofile(root..'lib/otbt_json.lua')
OTBT_LEDGER_PATH=os.tmpname(); os.remove(OTBT_LEDGER_PATH)
local ids={[1]='one',[2]='two'}
local sent, decodeCalls={},0
Util={JsonEncode=function(v) return json.encode(v):gsub('{}','null') end,
 JsonDecode=function() decodeCalls=decodeCalls+1; error('engine decoder must not be used') end}
MP={GetPlayerIdentifiers=function(pid) return {beammp=ids[pid]} end,
 GetPlayerName=function(pid) return 'P'..pid end,RegisterEvent=function() end,CreateEventTimer=function() end,
 TriggerClientEvent=function(pid,event,data) sent[#sent+1]={pid=pid,event=event,data=json.decode(data)} end}
local G,now,op
local function fresh()
 os.remove(OTBT_LEDGER_PATH); os.remove(OTBT_LEDGER_PATH..'.bad')
 G=dofile(root..'main.lua'); now=360000; op=0; G.now=function() return now end
end
local function send(pid,t,m)
 now=now+1; op=op+1; m=m or {}; m.type=t; m.opId='op-'..op
 return G.onLogistics(pid,m,'P'..pid)
end
local function account(pid) return G.account(pid,'P'..pid) end
local function job(n)
 for _,j in ipairs(G.economy.board(math.floor(now/3600),{})) do
  if j.trucksRequired==n and not j.locked and not G.ledger.contracts[j.id] then return j end
 end
 error('no job')
end
local function accept(n)
 local j=job(n); assert(send(1,'accept',{jobId=j.id})); return G.ledger.contracts[j.id]
end
local function pose(pid,c) G.players[pid]={name='P'..pid,lat=c.destination.lat,lon=c.destination.lon,poseAt=now+1} end
fresh()
-- #1: file codec remains local even when engine codec emits null for empty maps.
account(1); G.saveLedger()
local f=assert(io.open(OTBT_LEDGER_PATH)); local bytes=f:read('*a'); f:close()
T.check(bytes:find('"upgrades":{}',1,true) and bytes:find('"ops":{}',1,true),'#1 empty maps saved as objects')
G=dofile(root..'main.lua'); G.now=function() return now end
T.check(account(1).company.vault==25000 and not io.open(OTBT_LEDGER_PATH..'.bad'),'#1 null-emitting Util does not wipe ledger')
T.check(decodeCalls==0,'#1 file load avoids engine decoder')
-- #2: time alone, missing/stale/far poses, hourly cap, and persistence of cap.
local c=accept(1); now=now+G.economy.minimumTransitSeconds(c)
T.check(not send(1,'deliver_slot',{jobId=c.id,slotIndex=1}),'#2 no pose rejects delivery')
pose(1,c); G.players[1].poseAt=now-61
T.check(not send(1,'deliver_slot',{jobId=c.id,slotIndex=1}),'#2 stale pose rejected')
pose(1,c); G.players[1].lat=G.players[1].lat+1
T.check(not send(1,'deliver_slot',{jobId=c.id,slotIndex=1}),'#2 distant pose rejected')
local p=account(1); p.paidHour=math.floor((now+1)/3600); p.paidCount=G.economy.MAX_PAID_CONTRACTS_PER_HOUR
pose(1,c)
T.check(not send(1,'deliver_slot',{jobId=c.id,slotIndex=1}) and c.slots[1].status=='claimed','#2 hourly cap rejects before mutation')
p.paidCount=p.paidCount-1; pose(1,c)
T.check(send(1,'deliver_slot',{jobId=c.id,slotIndex=1}) and p.paidCount==6,'#2 fresh nearby pose permits final capped payment')
G=dofile(root..'main.lua'); G.now=function() return now end
T.check(account(1).paidCount==6,'#2 payout cap survives restart')
-- #3 guests are session-only, pid-keyed, and read-only; persisted cap enforced safely.
T.check(G.playerKey(3,'victim')~=G.playerKey(4,'victim'),'#3 same-name guests do not share accounts')
T.check(send(3,'sync_request')~=nil and not send(3,'accept',{jobId=job(1).id}),'#3 guest can view but cannot trade')
T.check(not send(3,'refuel',{litres=1}) and not send(3,'set_company_name',{name='stolen'}),'#3 guest money and company mutations rejected')
G.saveLedger(); f=assert(io.open(OTBT_LEDGER_PATH)); bytes=f:read('*a'); f:close()
T.check(not bytes:find('guest:',1,true),'#3 guests never reach disk')
G.economy.MAX_ACCOUNTS=1
T.check(not send(2,'sync_request') and not G.syncState(2,'P2'),'#3 account cap is nil-safe for sync and intents')
G.economy.MAX_ACCOUNTS=500
-- #4/#9 reject every untrusted ID before state changes/copy/echo.
local old=account(1).company.name
for _,field in ipairs({'opId','jobId','contractId','upgradeId','expeditionId','checkpointId'}) do
 for _,value in ipairs({string.rep('x',65),'bad/id',{{{{}}}}}) do
  local m={type='set_company_name',opId='valid',name='changed'}; m[field]=value
  T.check(not G.onLogistics(1,m,'P1') and account(1).company.name==old,'#4/#9 invalid '..field)
  now=now+1
 end
end
local r=send(1,'set_company_name',{name='good',expeditionId='not-catalog',checkpointId='not-catalog'})
T.check(r and not r.expeditionId and not r.checkpointId,'#4 unrelated IDs are not echoed or retained')
-- #5 board restoration and old contract purge.
fresh(); c=accept(1)
T.check(send(1,'abandon',{jobId=c.id}) and not G.ledger.contracts[c.id],'#5 abandoned undelivered job removed')
T.check(send(1,'accept',{jobId=c.id})~=nil,'#5 another accept can resolve restored job')
c=G.ledger.contracts[c.id]; c.status='completed'; now=now+3600; G.maintainLedger()
T.check(not G.ledger.contracts[c.id],'#5 old finished contract purged')
-- #6 UTF-8 boundary and invalid sequences under LuaJIT (no utf8 global).
T.check(send(1,'set_company_name',{name=string.rep('a',63)..'é'}) and account(1).company.name==string.rep('a',63),'#6 multibyte name truncates at boundary')
T.check(not send(1,'set_company_name',{name='bad'..string.char(255)}),'#6 invalid UTF-8 rejected')
T.check(send(1,'set_company_name',{name=string.rep('a',63)..'éZ'}) and account(1).company.name==string.rep('a',63),'#6 truncated name remains a prefix')
G.saveLedger(); G=dofile(root..'main.lua'); G.now=function() return now end
T.check(account(1).company.name==string.rep('a',63),'#6 boundary name persists across reload')
-- #7 owner can release another claimant, claims expire; penalties bounded and reputation isolated.
fresh(); c=accept(2); send(2,'claim',{jobId=c.id,slotIndex=2})
T.check(not send(2,'release_slot',{jobId=c.id,slotIndex=1}),'#7 non-owner cannot release')
send(2,'damage',{jobId=c.id,slotIndex=2,cargoHealth=0})
T.check(send(1,'release_slot',{jobId=c.id,slotIndex=2}) and c.slots[2].status=='open' and not c.slots[2].claimedKey,'#7 owner releases claimant')
T.check(c.slots[2].cargoHealth==100 and c.slots[2].damagePenalty==0,'#7 released cargo cannot retain saboteur damage')
send(2,'claim',{jobId=c.id,slotIndex=2})
send(2,'damage',{jobId=c.id,slotIndex=2,cargoHealth=0})
now=now+math.max(3*G.economy.minimumTransitSeconds(c),1800)+1; G.maintainLedger()
T.check(c.slots[1].status=='open' and c.slots[2].status=='open','#7 idle claims expire')
T.check(c.slots[2].cargoHealth==100 and c.slots[2].damagePenalty==0,'#7 expired claim clears prior claimant damage')
send(1,'claim',{jobId=c.id,slotIndex=1}); send(2,'claim',{jobId=c.id,slotIndex=2})
account(1).company.reputation=50; account(2).company.reputation=50
send(2,'damage',{jobId=c.id,slotIndex=2,cargoHealth=0})
T.check(c.slots[2].damagePenalty<=c.slots[2].grossPayout,'#7 claimant penalty cannot consume another slot payout')
now=now+G.economy.minimumTransitSeconds(c); pose(1,c); send(1,'deliver_slot',{jobId=c.id,slotIndex=1}); pose(2,c)
send(2,'deliver_slot',{jobId=c.id,slotIndex=2})
T.check(account(1).company.reputation>=50 and account(2).company.reputation==45,'#7 claimant damage only reduces claimant reputation')
T.check(not send(1,'release_slot',{jobId=c.id,slotIndex=2}),'#7 delivered slot cannot be released')
-- #8 player-scoped expedition payments and timed ordered stages; table reward only.
fresh(); local tour=G.economy.TOURS[1]; local reward=123; G.economy.EXPEDITION_REWARDS[tour.id]=reward
send(1,'expedition_start',{expeditionId=tour.id})
T.check(not send(1,'expedition_stage',{expeditionId=tour.id,stageIndex=2}),'#8 instant stage rejected')
for i=2,#tour.checkpoints do now=now+G.economy.MIN_STAGE_SECONDS; assert(send(1,'expedition_stage',{expeditionId=tour.id,stageIndex=i})) end
T.check(not send(1,'expedition_complete',{expeditionId=tour.id}),'#8 final stage also requires time')
now=now+G.economy.MIN_STAGE_SECONDS; local vault=account(1).company.vault
T.check(send(1,'expedition_complete',{expeditionId=tour.id,reward=999999}) and account(1).company.vault==vault+reward,'#8 server table reward paid')
T.check(send(2,'expedition_start',{expeditionId=tour.id}) and not send(1,'expedition_start',{expeditionId=tour.id}),'#8 payment blocks only same account')
-- #9 handlers reject oversize BEFORE decoder; depth-bounded parser rejects small deep packets.
local decode=G.decode; local calls=0; G.decode=function(data) calls=calls+1; return decode(data) end
BNGE_onPose(7,string.rep('[',8193)); BNGE_onLogistics(7,string.rep('[',8193))
T.check(calls==0,'#9 both handlers reject oversized data before decoding')
T.check(pcall(BNGE_onLogistics,7,string.rep('[',110)..'0'..string.rep(']',110)),'#9 deep JSON cannot escape handler')
T.check(decodeCalls==0,'#9 engine recursive decoder is bypassed')
local beforePose=G.players[1] and G.players[1].poseAt
BNGE_onPose(1,json.encode({v=3,aLat=0,aLon=0,lat=0,lon=0}))
local validAt=G.players[1].poseAt; now=now+61
BNGE_onPose(1,json.encode({v=1,aLat=0,aLon=0,lat=0,lon=0}))
T.check(G.players[1].poseAt==validAt,'#2 invalid pose cannot refresh delivery freshness')
-- #10 unrelated intents cannot select another company contract; co-op replies redact keys.
fresh(); c=accept(2)
r=send(2,'refuel',{contractId=c.id,litres=0.5})
T.check(r and not r.contract and not account(2).ops[r.opId].contract,'#10 unrelated intent cannot leak victim contract')
r=send(2,'claim',{jobId=c.id,slotIndex=2})
T.check(r and not r.contract.owner and not r.contract.slots[1].claimedKey and not r.contract.slots[2].claimedKey,'#10 claimant reply strips stable account identifiers')
-- #11 minimum fractional fuel charge persists immediately.
vault=account(2).company.vault; send(2,'refuel',{litres=0.001})
T.check(account(2).company.vault==vault-1,'#11 positive fractional refuel costs at least one')
-- #12 first pose sync bypasses exhausted intent rate, with nil-safe cap failure.
fresh(); for i=1,20 do G.onLogistics(1,{type='set_company_name',name='Rate',opId='rate-'..i},'P1') end
sent={}; BNGE_onPose(1,json.encode({v=3,aLat=0,aLon=0,lat=0,lon=0}))
local found=false; for _,m in ipairs(sent) do if m.pid==1 and m.data.type=='sync_state' then found=true end end
T.check(found,'#12 exhausted rate limit cannot suppress join sync')
G.economy.MAX_ACCOUNTS=1
T.check(pcall(BNGE_onPose,2,json.encode({v=3,aLat=0,aLon=0,lat=0,lon=0})),'#12 unavailable join sync is nil-safe')
-- #13 five-second sync limit; nonmoney work debounces, money flushes immediately, timer retries failures.
fresh(); T.check(send(1,'sync_request')~=nil and not send(1,'sync_request'),'#13 repeated sync throttled')
now=now+5; T.check(send(1,'sync_request')~=nil,'#13 sync opens after five seconds')
local saves=0; local save=G.saveLedger; G.saveLedger=function() saves=saves+1; return save() end
send(1,'set_company_name',{name='Debounced'}); send(1,'set_company_name',{name='Debounced again'})
T.check(saves==0 and G.dirty,'#13 mutations mark dirty without disk writes')
BNGE_tick(); T.check(saves==1 and not G.dirty,'#13 timer flushes dirty ledger')
G.dirty=true; BNGE_tick(); T.check(saves==1,'#13 timer limits disk saves to once per second')
now=now+1; BNGE_tick(); T.check(saves==2,'#13 next second flushes pending work')
send(1,'refuel',{litres=1}); T.check(saves==3 and not G.dirty,'#13 debit flushes immediately')
f=assert(io.open(OTBT_LEDGER_PATH)); bytes=f:read('*a'); f:close()
T.check(json.decode(bytes).players.one.company.vault==account(1).company.vault,'#13 debit is on disk before reply')
os.remove(OTBT_LEDGER_PATH); os.remove(OTBT_LEDGER_PATH..'.bad'); os.remove(OTBT_LEDGER_PATH..'.tmp')
T.done('test_beammp_security')
