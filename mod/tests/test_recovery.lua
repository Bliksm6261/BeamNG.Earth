-- Tests for recovery.lua:
-- 1. Field tire puncture repair and cooldown tracking.
-- 2. Kinetic snatch-strap tow tethering and force impulse.
-- 3. Channel 9 10-33 emergency breakdown SOS transmission.
-- 4. High-Lift jack suspension realignment.

local dir = (arg and arg[0] or ''):match('^(.*)[/\\]') or '.'
local T = dofile(dir .. '/testlib.lua')

-- Stub dependencies
local storage = {}
function jsonReadFile(path) return storage[path] end
function jsonWriteFile(path, data) storage[path] = data; return true end

package.loaded['beamngEarth/gps'] = { setDestination = function() return true end }
package.loaded['beamngEarth/freight'] = {
  getCompany = function() return { name = 'OTBT Recovery Ops' } end
}
package.loaded['beamngEarth/convoy'] = {
  getRadarTargets = function()
    return {
      { name = 'Heavy Escort Rig', distanceM = 22, type = 'truck' }
    }
  end,
  transmit = function(ch, msg, callsign, code)
    return true, { channel = ch, message = msg, code = code }
  end
}

local recovery = require('beamngEarth/recovery')

--------------------------------------------------------------------------------
-- 1. Field Tire Puncture Repair
--------------------------------------------------------------------------------
do
  recovery.reset()
  local queuedCmd = nil
  local mockVeh = {
    queueLuaCommand = function(self, cmd) queuedCmd = cmd end
  }

  local ok, res = recovery.repairTires(mockVeh)
  T.check(ok, 'tire puncture repair executed')
  T.check(queuedCmd ~= nil and queuedCmd:find('setTirePressure'), 'sent tire reinflation command to vehicle Lua')

  -- Immediate re-repair triggers cooldown
  local coolOk, coolErr = recovery.repairTires(mockVeh)
  T.check(coolOk == false, 'cooldown prevented rapid tire repair spam')
end

--------------------------------------------------------------------------------
-- 2. Kinetic Snatch-Strap & Tow Recovery
--------------------------------------------------------------------------------
do
  local appliedImpulse = false
  local impulse = nil
  local vec3Mt = {
    __mul = function(v, scale)
      return vec3(v.x * scale, v.y * scale, v.z * scale)
    end
  }
  function vec3(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, vec3Mt)
  end
  -- Identity rotation preserves the forward vector used by the recovery pull.
  local identityQuat = setmetatable({}, {
    __mul = function(_, v) return vec3(v.x, v.y, v.z) end
  })
  local mockVeh = {
    getRotation = function() return identityQuat end,
    getRefNodeId = function() return 0 end,
    applyClusterVelocityScaleAdd = function(self, node, scale, vec)
      appliedImpulse = true
      impulse = vec
    end
  }

  local ok, res = recovery.connectSnatchStrap(-26.2, 28.0, mockVeh)
  T.check(ok, 'snatch-strap connected to nearby teammate')
  T.check(res.target == 'Heavy Escort Rig', 'tethered to Heavy Escort Rig within 22m')
  T.check(appliedImpulse == true, 'applied recovery impulse pulling force')
  T.check(impulse and impulse.x == 0 and impulse.y == 2.5 and impulse.z == 0.5,
    'recovery impulse pulls forward with a small upward lift')

  local st = recovery.getUiState(-26.2, 28.0, mockVeh)
  T.check(st.towActive == true, 'recovery state marks tow active')
  T.check(st.tetherTarget == 'Heavy Escort Rig', 'records tether target')
end

--------------------------------------------------------------------------------
-- 3. Channel 9 10-33 Emergency SOS
--------------------------------------------------------------------------------
do
  local ok, res = recovery.sendEmergencySos(-25.7461, 28.1881, nil)
  T.check(ok, 'transmitted emergency SOS')
  T.check(res.channel == 9, 'routed to Channel 9 Emergency Frequency')
  T.check(res.code == 'breakdown', 'preset code marked breakdown')
  T.check(res.message:find('10%-33 EMERGENCY'), 'message formatted with 10-33 breakdown callout')
end

--------------------------------------------------------------------------------
-- 4. High-Lift Jack & Suspension Realignment
--------------------------------------------------------------------------------
do
  local jackCmd = nil
  local stoppedVeh = {
    getVelocity = function() return { length = function() return 0.0 end } end,
    queueLuaCommand = function(self, cmd) jackCmd = cmd end
  }

  local ok = recovery.realignSuspension(stoppedVeh)
  T.check(ok, 'High-Lift jack aligned suspension')
  T.check(jackCmd ~= nil and jackCmd:find('resetAlignment'), 'sent wheel realignment command')
end

T.done('test_recovery')
