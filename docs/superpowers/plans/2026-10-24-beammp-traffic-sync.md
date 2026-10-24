# BeamMP Shared Traffic Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On a BeamMP server, every player in a group sees the same AI traffic and parked cars. The server decides who drives them and how many there are.

**Architecture:** The server plugin is the authority. For each anchor group (the players who already share one anchor, `G.key(aLat, aLon)`), it elects one *traffic host*. Only the host's game runs `gameplay_traffic` and `gameplay_parking`, with the amounts the server sets. BeamMP syncs the host's traffic to the others like any car, and `mpanchor` already converts the positions. Every other player's game keeps its own traffic and parked cars off. The server also enforces the car budget: it cancels spawns over each player's allowance. When a host leaves, BeamMP removes its cars and the server elects the next host, who spawns new traffic. The host reports which of its cars are traffic, so the other games treat them as traffic and not as players' cars (collision radius, far-car unloading).

**Tech Stack:** BeamMP server Lua 5.3 (plugin), BeamNG GE Lua / LuaJIT (mod), plain-Lua tests run with `luajit` (`mod/tests/testlib.lua`).

**Spec:** this document. The design was agreed in the project thread on 2026-10-24 ("option A": the server decides, players drive). Background: `docs/ARCHITECTURE.md` "Parked cars and traffic", `beammp/Server/BeamNGEarth/main.lua` header, `mod/.../beamngEarth/mpsession.lua` header.

**Out of scope for this plan (phase 2):** handing individual cars to the nearest player without a gap when the host leaves; traffic for a player who is in no group with others (they keep their own local choice, as today). Known limit of phase 1: the host's traffic spawns within about 1.1 km of the host (the road graph's reach, `navgraph`). A group member several km away therefore sees little or no traffic until phase 2 gives each area its own driver.

## Global Constraints

- The server plugin stays Lua 5.3-compatible and keeps its pure part testable offline (no `MP.*` outside the `if MP and MP.RegisterEvent` block).
- Nothing in BeamMP's own files changes. Use only its events (`MP.RegisterEvent`, `MP.TriggerClientEvent`, `onVehicleSpawn`).
- Outside a BeamMP session, traffic behaves exactly as today (the player's level-start choice, `navgraph.choice`).
- Bump the client and server protocol together: `G.PROTO` and `mpsession.M.PROTO` go from 2 to 3.
- Server settings live in the "Settings" block at the top of `main.lua`, next to `G.SHARE_PORT`.
- Defaults: `G.TRAFFIC = { enabled = true, amount = 6, parked = 10, police = false }`, `G.PLAYER_CARS = 2`. A host's allowance is `PLAYER_CARS + amount + parked`.
- `ServerConfig.toml` `MaxCars` must be at least the host's allowance (18 with the defaults). `setup_otbt_server.sh` writes `MaxCars = 18`.
- Commit messages follow the repo's style: `Area: what changed`.

## Review Focus

1. **The host leaves or times out mid-drive.** The next player in the group becomes host within one tick, and their traffic starts. No player ends up with both their own traffic and the host's.
2. **Two groups on one server** (for example Johannesburg and Cape Town) get one host each, and a player who moves from one group to another changes role.
3. **A player who is in no group (alone on their anchor)** is their own host. Their level-start choice is used, not the server's amounts. This is today's behaviour and must not regress.
4. **A client on the old protocol (PROTO 2)** must not be elected host, and it must not be allowed more than `PLAYER_CARS` cars.
5. **A player who turns traffic on from the radial menu while not the host:** it must be turned off again within one tick, not left running with duplicate traffic.

---

### Task 0: Probe BeamMP's handling of traffic (gate)

These facts decide whether the design holds. Check them before writing code. Run them on the OTBT server (`ssh otbt-beamng`) with two clients (two PCs, or one PC plus a second BeamMP account).

**Files:**
- Create: `docs/research/2026-10-24-beammp-traffic-probe.md`

- [ ] **Step 1:** Set `MaxCars = 18` in `/opt/beammp/ServerConfig.toml` and restart (`sudo systemctl restart beammp`). On client 1, turn traffic on (radial menu > Traffic). On client 2, check that client 1's traffic cars appear and move. Record the result.
- [ ] **Step 2:** Add a temporary plugin `Resources/Server/Probe/main.lua` that registers `onVehicleSpawn` and returns `1` for every spawn by player 1 after their second car. Check that BeamMP cancels those spawns, and record what client 1 sees (a removed car, or a notice). Then delete the probe plugin.
- [ ] **Step 3:** In client 1's console, check that `gameplay_traffic.deleteVehicles`, `gameplay_parking.deleteVehicles`, `gameplay_traffic.getTrafficData` and `MPVehicleGE.getServerVehicleID` exist, and record their signatures.
- [ ] **Step 4:** Write the findings to the research file and commit them (`Research: BeamMP and stock traffic, probe`).

**Gate:** if Step 1 shows that BeamMP does not sync traffic cars, or Step 2 shows that spawns cannot be cancelled, stop and re-plan with the user. Do not work around it.

### Task 1: Server — host election and car budget

**Files:**
- Modify: `beammp/Server/BeamNGEarth/main.lua` (Settings block; new pure functions after `G.peers`; wiring)
- Test: `mod/tests/test_beammp_plugin.lua`

**Interfaces:**
- Produces: `G.trafficHosts(players) -> { [pid] = hostPid }`. Each live PROTO-3 player maps to its group's host: the member with the smallest `joinedAt`, with ties broken by the smaller pid. A player alone on their anchor is their own host.
- Produces: `G.trafficMsg(pid, hosts, players) -> { v = 3, host = tostring(hostPid), alone = bool, enabled, amount, parked, police, cars = { serverVehicleString... } }`. `cars` is the host's reported list (Task 2).
- Produces: `G.allowance(pid, hosts) -> integer`. `PLAYER_CARS + amount + parked` for a host that is not alone (or `PLAYER_CARS` when `G.TRAFFIC.enabled` is false); `PLAYER_CARS` for everyone else. A player alone gets the host allowance.
- Produces: `G.onSpawn(pid, hosts) -> bool cancel`. Increments `G.carCount[pid]` and returns true when the count would exceed `G.allowance`. `G.onDelete(pid)` decrements it, never below 0. `G.onLeave` also clears `G.carCount[pid]`.

- [ ] **Step 1: Write the failing tests** in `test_beammp_plugin.lua`:
  - three PROTO-3 players on one anchor, joinedAt 0/2/4: `trafficHosts` maps all three to pid 1; after `G.onLeave(1)`, all map to pid 2.
  - two anchors (Utah, Italy): each has its own host.
  - a PROTO-2 pose is ignored (`onPose` already rejects it); so it is never host and has no allowance entry beyond `PLAYER_CARS`.
  - `trafficMsg` for a non-host: `host` is the host's id string, `alone == false`; for a lone player: `alone == true`.
  - `allowance`: the host 18, a non-host 2, with `G.TRAFFIC.enabled = false` the host 2.
  - `onSpawn`: a non-host's third spawn returns true and its count stays 2; after `onDelete`, a spawn is allowed again.
- [ ] **Step 2: Run** `cd mod/tests && luajit test_beammp_plugin.lua`. Expected: FAIL (`trafficHosts` is nil).
- [ ] **Step 3: Implement** the functions above, and the Settings block values from Global Constraints. Set `G.PROTO = 3`. Wiring inside the `MP` block:
  - `MP.RegisterEvent('onVehicleSpawn', 'BNGE_onSpawn')`, where the handler returns `1` to cancel;
  - `MP.RegisterEvent('onVehicleDeleted', 'BNGE_onDelete')`;
  - in `BNGE_tick`, send each live player `bngeTraffic` (`G.trafficMsg`) when its signature changes, the same pattern as `G.sentPeers`;
  - print a line when a group's host changes: `[BeamNG.Earth] <name> hosts traffic for N player(s)`.
- [ ] **Step 4: Run** the test again. Expected: `test_beammp_plugin` passes.
- [ ] **Step 5: Commit**: `Server plugin: elect a traffic host per group and cap each player's cars`.

### Task 2: Server — relay the host's traffic car list

**Files:**
- Modify: `beammp/Server/BeamNGEarth/main.lua` (`G.onPose`)
- Test: `mod/tests/test_beammp_plugin.lua`

**Interfaces:**
- Consumes: the pose field `tr`, a list of BeamMP server vehicle strings (`"<pid>-<vid>"`), from the client (Task 5).
- Produces: `G.players[pid].tr`, the validated list, kept only when every entry matches `^%d+%-%d+$` and starts with that player's own pid. At most `G.TRAFFIC.amount + G.TRAFFIC.parked` entries. It goes out as `cars` in `trafficMsg`.

- [ ] **Step 1: Write the failing tests:** a host's pose with `tr = { '1-3', '1-4' }` makes the non-host's `trafficMsg(...).cars` equal `{ '1-3', '1-4' }`; entries for another pid (`'2-1'`), a non-string, or a list longer than the cap are dropped.
- [ ] **Step 2: Run** the test. Expected: FAIL.
- [ ] **Step 3: Implement** the validation in `G.onPose`, and include `cars` from the host's `tr` in `G.trafficMsg`. Include the list in the signature, so a changed list is sent again.
- [ ] **Step 4: Run** the test. Expected: PASS.
- [ ] **Step 5: Commit**: `Server plugin: tell each group which of the host's cars are traffic`.

### Task 3: Client — the traffic role from the server

**Files:**
- Create: `mod/beamng_earth/lua/ge/extensions/beamngEarth/trafficsync.lua`
- Test: `mod/tests/test_trafficsync.lua`

**Interfaces:**
- Consumes: the `bngeTraffic` message from Task 1/2.
- Produces: `trafficsync.choiceFor(msg, myPid, ownChoice) -> choice`, a pure function. The result has the same shape as `navgraph.choice` (`{ traffic, parked, police, trafficAmount, parkedAmount }`):
  - with no message, or `msg.alone`: `ownChoice` unchanged;
  - as host: `{ traffic = enabled, parked = enabled and parked > 0, police, trafficAmount = amount, parkedAmount = parked }`;
  - as a non-host: everything off.
- Produces: `trafficsync.remoteTraffic() -> { [serverVehicleString] = true }`, the latest `cars` set; `trafficsync.isHost() -> bool`; `trafficsync.onMessage(json)`; `trafficsync.reset()`.

- [ ] **Step 1: Write the failing tests** for `choiceFor` (all three cases, plus `enabled = false` as host means off). `onMessage` with bad JSON, or `v ~= 3`, leaves the state unchanged. `remoteTraffic` reflects `cars`.
- [ ] **Step 2: Run** `cd mod/tests && luajit test_trafficsync.lua`. Expected: FAIL (module missing).
- [ ] **Step 3: Implement** the module in the style of `mpsession.lua` (an `M` table, pure functions first, `log` guarded).
- [ ] **Step 4: Run** the test. Expected: PASS.
- [ ] **Step 5: Commit**: `Traffic sync: the server's traffic role for this player`.

### Task 4: Client — apply the role to traffic and parked cars at run time

**Files:**
- Modify: `mod/beamng_earth/lua/ge/extensions/beamngEarth/navgraph.lua` (around `M.choice`, `startTraffic`)
- Modify: `mod/beamng_earth/lua/ge/extensions/beamngEarth/parking.lua` (`M.update`, start of parked cars)
- Modify: `mod/beamng_earth/lua/ge/extensions/beamngEarth/mpsession.lua` (register the `bngeTraffic` handler next to the others, line ~487; feed `trafficsync`)
- Test: `mod/tests/test_navgraph.lua`, `mod/tests/test_parking.lua`

**Interfaces:**
- Consumes: `trafficsync.choiceFor`, `trafficsync.onMessage`.
- Produces: `navgraph.setChoice(c)`. It stores `c` as `M.choice`. If traffic is running and `c.traffic` is false, it calls `gameplay_traffic.deleteVehicles()`. If the graph is already built (`started`) and `c.traffic` is true while traffic is not running, it calls `startTraffic()`. It does the same for parked cars through `parking.setParked(on, amount)`, using `gameplay_parking.deleteVehicles()` and `setupVehicles`.
- In an MP session, `mpsession.update` calls `navgraph.setChoice(trafficsync.choiceFor(msg, myPid(), navgraph.ownChoice()))` on each new `bngeTraffic`, and on each tick. That tick check covers Review Focus 5: a non-host who turned traffic on from the radial menu has it turned off. `navgraph.ownChoice()` returns the level-start choice, saved separately from `M.choice`.

- [ ] **Step 1: Write the failing tests** with stubbed `gameplay_traffic` and `gameplay_parking` (state, and counters for `deleteVehicles` and `setupTraffic` calls):
  - `setChoice({traffic=false})` while traffic is on: `deleteVehicles` is called once;
  - `setChoice({traffic=true, trafficAmount=6})` after the graph is built: `setupTraffic(6, …)` is called once, and a repeat call does nothing more;
  - `setChoice` before the graph is built: nothing is called, and the choice is used when it is built;
  - `ownChoice()` still returns the level-start choice after `setChoice`;
  - the parked-car equivalents in `test_parking.lua`.
- [ ] **Step 2: Run** `luajit test_navgraph.lua` and `luajit test_parking.lua`. Expected: FAIL.
- [ ] **Step 3: Implement** `setChoice`, `ownChoice`, `parking.setParked`, and the `mpsession` wiring.
- [ ] **Step 4: Run** both tests, plus `test_mpsession.lua`. Expected: all pass.
- [ ] **Step 5: Commit**: `Traffic sync: only the host runs traffic and parked cars in a BeamMP group`.

### Task 5: Client — the host reports its traffic; the others treat it as traffic

**Files:**
- Modify: `mpsession.lua` (the pose at line ~571: add `tr`; protocol `M.PROTO = 3`)
- Modify: `collisionfoci.lua` (`kind` for remote cars, line ~104)
- Modify: `farcars.lua` (skip remote traffic)
- Test: `mod/tests/test_mpsession.lua`, `mod/tests/test_collisionfoci.lua`

**Interfaces:**
- Consumes: `trafficsync.isHost()`, `trafficsync.remoteTraffic()`.
- Produces: `mpsession.trafficIds(trafficIds, parkedIds, toServerId) -> { serverVehicleString... }`, a pure function. It maps the host's `gameplay_traffic.getTrafficData()` ids and `gameplay_parking` ids through `MPVehicleGE.getServerVehicleID` (or the Task 0 equivalent), dropping ids with no server id. The pose carries `tr` only when `isHost()`.
- In `collisionfoci`, a remote vehicle whose server vehicle string is in `trafficsync.remoteTraffic()` gets `kind = 'traffic'`; `farcars` already skips anything that is not `'player'`.

- [ ] **Step 1: Write the failing tests:** `trafficIds` with a stub mapper (one id unmapped, so it is dropped); `collisionfoci`'s vehicle list classes a remote car in the set as `'traffic'` and one outside it as `'player'`.
- [ ] **Step 2: Run** the tests. Expected: FAIL.
- [ ] **Step 3: Implement** the changes.
- [ ] **Step 4: Run** `test_mpsession.lua`, `test_collisionfoci.lua`, `test_farcars.lua` and `test_beammp_plugin.lua`. Expected: all pass.
- [ ] **Step 5: Commit**: `Traffic sync: the host's traffic is traffic in everyone's game`.

### Task 6: Server setup, docs, and a live two-player test

**Files:**
- Modify: `beammp/setup_otbt_server.sh` (`MAXCARS` setting, default 18, written as `MaxCars`; on a re-run, raise an existing lower `MaxCars` in place with `sed`, and keep the rest of the config)
- Modify: `beammp/README.md` (traffic in a BeamMP session; the `G.TRAFFIC` settings)
- Modify: `docs/ARCHITECTURE.md` ("Parked cars and traffic": a BeamMP subsection), `CHANGELOG.md`

- [ ] **Step 1:** Make the script change. Check it with `bash -n beammp/setup_otbt_server.sh`.
- [ ] **Step 2:** Update the docs and the changelog.
- [ ] **Step 3:** Run every Lua test: `cd mod/tests && for f in test_*.lua; do luajit $f || echo FAIL $f; done`. Expected: no `FAIL` lines.
- [ ] **Step 4: Commit**: `BeamMP: shared traffic (server-elected host), setup and docs`.
- [ ] **Step 5: Deploy to OTBT's server** (after the user agrees): `ssh -t otbt-beamng 'sudo BRANCH=otbt-traffic-sync bash /root/setup_otbt_server.sh'`. Check that the log shows `plugin loaded` and that `MaxCars = 18`.
- [ ] **Step 6: Live test** with two players near each other in Johannesburg:
  - player 1 joins first and becomes host (log: `hosts traffic for 2 player(s)`);
  - both see the same traffic cars in the same places;
  - player 2's own traffic stays off, even after they choose traffic in the radial menu;
  - player 1 leaves: within about 5 s, player 2's game starts traffic and the log names player 2 as host.
  Record the results in the research file from Task 0.
