# BeamNG.Earth on a BeamMP server

This zip turns a BeamMP server into a BeamNG.Earth server: the real world, streamed around every player. Players join
with the normal BeamMP launcher.

## Off the Beaten Track's server

On an Ubuntu VPS, `setup_otbt_server.sh` (beside this file in the repository) does all of the steps below:
`sudo bash setup_otbt_server.sh` (it asks for your AuthKey; before the edition is merged: `sudo BRANCH=otbt-branding bash ...`).
First lock the VPS down like OTBT's other servers with `harden_otbt_server.sh` (Tailscale, SSH over Tailscale only,
key-only logins with Tailscale SSH off, UFW, fail2ban, automatic updates; the game's port 30814 stays public):
`sudo TS_AUTHKEY=<tailscale auth key> SSH_PUBKEY="<your id_ed25519.pub>" bash harden_otbt_server.sh`.

## Quick server setup

1. **Get the BeamMP server** (the latest release from https://github.com/BeamMP/BeamMP-Server/releases; Windows:
   `BeamMP-Server.exe`, Linux: the build for your distribution). Put it in its own folder and run it once: it writes
   `ServerConfig.toml` and a `Resources` folder, then stops or waits. Close it.
2. **Unzip this file into that folder.** Its `Resources` folder merges with the server's:
   - `Resources/Client/beamng_earth.zip`: the BeamNG.Earth level and mod (BeamMP sends it to every player who joins);
   - `Resources/Server/BeamNGEarth/main.lua`: the server plugin (it tells the players where everyone is).
3. **Edit `ServerConfig.toml`:**

   ```toml
   Map = "/levels/beamng_earth/info.json"
   Port = 30814          # any port you like; players connect to it
   Name = "My BeamNG.Earth server"
   MaxCars = 3
   Private = true        # true: only people you give the address to can join
   AuthKey = "..."       # your own key from https://keymaster.beammp.com (the server won't start with it empty)
   ```

   Never share your AuthKey.
4. **Open the port** if players come over the internet: forward the server's port, **TCP and UDP**, in your router to
   the server's computer (and allow it in its firewall). Players on the same network need nothing.
5. **Start the server.** Its log should show `[BeamNG.Earth] plugin loaded`.
6. **Players connect** from BeamMP's Multiplayer menu: Direct Connect with your address and port (or find it in the
   server list if it isn't private).

To update, unzip the new version's server zip over the old one and restart the server. The server needs no world
data and little CPU: the world is built on each player's computer.

## Network Event Replication

The BeamNG.Earth server plugin (`Resources/Server/BeamNGEarth/main.lua`) replicates convoy and logistics simulation events between all connected players:
- **`bnge:cb_radio_msg`**: Replicates CB radio chat, tactical 10-codes, and emergency 10-33 SOS alerts across channels (19 Highway, 1 Convoy, 9 Emergency).
- **`bnge:recovery_tow_req`**: Coordinates kinetic snatch-strap towing impulses between convoy members within 25 meters.
- **`bnge:bushcamp_state`**: Synchronizes deployable rooftop tents, campfire positions, and player rest states in the wilderness.
- **`bnge:checkpoint_clear`**: Broadcasts toll booth, customs clearance, and weighbridge compliance status.
- **`bnge:fuel_refuel`**: Tracks shared commercial fueling events and Home Base bulk fuel operations.

## Live Production Server (OTBT)

The official Off the Beaten Track server is deployed at:
- **Host:** `beamng.offthebeatentrack.world` (IP: `156.155.250.124`)
- **Port:** `30814` (TCP & UDP)
- **Mod:** `Resources/Client/beamng_earth.zip` (automatically synced to clients on connection)
- **Service Management:** `sudo systemctl status beammp` (deployed in `/opt/beammp` via `/opt/beammp-src/beammp/setup_otbt_server.sh`)

## Players

- **Every player needs the BeamNG.Earth app** (https://github.com/Bliksm6261/BeamNG.Earth/releases) running, the same
  version as the server's. Start the BeamNG.Earth app and the BeamMP launcher in either order (the app starts the game,
  or just its world server if the game is already running), then join. Without the app, a window asks to install it:
  the world can't load without it.
- A player who joins is sent to where the others are, and each player's car shows in the right place in everyone's
  world, with its dents. Other players show on the world map (M) as arrows.
- Players near each other share one world origin and split the work of building the world: each piece of the distant
  landscape is built once and sent to the others. For that, the other players must reach each player's computer on
  **TCP port 47621** (on one network it just works; over the internet, each player forwards it, or else simply builds
  everything themselves). To use another port on your server, edit the line `G.SHARE_PORT = 47621` near the top of
  `Resources/Server/BeamNGEarth/main.lua` and restart the server: every player who joins gets it. A player can still
  pick their own with the environment variable `BNGE_SHARE_PORT`.
- Players far apart (another country) each build their own world and don't see each other's cars until they meet.

## Protocol 3 economy

Deploy all four Lua files in `Server/BeamNGEarth` together with the updated client.
The plugin saves `otbt_ledger.json` beside `main.lua`. Set `G.LEDGER_PATH` in
`main.lua` before module initialization to change it (or set the
`OTBT_LEDGER_PATH` Lua global before loading the plugin). The directory must
exist and be writable. Tests use temporary paths. Writes use `.tmp` and rename;
write failures are logged and retain the in-memory balance. Invalid ledgers are
moved to `.bad` before starting fresh. Back up the ledger independently of mod
releases.

All economy messages use `bngeLogistics`. Mutations require a fresh string
`opId` (1–128 bytes). Replays return the saved reply without applying changes.
Clients send these intents:

| Type | Fields |
| --- | --- |
| `sync_request` | None; reply includes personal company, active contract/expedition and server job board |
| `accept` | `jobId`, optional `slotIndex` (defaults to 1) |
| `claim`, `damage`, `deliver_slot` | `jobId` or `contractId`, `slotIndex`; optional `cargoHealth` for damage/delivery |
| `finalize`, `abandon` | `jobId` or `contractId` |
| `purchase_upgrade` | `upgradeId` |
| `refuel` | `litres` (>0, max 400; $1.85/L, rounded down) |
| `checkpoint_clear` | `checkpointId` |
| `set_company_name` | `name` (control characters removed, capped at 64 bytes) |
| `expedition_start`, `expedition_complete`, `abandon_expedition` | `expeditionId` |
| `expedition_stage` | `expeditionId`, sequential `stageIndex` |
| `cb_radio` | Existing `channel`, `callsign`, `message`, `code` fields; no `opId` required |

Prices and contract tables from clients are ignored. Server-generated IDs encode
hour, hub and board position; accept resolves only the current hour. Accepted
contracts retain their prices across rotations/restarts. Co-op participants get
`slot_state` broadcasts; affected players get personal `ledger_state` replies
with `company`, `contract`, `expedition`, `playerKey`, `rev`, `opId`, and `intent`.
Clients ignore older revisions so saved operation replies cannot roll back state. Completing the last
slot automatically pays the accepter, regardless of who delivered that slot.
Company vaults are never shared in broadcasts. Single-player keeps local pricing
and accounting.

Limits: delivery, damage and expedition progress are still player reports; the
server validates ownership and progression but has no authoritative vehicle or
location telemetry. Precision docking pays no bonus until it can be verified.
Checkpoint clearances charge catalog toll/customs/weigh fees once per player per
hour; they have no cash reward. Expeditions currently have zero cash reward and
complete once per expedition ID across the server. MP fuel uses the standard
price without the local Home Base discount. Operation results, paid IDs, and
contracts are retained without pruning. The JSON file is a single-process store;
a failed write can lose recent changes after a crash. Guest identities follow
player names and have no protection against name reuse.
