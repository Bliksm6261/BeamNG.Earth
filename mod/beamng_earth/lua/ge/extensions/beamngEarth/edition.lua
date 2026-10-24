-- The edition this build is (the Off the Beaten Track edition of BeamNG.Earth; README): its name, where players get
-- the app, and the multiplayer server the game joins by itself (autojoin.lua). One file to change for another edition.
--
-- server.host '' would turn the automatic join off; BeamMP's own server list works either way.

return {
  name = 'Off the Beaten Track',
  installUrl = 'https://github.com/Bliksm6261/BeamNG.Earth/releases/latest',
  server = {
    host = 'beamng.offthebeatentrack.world',   -- the edition's BeamMP server (OTBT's VPS, 156.155.250.124)
    port = 30814,           -- BeamMP's default
    name = 'Off the Beaten Track',
  },
  autoJoin = true,          -- join server.host as soon as BeamMP is ready (autojoin.lua)
}
