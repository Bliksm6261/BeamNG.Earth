local dir=(arg[0]:match('^(.*)[/\\]') or '.')
local T=dofile(dir..'/testlib.lua')
dofile(dir..'/stubs.lua')
local settings=require('beamngEarth/settings')
settings.load()
T.check(settings.get('otbtLogisticsEnabled')==false,'logistics defaults off')
local persisted
jsonWriteFile=function(path,data) persisted=data end
T.check(settings.set('otbtLogisticsEnabled',true),'logistics enabled through existing settings')
T.check(persisted.otbtLogisticsEnabled==true,'toggle saved in settings file')
settings.set('otbtLogisticsEnabled',false)
local sends=0
TriggerServerEvent=function() sends=sends+1 end
jsonEncode=function() return '{}' end
local actions={
 freight={'acceptContract','claimSlot','recordDamage','deliverSlot','finalizeContract','abandonContract','purchaseUpgrade','setCompanyName','refuelVehicle','restDriver','spawnContractTrailer','update','onRemoteLogistics','loadState','saveState','clearCheckpoint'},
 expeditions={'startExpedition','setHomeBase','setHomeBaseByCity','teleportToHomeBase','fastTravelToTrailhead','beginTrail','abandonExpedition','advanceCheckpoint','spawnOverlandRig','spawnSemiTruck','update','onRemoteExpedition','loadState','saveState'},
 convoy={'transmit','setChannel','receiveRadioMessage'},
 checkpoints={'clearCheckpoint','onRemoteLogistics','update'},
 recovery={'repairTires','connectSnatchStrap','sendEmergencySos','realignSuspension'},
 bushcamp={'deployCamp','packCamp','restAtCamp'},
 african_weather={'applyPreset','setAutoWeather','update'},
 corridor_traffic={'spawnCorridorTraffic','setDensity','update'},
 mpsession={'sendLogisticsEvent'},
}
for module,names in pairs(actions) do
 local m=require('beamngEarth/'..module)
 for _,name in ipairs(names) do
  local ok,why=m[name]()
  T.check(ok==false and why=='OTBT logistics disabled',module..'.'..name..' disabled')
 end
end
T.check(sends==0,'disabled actions send no server events')
local reads={}
jsonReadFile=function(path)
 reads[path]=true
 if path==require('beamngEarth/freight').FILE then
  return {company={name='Saved Fleet',vault=1234,upgrades={}}}
 end
end
settings.set('otbtLogisticsEnabled',true)
T.check(reads[require('beamngEarth/freight').FILE] and reads[require('beamngEarth/expeditions').FILE],'enabling loads saved logistics state')
T.check(require('beamngEarth/freight').getCompany().name=='Saved Fleet','enabling restores saved company')
local ok=require('beamngEarth/mpsession').sendLogisticsEvent({type='sync_request'})
T.check(ok and sends==1,'enabled transport sends logistics')
local freight=require('beamngEarth/freight')
local originalJobs,originalAccept=freight.getAvailableJobs,freight.acceptContract
local identity
freight.getAvailableJobs=function() return {{id='identity-job'}} end
freight.acceptContract=function(job,pid,name) identity={pid=pid,name=name}; return true,job end
MPConfig={getPlayerServerID=function() return 42 end,getNickname=function() return 'Real Driver' end}
T.check(settings.uiFreightAccept('identity-job',1).ok and identity.pid==42 and identity.name=='Real Driver','HQ accept uses real BeamMP pid and name')
MPConfig=nil
T.check(settings.uiFreightAccept('identity-job',1).ok and identity.pid==0 and identity.name=='0','HQ accept falls back to local pid')
freight.getAvailableJobs,freight.acceptContract=originalJobs,originalAccept
local function read(path) local f=assert(io.open(path)); local s=f:read('*a'); f:close(); return s end
local map=read(dir..'/../beamng_earth/ui/ui-vue/mods/beamngEarth/EarthMap.vue')
T.check(map:find('v%-if="state.otbtLogisticsEnabled"')~=nil,'HQ button bound to toggle')
T.check(map:find('v%-if="state.otbtLogisticsEnabled && hqOpen"')~=nil,'HQ modal bound to toggle')
local ui=read(dir..'/../beamng_earth/ui/ui-vue/mods/beamngEarth/EarthSettings.vue')
T.check(ui:find('id: "otbtLogisticsEnabled", type: "bool", default: false',1,true)~=nil,'settings UI exposes default off toggle')
T.done('test_logistics_switch')
