-- Join the edition's BeamMP server by itself (edition.lua; the owner, 2026-10-24: "our app does everything itself"):
-- the app starts BeamMP's launcher (beammp_launch.py), the launcher starts the game with BeamMP's mod, and once that mod
-- is talking to its launcher and signed in, this joins the server. No step for the player.
--
-- Sign-in: BeamMP signs a returning player in by itself (MPCoreNetwork.autoLogin when its launcher connects); a player
-- still signed out after LOGIN_WAIT_S plays as a guest (MPCoreNetwork.login(), BeamMP's own "Play as guest").
-- Once per game start: after a join (or GIVE_UP_S without BeamMP being ready, or a player already in a session) it
-- does nothing more, so leaving the server is the player's choice. Off: edition.autoJoin false or no server.host.

local M = {}

M.LOGIN_WAIT_S = 10         -- s after BeamMP's launcher connects for its own sign-in before playing as a guest
M.GIVE_UP_S = 300           -- s without BeamMP ready: no join this game start
M.SETTING = 'autoJoin'      -- the player's switch (settings.lua SCHEMA, the settings page's Multiplayer)

local edition = require('beamngEarth/edition')

local state = 'waiting'     -- 'waiting' | 'signing-in' | 'joining' | 'done'
local clock, readyAt, guestAsked = 0, nil, false

local function mp()
  local m = rawget(_G, 'MPCoreNetwork')
  return type(m) == 'table' and m or nil
end

local function call(m, name, ...)
  if type(m[name]) ~= 'function' then return nil end
  local ok, v = pcall(m[name], ...)
  if ok then return v end
  log('W', 'beamngEarth', 'autojoin: MPCoreNetwork.' .. name .. ': ' .. tostring(v))
  return nil
end

function M.enabled(settings)
  local s = edition.server or {}
  if not edition.autoJoin or type(s.host) ~= 'string' or s.host == '' then return false end
  local on = true
  if settings and type(settings.get) == 'function' then on = settings.get(M.SETTING) end
  return on ~= false and on ~= 'false'
end

function M.state() return state end

-- every frame, in every level and the menus (core.lua onUpdate)
function M.update(dt, settings)
  if state == 'done' then return end
  clock = clock + (dt or 0)
  if not M.enabled(settings) then state = 'done'; return end
  local m = mp()
  if not m then
    if clock > M.GIVE_UP_S then state = 'done' end
    return
  end
  if call(m, 'isMPSession') == true then state = 'done'; return end   -- already playing somewhere
  if call(m, 'isLauncherConnected') ~= true then
    if clock > M.GIVE_UP_S then
      log('W', 'beamngEarth', 'autojoin: BeamMP\'s launcher never connected; not joining')
      state = 'done'
    end
    return
  end
  readyAt = readyAt or clock
  if call(m, 'isLoggedIn') ~= true then
    state = 'signing-in'
    if not guestAsked and clock - readyAt > M.LOGIN_WAIT_S then
      guestAsked = true
      log('I', 'beamngEarth', 'autojoin: not signed in to BeamMP; playing as a guest')
      call(m, 'login')
    end
    return
  end
  local s = edition.server
  state = 'joining'
  log('I', 'beamngEarth', string.format('autojoin: joining %s (%s:%d)', s.name or s.host, s.host, s.port or 30814))
  call(m, 'connectToServer', s.host, s.port or 30814, s.name or s.host, true)
  state = 'done'
end

-- tests
function M._reset() state, clock, readyAt, guestAsked = 'waiting', 0, nil, false end

return M
