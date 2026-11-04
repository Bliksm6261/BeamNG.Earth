local dir=(arg[0]:match('^(.*)[/\\]') or '.')
local T=dofile(dir..'/testlib.lua')
local plugin=dir..'/../../beammp/Server/BeamNGEarth/'
local pipe=assert(io.popen('find "'..plugin..'" -maxdepth 1 -name "*.lua" -type f'))
local files={}; for file in pipe:lines() do files[#files+1]=file end; pipe:close()
T.check(#files==1 and files[1]==plugin..'main.lua','only main.lua auto-runs')
OTBT_LEDGER_PATH=nil
local G=dofile(plugin..'main.lua')
T.check(G.LEDGER_PATH==plugin..'data/otbt_ledger.json','default ledger isolated in data subfolder')
local root=os.tmpname(); os.remove(root)
local path=root.."/quote' folder/ledger.json"
G.LEDGER_PATH=path
T.check(G.saveLedger(),'mkdir fallback handles missing directories and quoted paths')
local f=io.open(path,'r'); T.check(f~=nil,'ledger created in nested data folder'); if f then f:close() end
local corrupt=assert(io.open(path,'w')); corrupt:write('{broken'); corrupt:close()
G.loadLedger(path)
local bad=io.open(path..'.bad','r'); T.check(bad~=nil,'corrupt backup remains in data folder'); if bad then bad:close() end
os.remove(path..'.bad')
os.remove(path); os.remove(root.."/quote' folder"); os.remove(root)
local called
FS={CreateDirectory=function(path) called=path end}
G.LEDGER_PATH=os.tmpname()
T.check(G.saveLedger() and called==G.LEDGER_PATH:match('^(.*)/'),'BeamMP FS directory creation used')
os.remove(G.LEDGER_PATH); FS=nil
local result=os.execute('python3 "'..dir..'/check_beammp_package.py"')
T.check(result==0,'BeamMP archive includes lib and excludes ledger data; installer extracts archive')
T.done('test_beammp_layout')
