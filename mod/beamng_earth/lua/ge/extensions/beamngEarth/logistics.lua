-- Resolve settings lazily to avoid a settings/module load cycle.
local M = {}
function M.enabled()
  local settings = rawget(_G, 'beamngEarth_settings') or package.loaded['beamngEarth/settings']
  return settings ~= nil and settings.get ~= nil and settings.get('otbtLogisticsEnabled') == true
end
return M
