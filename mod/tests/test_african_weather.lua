-- Tests for african_weather.lua:
-- 1. Presets catalog (Highveld Supercell, Kalahari Haboob, Drakensberg Mist, Karoo Heatwave).
-- 2. Regional and diurnal weather detection.
-- 3. Mud physics & surface friction degradation.
-- 4. Manual preset application and auto-scheduling.

local dir = (arg and arg[0] or ''):match('^(.*)[/\\]') or '.'
local T = dofile(dir .. '/testlib.lua')

-- Stub dependencies
local storage = {}
function jsonReadFile(path) return storage[path] end
function jsonWriteFile(path, data) storage[path] = data; return true end

package.loaded['beamngEarth/gps'] = { setDestination = function() return true end }
package.loaded['beamngEarth/weather'] = {
  onWeather = function(msg) return true end
}

local aw = require('beamngEarth/african_weather')

--------------------------------------------------------------------------------
-- 1. Catalog Verification
--------------------------------------------------------------------------------
do
  local presets = aw.PRESETS
  T.check(#presets >= 5, 'contains at least 5 regional African weather presets')

  local map = {}
  for _, p in ipairs(presets) do
    T.check(p.id ~= nil, 'preset has id')
    T.check(p.name ~= nil, 'preset has descriptive name')
    T.check(p.icon ~= nil, 'preset has icon')
    T.check(p.tempC ~= nil, 'preset has temperature')
    map[p.id] = p
  end

  T.check(map['highveld_thunderstorm'] ~= nil, 'contains Highveld Summer Supercell')
  T.check(map['kalahari_haboob'] ~= nil, 'contains Kalahari Haboob dust storm')
  T.check(map['escarpment_fog'] ~= nil, 'contains Drakensberg Escarpment Mist')
  T.check(map['karoo_scorcher'] ~= nil, 'contains Karoo Heatwave')
end

--------------------------------------------------------------------------------
-- 2. Regional & Diurnal Weather Detection
--------------------------------------------------------------------------------
do
  -- Johannesburg Highveld in mid-afternoon (tod = 0.65 ~ 15:30)
  local stormId = aw.detectRegionalWeather(-26.2041, 28.0473, 0.65)
  T.check(stormId == 'highveld_thunderstorm', 'detected Highveld afternoon supercell storm')

  -- Drakensberg Escarpment in early morning (tod = 0.25 ~ 06:00)
  local fogId = aw.detectRegionalWeather(-29.2000, 29.5000, 0.25)
  T.check(fogId == 'escarpment_fog', 'detected Drakensberg mountain mist')

  -- Kalahari Desert in blazing afternoon (tod = 0.50 ~ 12:00)
  local dustId = aw.detectRegionalWeather(-24.0000, 18.0000, 0.50)
  T.check(dustId == 'kalahari_haboob', 'detected Kalahari desert dust haboob')
end

--------------------------------------------------------------------------------
-- 3. Mud Physics & Surface Friction Dynamics
--------------------------------------------------------------------------------
do
  aw.reset()

  -- Apply Highveld Supercell
  local ok, p = aw.applyPreset('highveld_thunderstorm')
  T.check(ok, 'applied Highveld Supercell preset')
  T.check(p.rainMmH >= 50.0, 'heavy precipitation configured (55 mm/h)')

  local st = aw.getUiState()
  T.check(st.activePreset.id == 'highveld_thunderstorm', 'active preset is supercell')
  T.check(st.mudFriction < 0.60, 'dirt road friction degraded to slick red mud (~0.50)')

  -- Reset to clear weather
  local ok2, p2 = aw.applyPreset('savanna_clear')
  T.check(ok2, 'applied clear weather')
  local st2 = aw.getUiState()
  T.check(st2.mudFriction == 1.0, 'surface friction restored to 1.0 under clear sky')
end

T.done('test_african_weather')
