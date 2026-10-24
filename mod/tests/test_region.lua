-- luajit mod/tests/test_region.lua  (the edition's playable region, region.lua / regiondata.lua)
-- Each covered country's capital is inside, its neighbours outside the edition are not, Lesotho (a hole in South
-- Africa's polygon) is inside through its own polygon, every first-run place is inside, and a region with no
-- polygons leaves the whole planet open.
local T = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/testlib.lua')
local region = require('beamngEarth/region')

T.check(region.enabled(), 'the edition limits the region')
T.check(region.name():match('Southern Africa') ~= nil, 'the region has its name')
T.check(#region.data.countries == 10, 'ten countries (' .. #region.data.countries .. ')')

local inside = {
  { 'Pretoria', -25.746, 28.188 }, { 'Cape Town', -33.925, 18.424 }, { 'Windhoek', -22.560, 17.083 },
  { 'Gaborone', -24.654, 25.908 }, { 'Harare', -17.829, 31.053 }, { 'Lusaka', -15.387, 28.322 },
  { 'Maputo', -25.966, 32.573 }, { 'Maseru (Lesotho, a hole in South Africa)', -29.310, 27.478 },
  { 'Sani Top (Lesotho)', -29.5868, 29.2886 }, { 'Mbabane', -26.305, 31.137 }, { 'Lilongwe', -13.963, 33.774 },
  { 'Dodoma', -6.163, 35.752 }, { 'Zanzibar Town', -6.165, 39.199 },
}
for _, p in ipairs(inside) do T.check(region.contains(p[2], p[3]), p[1] .. ' inside') end

local outside = {
  { 'Luanda, Angola', -8.839, 13.289 }, { 'Kinshasa, DR Congo', -4.441, 15.266 }, { 'Nairobi, Kenya', -1.286, 36.817 },
  { 'Antananarivo, Madagascar', -18.879, 47.508 }, { 'Kigali, Rwanda', -1.944, 30.062 },
  { 'the Atlantic off Cape Town', -34.0, 16.5 }, { 'Mount Whitney, USA', 36.5785, -118.2923 }, { 'Null Island', 0, 0 },
}
for _, p in ipairs(outside) do T.check(not region.contains(p[2], p[3]), p[1] .. ' outside') end
T.check(not region.contains('x', nil), 'no lat/lon: outside')

-- the margin: a place just past a simplified coastline or border is still in, one well past it is not
T.check(region.contains(-34.0886, 18.3606 - 0.02), 'Chapman\'s Peak 2 km out to sea: inside (the margin)')
T.check(not region.contains(-34.0886, 18.3606 - 0.2), '20 km out to sea: outside')

-- every first-run place is somewhere the player may go
local places = require('beamngEarth/places')
for _, s in ipairs(places.SEED) do T.check(region.contains(s.lat, s.lon), 'first-run place inside: ' .. s.name) end

-- no polygons (an edition without a region): everything is open
region._setData({ name = 'none', countries = {}, polygons = {} })
T.check(not region.enabled() and region.name() == '', 'no polygons: not enabled')
T.check(region.contains(36.5785, -118.2923) and region.contains(0, 0), 'no polygons: the whole planet is open')
region._setData()
T.check(region.enabled(), 'back to the edition\'s region')

T.done('test_region')
