-- Persistent authoritative ledger. Runtime pid is used only to route replies.
return function(G, economy, json)
  local function fresh() return { rev=0, players={}, contracts={}, paid={}, expeditions={} } end
  local function copy(t) return json.decode(json.encode(t)) end
  G.now = G.now or os.time
  G.MAX_OPS = 200
  G.INTENTS_PER_SECOND = 20
  local rates = {}
  local function trimOps(p)
    local order, seen, missing = {}, {}, {}
    for _, op in ipairs(type(p.opOrder)=='table' and p.opOrder or {}) do
      if type(op)=='string' and p.ops[op] and not seen[op] then
        order[#order+1]=op; seen[op]=true
      end
    end
    for op in pairs(p.ops) do if not seen[op] then missing[#missing+1]=op end end
    table.sort(missing, function(a,b)
      local ar,br=tonumber(p.ops[a].rev) or 0,tonumber(p.ops[b].rev) or 0
      if ar~=br then return ar<br end
      return a<b
    end)
    for _, op in ipairs(missing) do order[#order+1]=op end
    while #order>G.MAX_OPS do p.ops[table.remove(order,1)]=nil end
    p.opOrder=order
  end
  G.economy = economy
  G.encode = function(t) return (Util and Util.JsonEncode or json.encode)(t) end
  G.decode = function(s) return (Util and Util.JsonDecode or json.decode)(s) end
  function G.loadLedger(path)
    if path then G.LEDGER_PATH = path end
    G.ledger = fresh()
    local f = io.open(G.LEDGER_PATH, 'r')
    if not f then return end
    local data=f:read('*a'); f:close()
    local ok, v=pcall(G.decode, data)
    if ok and type(v)=='table' and type(v.rev)=='number' and type(v.players)=='table'
        and type(v.contracts)=='table' and type(v.paid)=='table' then
      -- Reject syntactically valid JSON with an unusable ledger schema too.
      local function finite(n) return type(n)=='number' and n==n and math.abs(n)<math.huge and n>=0 end
      if not finite(v.rev) then ok=false end
      for _, p in pairs(v.players) do
        if type(p)~='table' or type(p.company)~='table' or type(p.ops)~='table' then ok=false
        else
          local comp=p.company
          if type(comp.name)~='string' or type(comp.upgrades)~='table' then ok=false end
          for _, field in ipairs({'vault','completedDeliveries','totalTonnesHauled','totalEarnings','reputation'}) do
            if not finite(comp[field]) then ok=false end
          end
          for _, result in pairs(p.ops) do if type(result)~='table' or result.type~='ledger_state' then ok=false end end
        end
      end
      for id, c in pairs(v.contracts) do
        if type(c)~='table' or c.id~=id or not v.players[c.owner] or type(c.slots)~='table'
            or #c.slots<1 or type(c.cargo)~='table' or not finite(c.weightPerTruckKg) then ok=false
        else
          for _, slot in ipairs(c.slots) do
            if type(slot)~='table' or not finite(slot.grossPayout) or not finite(slot.weightKg)
                or not finite(slot.cargoHealth) or not finite(slot.damagePenalty) then ok=false end
          end
        end
      end
      for _, paid in pairs(v.paid) do if paid~=true then ok=false end end
      if v.expeditions~=nil and type(v.expeditions)~='table' then ok=false end

      if ok then
        for _, p in pairs(v.players) do trimOps(p) end
        v.expeditions=v.expeditions or {}; G.ledger=v; return
      end
    end
    local renamed, err=os.rename(G.LEDGER_PATH, G.LEDGER_PATH..'.bad')
    print('[OTBT] corrupt ledger; starting fresh' .. (renamed and '' or ': backup failed '..tostring(err)))
  end
  local function ensureDirectory(path)
    local dir = path:match('^(.*)[/\\]')
    if not dir or dir == '' then return end
    if FS and FS.CreateDirectory then
      local ok, result = pcall(FS.CreateDirectory, dir)
      if ok and result ~= false then return end
    end
    -- Shell quote the entire path; never interpolate an unquoted override.
    if os.execute then os.execute("mkdir -p -- '" .. dir:gsub("'", "'\\''") .. "'") end
  end
  function G.saveLedger()
    G.ledger.rev=G.ledger.rev+1
    local ok, err=pcall(function()
      ensureDirectory(G.LEDGER_PATH)
      local encoded=G.encode(G.ledger)
      local f=assert(io.open(G.LEDGER_PATH..'.tmp', 'w'))
      local wrote, why=f:write(encoded); local closed, reason=f:close()
      assert(wrote, why); assert(closed, reason)
      assert(os.rename(G.LEDGER_PATH..'.tmp', G.LEDGER_PATH))
    end)
    if not ok then print('[OTBT] ledger write failed: '..tostring(err)) end
    return ok
  end
  function G.playerKey(pid, name)
    if MP and MP.GetPlayerIdentifiers then
      local ok, ids=pcall(MP.GetPlayerIdentifiers, pid)
      if ok and type(ids)=='table' and ids.beammp~=nil and tostring(ids.beammp)~='' then return tostring(ids.beammp) end
    end
    return 'guest:'..name
  end
  function G.account(pid, name)
    local key=G.playerKey(pid,name)
    local p=G.ledger.players[key]
    if not p then
      p={name=name, company={name='OTBT Logistics Co-op',vault=25000,completedDeliveries=0,
        totalTonnesHauled=0,totalEarnings=0,reputation=100,upgrades={}},ops={}}
      G.ledger.players[key]=p; G.saveLedger()
    end
    return p,key
  end
  function G.ledgerState(pid, name, contract)
    local p,key=G.account(pid,name)
    if not contract then
      for _, c in pairs(G.ledger.contracts) do
        if c.status=='in_transit' then
          if c.owner==key then contract=c; break end
          for _, s in ipairs(c.slots) do if s.claimedKey==key then contract=c; break end end
          if contract then break end
        end
      end
    end
    return copy({type='ledger_state',company=p.company,contract=contract,
      expedition=G.ledger.expeditions[key], playerKey=key, rev=G.ledger.rev})
  end
  local function reject(reason)
    print('[OTBT] rejected intent: '..reason)
    return nil,nil
  end
  function G.onLogistics(pid, msg, name)
    if type(msg)~='table' or type(msg.type)~='string' then return reject('invalid message') end
    name=name or ('Player '..tostring(pid))
    local key=G.playerKey(pid,name)
    local now=G.now()
    local rate=rates[key]
    if not rate or rate.window~=math.floor(now) then rate={window=math.floor(now),count=0}; rates[key]=rate end
    rate.count=rate.count+1
    if rate.count>G.INTENTS_PER_SECOND then return reject('rate limit') end
    local p=G.account(pid,name)
    local comp=p.company
    local epoch=math.floor(G.now()/3600)
    if msg.type=='sync_request' then
      local state=G.ledgerState(pid,name)
      return {type='sync_state',state={company=state.company,activeContract=state.contract,
        activeExpedition=state.expedition},playerKey=key,rev=G.ledger.rev,jobs=economy.board(epoch,comp.upgrades)},pid
    end
    if msg.type=='cb_radio' then
      return {type='cb_radio',channel=tonumber(msg.channel) or 19,callsign=tostring(msg.callsign or name):sub(1,64),
        message=tostring(msg.message or ''):sub(1,512),code=tostring(msg.code or ''):sub(1,32),time=G.now(),playerName=name,pid=pid},-1
    end
    if type(msg.opId)~='string' or #msg.opId<1 or #msg.opId>128 then return reject('opId required') end
    if p.ops[msg.opId] then return copy(p.ops[msg.opId]),pid end
    for _, field in ipairs({'litres','cargoHealth','slotIndex','stageIndex'}) do
      local n=msg[field]
      if n~=nil and (type(n)~='number' or n~=n or n<0 or n==math.huge) then return reject('invalid '..field) end
    end
    local id=msg.contractId or msg.jobId
    local c=type(id)=='string' and G.ledger.contracts[id] or nil
    local idx=msg.slotIndex
    if idx and (idx%1~=0 or idx<1) then return reject('invalid slot') end
    local s=c and idx and c.slots[idx]
    local broadcast=false
    local function payContract()
      for _, slot in ipairs(c.slots) do if slot.status~='delivered' then return false end end
      local paidKey='contract:'..c.id
      if G.ledger.paid[paidKey] then return true end
      local owner=G.ledger.players[c.owner].company
      local gross,penalties,bonus,weight=0,0,0,0
      for _, slot in ipairs(c.slots) do
        gross=gross+slot.grossPayout; penalties=penalties+slot.damagePenalty
        bonus=bonus+(slot.dockBonus or 0); weight=weight+slot.weightKg
      end
      local payout=math.max(0,gross-penalties+bonus)
      owner.vault=owner.vault+payout; owner.totalEarnings=owner.totalEarnings+payout
      owner.completedDeliveries=owner.completedDeliveries+1
      owner.totalTonnesHauled=owner.totalTonnesHauled+math.floor(weight/1000)
      owner.reputation=math.max(10,math.min(100,owner.reputation+(penalties>gross*.3 and -5 or (bonus>0 and 7 or 2))))
      c.status='completed'; c.netPayout=payout; G.ledger.paid[paidKey]=true
      return true
    end
    local t=msg.type
    if t=='accept' or t=='claim' then
      for _, contract in pairs(G.ledger.contracts) do
        for _, slot in ipairs(contract.slots) do
          if slot.status=='claimed' and slot.claimedKey==key then return reject('already holding a slot') end
        end
      end
    end
    if t=='set_company_name' then
      if type(msg.name)~='string' then return reject('invalid name') end
      local clean=msg.name:gsub('[%z\1-\31\127]', ''):sub(1,64)
      if #clean==0 then return reject('empty name') end
      comp.name=clean
    elseif t=='purchase_upgrade' then
      local up
      for _, u in ipairs(economy.UPGRADES) do if u.id==msg.upgradeId then up=u end end
      if not up or comp.upgrades[up.id] then return reject('unknown or owned upgrade') end
      if comp.vault<up.cost then return reject('insufficient funds') end
      comp.vault=comp.vault-up.cost; comp.upgrades[up.id]={cost=up.cost,purchasedAt=G.now()}
    elseif t=='refuel' then
      if not msg.litres or msg.litres<=0 or msg.litres>economy.FUEL_CAP then return reject('invalid litres') end
      local cost=math.floor(msg.litres*economy.FUEL_PRICE)
      if comp.vault<cost then return reject('insufficient funds') end
      comp.vault=comp.vault-cost
    elseif t=='checkpoint_clear' then
      local cp
      for _, v in ipairs(economy.CHECKPOINTS) do if v.id==msg.checkpointId then cp=v end end
      if not cp then return reject('unknown checkpoint') end
      local paidKey='checkpoint:'..key..':'..cp.id..':'..epoch
      if G.ledger.paid[paidKey] then return reject('checkpoint already cleared') end
      local fee=0
      local active
      for _, v in pairs(G.ledger.contracts) do if v.owner==key and v.status=='in_transit' then active=v; break end end
      if cp.type=='toll' then
        fee=cp.standardFee or 35
        if active and active.cargo.hazmat then fee=math.floor(fee*1.25) end
        if comp.reputation>=90 then fee=math.floor(fee*.9) end
      elseif cp.type=='border' then fee=comp.upgrades.license_cross_border and 0 or (cp.standardFee or 80)
      elseif cp.type=='weigh' and active and 18000+active.weightPerTruckKg>(cp.maxGrossKg or 34000)
          and not comp.upgrades.license_heavy_haul then fee=2500 end
      if comp.vault<fee then return reject('insufficient funds') end
      comp.vault=comp.vault-fee; G.ledger.paid[paidKey]=true
    elseif t=='accept' then
      if type(id)~='string' or G.ledger.contracts[id] then return reject('unknown or accepted job') end
      for _, v in pairs(G.ledger.contracts) do if v.owner==key and v.status=='in_transit' then return reject('active contract') end end
      c=economy.resolve(id,epoch,comp.upgrades)
      if not c or c.locked then return reject('unknown or locked job') end
      idx=idx or 1; s=c.slots[idx]
      if not s then return reject('invalid slot') end
      c.owner=key; c.status='in_transit'; c.acceptedAt=G.now()
      s.status='claimed'; s.claimedAt=G.now(); s.claimedKey=key; s.claimedBy=name; s.claimedPid=pid
      G.ledger.contracts[id]=c; broadcast=true
    elseif t=='claim' then
      if not c or c.status~='in_transit' or not s or s.status~='open' then return reject('slot unavailable') end
      s.status='claimed'; s.claimedAt=G.now(); s.claimedKey=key; s.claimedBy=name; s.claimedPid=pid; broadcast=true
    elseif t=='damage' or t=='deliver_slot' then
      if not c or c.status~='in_transit' or not s or s.status~='claimed' or s.claimedKey~=key then return reject('slot ownership or status') end
      if t=='deliver_slot' and G.now()-(s.claimedAt or G.now())<economy.minimumTransitSeconds(c) then return reject('minimum transit time') end
      if msg.cargoHealth then s.cargoHealth=math.min(s.cargoHealth,math.min(100,msg.cargoHealth)) end
      s.damagePenalty=economy.calculatePenalty(s,c.cargo,G.ledger.players[c.owner].company.upgrades)
      if t=='deliver_slot' then
        s.status='delivered'
        -- Precision docking needs authoritative vehicle telemetry; disabled until available.
        s.dockBonus=0; payContract()
      end
      broadcast=true
    elseif t=='finalize' then
      if not c or c.owner~=key or c.status~='in_transit' then return reject('contract ownership or status') end
      if not payContract() then return reject('undelivered slots') end
      broadcast=true
    elseif t=='abandon' then
      if not c or c.owner~=key or c.status~='in_transit' then return reject('contract ownership or status') end
      c.status='abandoned'; for _, slot in ipairs(c.slots) do if slot.status~='delivered' then slot.status='abandoned' end end
      comp.reputation=math.max(10,comp.reputation-10); broadcast=true
    elseif t=='expedition_start' then
      local tour
      for _, v in ipairs(economy.TOURS) do if v.id==msg.expeditionId then tour=v end end
      if not tour or G.ledger.expeditions[key] or G.ledger.paid['expedition:'..tour.id] then return reject('expedition unavailable') end
      if tour.grade and tour.grade>=5 and not comp.upgrades.cert_rock_crawl then return reject('expedition locked') end
      local exp=copy(tour); exp.owner=key; exp.stageIndex=1; exp.stages=#tour.checkpoints; exp.status='transit'
      G.ledger.expeditions[key]=exp
    elseif t=='abandon_expedition' then
      local exp=G.ledger.expeditions[key]
      if not exp or exp.id~=msg.expeditionId then return reject('expedition ownership') end
      G.ledger.expeditions[key]=nil
    elseif t=='expedition_stage' or t=='expedition_complete' then
      local exp=G.ledger.expeditions[key]
      if not exp or exp.owner~=key or exp.id~=msg.expeditionId then return reject('expedition ownership') end
      if t=='expedition_stage' then
        if msg.stageIndex~=exp.stageIndex+1 or msg.stageIndex>exp.stages then return reject('stage order') end
        exp.stageIndex=msg.stageIndex; exp.status='active'
      else
        if exp.stageIndex~=exp.stages or G.ledger.paid['expedition:'..exp.id] then return reject('expedition incomplete or paid') end
        local reward=economy.EXPEDITION_REWARDS[exp.id] or 0
        comp.vault=comp.vault+reward; G.ledger.paid['expedition:'..exp.id]=true; G.ledger.expeditions[key]=nil
      end
    else return reject('unknown intent') end
    local result=G.ledgerState(pid,name,c)
    result.rev=G.ledger.rev+1
    result.opId=msg.opId; result.intent=t; result.expeditionId=msg.expeditionId; result.checkpointId=msg.checkpointId
    if t=='purchase_upgrade' then result.jobs=economy.board(epoch,comp.upgrades) end
    p.ops[msg.opId]=copy(result)
    trimOps(p)
    G.saveLedger()
    if broadcast and MP and MP.TriggerClientEvent then
      local public=copy(c)
      public.owner=nil
      for _, slot in ipairs(public.slots) do slot.claimedKey=nil end
      MP.TriggerClientEvent(-1,'bngeLogistics',G.encode({type='slot_state',contract=public,rev=G.ledger.rev}))
      -- Send each affected participant their own company, never another player's vault.
      for other, pose in pairs(G.players) do
        if other~=pid then
          local otherKey=G.playerKey(other,pose.name)
          local affected=c.owner==otherKey
          for _, slot in ipairs(c.slots) do if slot.claimedKey==otherKey then affected=true end end
          if affected then MP.TriggerClientEvent(other,'bngeLogistics',G.encode(G.ledgerState(other,pose.name,c))) end
        end
      end
    end
    return copy(result),pid
  end
  G.loadLedger()
end
