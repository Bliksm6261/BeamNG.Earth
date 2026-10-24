-- The edition's playable region (the Off the Beaten Track edition: the countries its maps cover; regiondata.lua,
-- built by tools/build_region.py). core.teleportTo refuses a place outside it, whatever asked for the teleport (the
-- world map, search, saved places, the console, a BeamMP player to join). No polygons: the whole planet is open.
--
--   region.enabled()          -> true when the edition limits where the player can go
--   region.contains(lat, lon) -> true inside one of the countries (always true when not enabled)
--   region.name()             -> the region's name for messages ('' when not enabled)
--
-- A polygon is its outer ring then its holes (South Africa's hole is Lesotho, its own polygon): inside one polygon
-- (even-odd over its rings) is inside the region. Each polygon's bounding box is checked first. The polygons are
-- simplified to about 1 km, so a place within MARGIN_KM of a polygon's outer ring counts as inside too (a beach, a
-- coastal road, a border post): the edge is a little generous, never short.

local M = {}

M.MARGIN_KM = 5
local KM_LAT = 111.32 -- km per degree of latitude

local data = require('beamngEarth/regiondata')

local polys = {}  -- { rings = { flat lat, lon, ... }, s, w, n, e }

local function load(d)
  polys = {}
  for _, p in ipairs((d and d.polygons) or {}) do
    local q = { rings = p.rings or {}, s = 90, w = 180, n = -90, e = -180 }
    local outer = q.rings[1]
    if outer and #outer >= 6 then
      for i = 1, #outer - 1, 2 do
        local la, lo = outer[i], outer[i + 1]
        if la < q.s then q.s = la end
        if la > q.n then q.n = la end
        if lo < q.w then q.w = lo end
        if lo > q.e then q.e = lo end
      end
      polys[#polys + 1] = q
    end
  end
  M.data = d
end

-- even-odd crossing test of (lat, lon) against a flat ring
local function inRing(r, lat, lon)
  local inside = false
  local n = #r
  local jLat, jLon = r[n - 1], r[n]
  for i = 1, n - 1, 2 do
    local iLat, iLon = r[i], r[i + 1]
    if (iLat > lat) ~= (jLat > lat) and lon < (jLon - iLon) * (lat - iLat) / (jLat - iLat) + iLon then
      inside = not inside
    end
    jLat, jLon = iLat, iLon
  end
  return inside
end

-- km from (lat, lon) to the nearest edge of a flat ring (equirectangular about lat: fine at a few km)
local function ringDistKm(r, lat, lon)
  local kx = KM_LAT * math.cos(math.rad(lat))
  local best = math.huge
  local n = #r
  local ax, ay = (r[n] - lon) * kx, (r[n - 1] - lat) * KM_LAT
  for i = 1, n - 1, 2 do
    local bx, by = (r[i + 1] - lon) * kx, (r[i] - lat) * KM_LAT
    local dx, dy = bx - ax, by - ay
    local L2 = dx * dx + dy * dy
    local t = L2 > 0 and math.max(0, math.min(1, -(ax * dx + ay * dy) / L2)) or 0
    local px, py = ax + t * dx, ay + t * dy
    local d = px * px + py * py
    if d < best then best = d end
    ax, ay = bx, by
  end
  return math.sqrt(best)
end

function M.enabled() return #polys > 0 end

function M.name() return (M.enabled() and M.data and M.data.name) or '' end

function M.contains(lat, lon)
  if #polys == 0 then return true end
  lat, lon = tonumber(lat), tonumber(lon)
  if not lat or not lon then return false end
  for _, q in ipairs(polys) do
    if lat >= q.s and lat <= q.n and lon >= q.w and lon <= q.e then
      local inside = false
      for _, r in ipairs(q.rings) do
        if inRing(r, lat, lon) then inside = not inside end
      end
      if inside then return true end
    end
  end
  local mLat = M.MARGIN_KM / KM_LAT
  local mLon = M.MARGIN_KM / (KM_LAT * math.max(math.cos(math.rad(lat)), 0.05))
  for _, q in ipairs(polys) do
    if lat >= q.s - mLat and lat <= q.n + mLat and lon >= q.w - mLon and lon <= q.e + mLon
      and ringDistKm(q.rings[1], lat, lon) <= M.MARGIN_KM then
      return true
    end
  end
  return false
end

-- tests: another region (nil: back to regiondata.lua)
function M._setData(d) load(d or data) end

load(data)

return M
