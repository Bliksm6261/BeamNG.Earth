# OTBT Overland vehicle pack: brief for the modder

Off the Beaten Track (https://offthebeatentrack.world) is a Southern African overlanding platform. This pack gives
players of the OTBT edition of BeamNG.Earth a garage of overland builds of BeamNG's stock vehicles, in OTBT colours
with South African style plates. It ships as its own zip (`otbt_overland.zip`) that the OTBT BeamMP server sends to
every player, so everyone sees the same cars. Brand orange is **#FF9500**.

The full list of builds, and what each one needs, is `builds.json` in this folder. In short:

| # | Config | Based on | Stands in for | New parts it needs |
|---|---|---|---|---|
| 1 | OTBT Bakkie Double Cab | Gavril D-Series crew cab (`pickup`) | Hilux / Ranger | canopy + rack, rooftop tent, long-range tank, snorkel, jerry cans, recovery boards |
| 2 | OTBT Cruiser | Gavril Roamer (`roamer`) | Land Cruiser / Prado | roof rack, rooftop tent, long-range tank, snorkel, rear wheel carrier, awning |
| 3 | OTBT Mini | Ibishu Hopper (`hopper`) | Jimny | roof rack, snorkel, rear jerry can |

## Who does what

**The modder (needs Blender and the game):**
1. **3D accessories** as new jbeam parts that slot into the stock vehicles: rooftop tent, roof rack and canopy,
   snorkel, long-range tank, jerry can holder, rear wheel carrier, awning, recovery boards. Model each once and fit
   it per vehicle (a mount per model). Give the heavy ones real mass (a tent is about 60 kg, a full 80 L tank about
   70 kg) so they change how the car drives. Keep them simple: no flexbody for small parts if a prop does the job.
2. **The OTBT livery** as a skin for each of the three models, from `art/livery_otbt.svg` laid onto each model's
   skin UV map. Paint slot 1 stays the player's choice; the graphic sits on top.
3. **The South African plate design** from `art/plate_za_otbt.svg` (520 x 110 mm, white with an OTBT strip and
   "ZA"; deliberately not a real province's plate) as a licence plate design the configs use.
4. **Save the three configs** in game (Vehicle Config, Save) with the parts in `builds.json`, into
   `mod/vehicles/<model>/<config>.pc`, plus a thumbnail `<config>.jpg` (500 x 281). Use the real slot and part
   names of the current BeamNG version: our files never guess them.
5. **Test drive** each build on Sani Pass and a Kalahari sand track in BeamNG.Earth: it must climb, not tip over on
   the rack's weight, and not break on corrugations.

**We do (in this repository):**
- `builds.json`: the list of builds and their parts (change it with Chad).
- `tools/build_vehicle_pack.py`: zips `mod/` into `dist/otbt_overland.zip`, writes each config's
  `info_<config>.json` (name, brand, description) from `builds.json`, and checks every build has its `.pc`.
- The BeamMP server zip includes the pack as `Resources/Client/otbt_overland.zip`.
- The artwork sources in `art/`.

## Rules

- Only stock BeamNG vehicles as the base, and only our own new parts and art: no parts or textures copied from other
  mods, and no real manufacturers' names or logos (Toyota, Ford, ARB, Front Runner...), so the pack can be shared and
  sponsored.
- All new files go under `mod/`, in the game's own folder layout (`vehicles/<model>/...`; shared parts in
  `vehicles/common/otbt/...`). Prefix every part and file name with `otbt_` so nothing clashes with other mods.
- Keep the pack small: players download it when they join. Aim for under 100 MB with textures at 2048 px at most.

## Order of work

Start with build 1, the double-cab bakkie, end to end (one accessory set, livery, plate, saved config) so we can test
the whole path from the server to a player's garage early. Then the other two.
