-- The level's info.json for the freeroam level select (the user, 2026-10-20: "have the location selector
-- automatically match the places list"): a spawn point per saved place (places.lua), "Random location" and the
-- default start, and the level's details as the stock levels have them, for the whole Earth.
--
-- Written to /levels/beamng_earth/info.json in the user folder, where it stands over the mod's own copy (checked in
-- game 2026-10-20: the level list reads the user folder's; deleting it brings the mod's back). core_levels drops its
-- level list when a file under /levels/ changes, so the menu shows the new list by itself. Written only when its text
-- changes (each write is a file event and a rebuilt level list).
--
-- The spawn point the player picks is saved by the game (setSpawnpoint.setDefaultSP, settings/cloud/game-state.json
-- levels.beamng_earth.defaultSpawnPointName); our level has no SpawnSphere of those names, the car starts at the
-- default one, and core's start teleport goes to the place it names (M.chosen).

local M = {}

M.PATH = '/levels/beamng_earth/info.json'
M.GAME_STATE = 'settings/cloud/game-state.json'
M.LEVEL = 'beamng_earth'
M.DEFAULT = 'spawn_default'
M.RANDOM = 'bne_random'
M.PREFIX = 'bne_place_'
M.PREVIEW = 'beamng_earth_preview.jpg'
M.PLACE_PREVIEWS = 'places/'           -- per place: <PLACE_PREVIEWS><previewKey>.jpg (the server writes them)

-- The edition's region (stock levels' fields; levelTiles.lua shows size as width x height (area)). Kept the same as
-- tools/make_level_assets.py's info.json.
M.BASE = {
  title = 'Off the Beaten Track: Southern Africa',
  description = 'Southern Africa at full scale, from Cape Town to the Serengeti, built around you by the Off the '
    .. 'Beaten Track app (offthebeatentrack.world, built on BeamNG.Earth). Start the app, then pick a city '
    .. 'below or teleport from the map. Preview: Sentinel-2 cloudless 2016 by EOX IT Services GmbH (CC BY '
    .. '4.0).',
  previews = { M.PREVIEW },
  size = { 3070277, 3772300 },   -- the region's box (region.lua): ~29 deg of longitude at 18 S by ~34 deg of latitude
  biome = 'Savanna, bushveld, Kalahari and Namib desert, Drakensberg mountains, Okavango wetlands, coast and lakes',
  roads = 'Every road in ten countries: highways, city streets, gravel roads, mountain passes and 4x4 tracks',
  suitablefor = 'Overlanding, 4x4 trails, road trips, exploring, freeroam',
  features = 'Real terrain, roads, passes, towns and live weather across South Africa, Namibia, Botswana, '
    .. 'Zimbabwe, Zambia, Mozambique, Lesotho, Eswatini, Malawi and Tanzania',
  country = 'Southern Africa (10 countries)',
  authors = 'Off the Beaten Track (built on BeamNG.Earth)',
  defaultSpawnPointName = M.DEFAULT,
  supportsTraffic = true,
  supportsTimeOfDay = true,
}

-- A place's preview file name: its rounded position (a rename keeps the picture; a moved place gets a new one).
function M.previewKey(lat, lon) return string.format('%.4f_%.4f', lat, lon):gsub('-', 'm'):gsub('%.', 'p') end

local function copy(t)
  local o = {}
  for k, v in pairs(t) do o[k] = type(v) == 'table' and copy(v) or v end
  return o
end

-- The info table for places ({ id, name, lat, lon }); hasPreview(key) -> true when that place's picture exists.
function M.build(placeList, hasPreview)
  local info = copy(M.BASE)
  local sp = {
    { objectname = M.DEFAULT, translationId = 'Where you left off', preview = M.PREVIEW,
      description = 'The last place you teleported to.' },
    { objectname = M.RANDOM, translationId = 'Random location', preview = M.PREVIEW,
      description = 'A road somewhere in Southern Africa, picked at random each time.' },
  }
  for _, p in ipairs(placeList or {}) do
    local key = M.previewKey(p.lat, p.lon)
    sp[#sp + 1] = { objectname = M.PREFIX .. tostring(p.id), translationId = p.name,
      description = string.format('%.5f, %.5f', p.lat, p.lon),
      preview = (hasPreview and hasPreview(key)) and (M.PLACE_PREVIEWS .. key .. '.jpg') or M.PREVIEW }
  end
  info.spawnPoints = sp
  return info
end

local last = nil -- the text written last (or read back)

-- Write the info for placeList when it differs from the file. Returns true when it wrote.
function M.write(placeList)
  local enc, write, read = rawget(_G, 'jsonEncodePretty') or rawget(_G, 'jsonEncode'), rawget(_G, 'writeFile'),
    rawget(_G, 'readFile')
  if not enc or not write then return false end
  local function hasPreview(key)
    return FS and FS.fileExists and FS:fileExists('/levels/beamng_earth/' .. M.PLACE_PREVIEWS .. key .. '.jpg') or false
  end
  local ok, text = pcall(enc, M.build(placeList, hasPreview))
  if not ok or type(text) ~= 'string' then return false end
  if last == nil and read then
    local ok2, cur = pcall(read, M.PATH)
    last = ok2 and cur or ''
  end
  if text == last then return false end
  local ok3, res = pcall(write, M.PATH, text)
  if not ok3 or res == false then
    log('W', 'beamngEarth', 'level info: write failed: ' .. tostring(res))
    return false
  end
  last = text
  return true
end

-- The places whose picture is not there yet and not asked for this session: { { key, lat, lon } }, each marked asked.
local asked = {}
function M.missing(placeList)
  local out = {}
  for _, p in ipairs(placeList or {}) do
    local key = M.previewKey(p.lat, p.lon)
    if not asked[key] and not (FS and FS.fileExists
        and FS:fileExists('/levels/beamng_earth/' .. M.PLACE_PREVIEWS .. key .. '.jpg')) then
      asked[key] = true
      out[#out + 1] = { key = key, lat = p.lat, lon = p.lon }
    end
  end
  return out
end

-- The spawn point the player picked for our level: M.DEFAULT, M.RANDOM, M.PREFIX .. id, or nil.
function M.chosen()
  local read = rawget(_G, 'jsonReadFile')
  if not read then return nil end
  local ok, data = pcall(read, M.GAME_STATE)
  local lv = ok and type(data) == 'table' and type(data.levels) == 'table' and data.levels[M.LEVEL] or nil
  local name = type(lv) == 'table' and lv.defaultSpawnPointName or nil
  return type(name) == 'string' and name or nil
end

-- The place id of a spawn point name, or nil.
function M.placeId(name)
  local id = type(name) == 'string' and name:match('^' .. M.PREFIX .. '(%d+)$')
  return id and tonumber(id) or nil
end

function M._reset() last, asked = nil, {} end -- tests

return M
