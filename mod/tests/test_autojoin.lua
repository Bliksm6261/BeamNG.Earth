-- luajit mod/tests/test_autojoin.lua  (joining the edition's BeamMP server by itself, autojoin.lua / edition.lua)
-- Off without a server; waits for BeamMP's launcher; a returning player signed in by BeamMP joins at once; a signed-out
-- one plays as a guest after LOGIN_WAIT_S; joins once (skip the mod warning); nothing in a session already; gives up;
-- the player's switch.
local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
_G.log = _G.log or function() end
local edition = require('beamngEarth/edition')
local aj = require('beamngEarth/autojoin')

local function fakeMP()
  local m = { launcher = false, loggedIn = false, session = false, calls = {} }
  m.isLauncherConnected = function() return m.launcher end
  m.isLoggedIn = function() return m.loggedIn end
  m.isMPSession = function() return m.session end
  m.login = function(...) m.calls[#m.calls + 1] = { 'login', select('#', ...) } end
  m.connectToServer = function(ip, port, name, skip) m.calls[#m.calls + 1] = { 'connect', ip, port, name, skip } end
  return m
end
local function settingsWith(v) return { get = function(k) if k == aj.SETTING then return v end end } end
local function run(n, dt, s) for _ = 1, n do aj.update(dt, s) end end

-- the real settings module has the switch, on by default, and keeps it off
do
  local settings = require('beamngEarth/settings')
  T.check(settings.SCHEMA[aj.SETTING] and settings.defaults()[aj.SETTING] == true, 'autoJoin in settings.lua, on by default')
  T.check(settings.validate(aj.SETTING, 'false') == false, 'autoJoin can be switched off')
end

-- the edition's own server
T.check(edition.server.host == 'beamng.offthebeatentrack.world' and edition.server.port == 30814 and aj.enabled(nil),
  'edition.lua: OTBT\'s server, BeamMP\'s port, on')

-- without a server: never joins
edition.server.host = ''
T.check(not aj.enabled(nil), 'no server in edition.lua: off')
_G.MPCoreNetwork = fakeMP()
MPCoreNetwork.launcher, MPCoreNetwork.loggedIn = true, true
run(5, 1)
T.check(aj.state() == 'done' and #MPCoreNetwork.calls == 0, 'no server: no join')

edition.server.host = '203.0.113.7'
edition.server.port = 30815

-- waits for BeamMP: no MPCoreNetwork yet, then no launcher
aj._reset(); _G.MPCoreNetwork = nil
run(10, 1)
T.check(aj.state() == 'waiting', 'no BeamMP mod yet: waiting')
_G.MPCoreNetwork = fakeMP()
run(10, 1)
T.check(aj.state() == 'waiting' and #MPCoreNetwork.calls == 0, 'launcher not connected: waiting')

-- a returning player (BeamMP signed them in): joins at once, skipping the mod warning, once
MPCoreNetwork.launcher, MPCoreNetwork.loggedIn = true, true
run(1, 0.016)
local c = MPCoreNetwork.calls[1]
T.check(c and c[1] == 'connect' and c[2] == '203.0.113.7' and c[3] == 30815 and c[4] == 'Off the Beaten Track'
  and c[5] == true, 'joined the edition\'s server')
run(100, 1)
T.check(#MPCoreNetwork.calls == 1 and aj.state() == 'done', 'joined once: leaving is the player\'s choice')

-- signed out: BeamMP's own sign-in first, then a guest
aj._reset(); _G.MPCoreNetwork = fakeMP()
MPCoreNetwork.launcher = true
run(5, 1)
T.check(aj.state() == 'signing-in' and #MPCoreNetwork.calls == 0, 'signed out: BeamMP gets LOGIN_WAIT_S to sign in')
run(aj.LOGIN_WAIT_S, 1)
T.check(#MPCoreNetwork.calls == 1 and MPCoreNetwork.calls[1][1] == 'login' and MPCoreNetwork.calls[1][2] == 0,
  'still signed out: plays as a guest (login with no credentials)')
run(5, 1)
T.check(#MPCoreNetwork.calls == 1, 'guest asked once')
MPCoreNetwork.loggedIn = true
run(1, 1)
T.check(MPCoreNetwork.calls[2] and MPCoreNetwork.calls[2][1] == 'connect', 'signed in as a guest: joins')

-- already in a session (the player joined another server first): nothing
aj._reset(); _G.MPCoreNetwork = fakeMP()
MPCoreNetwork.launcher, MPCoreNetwork.loggedIn, MPCoreNetwork.session = true, true, true
run(3, 1)
T.check(aj.state() == 'done' and #MPCoreNetwork.calls == 0, 'in a session already: no join')

-- BeamMP never ready: gives up
aj._reset(); _G.MPCoreNetwork = fakeMP()
run(aj.GIVE_UP_S + 2, 1)
T.check(aj.state() == 'done' and #MPCoreNetwork.calls == 0, 'launcher never connected: gave up')

-- the player's switch
aj._reset(); _G.MPCoreNetwork = fakeMP()
MPCoreNetwork.launcher, MPCoreNetwork.loggedIn = true, true
run(3, 1, settingsWith(false))
T.check(aj.state() == 'done' and #MPCoreNetwork.calls == 0, 'switched off by the player: no join')
aj._reset()
run(1, 1, settingsWith(true))
T.check(#MPCoreNetwork.calls == 1, 'the switch on: joins')

-- a Lua reload (BeamMP's after leaving a server) after the join: still done, no second join
aj._reset(); _G.MPCoreNetwork = fakeMP()
MPCoreNetwork.launcher, MPCoreNetwork.loggedIn = true, true
run(1, 1)
local saved = aj.serialize()
aj._reset(); aj.deserialize(saved)
run(3, 1)
T.check(#MPCoreNetwork.calls == 1 and aj.state() == 'done', 'after a Lua reload: not joined again')
aj._reset(); aj.deserialize({ done = false })
T.check(aj.state() == 'waiting', 'a reload before the join: still joins')
aj.deserialize(nil)
T.check(aj.state() == 'waiting', 'nothing saved: a new game start')

-- a BeamMP function that throws: logged, not fatal
aj._reset(); _G.MPCoreNetwork = fakeMP()
MPCoreNetwork.isLauncherConnected = function() error('boom') end
T.check(pcall(run, 3, 1), 'a throwing BeamMP call does not throw')

edition.server.host, edition.server.port = 'beamng.offthebeatentrack.world', 30814
_G.MPCoreNetwork = nil
T.done('test_autojoin')
