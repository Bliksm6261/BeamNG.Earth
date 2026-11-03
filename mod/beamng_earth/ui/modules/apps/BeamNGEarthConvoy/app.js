// BeamNG.Earth Convoy Radar & CB Radio HUD App (lua/ge/extensions/beamngEarth/convoy.lua)
angular.module('beamng.apps')
.directive('beamngEarthConvoy', [function () {
  return {
    template:
      '<div class="bngApp" style="width:100%;height:100%;background:transparent;box-shadow:none;overflow:visible;" layout="column">' +
        '<div ng-show="!hidden" style="background:rgba(12,16,24,0.90);border-left:4px solid #00c07f;border-radius:5px;padding:8px 12px;color:#f0f2f5;font-family:sans-serif;box-shadow:0 4px 14px rgba(0,0,0,0.55);">' +
          '<div layout="row" layout-align="space-between center" style="border-bottom:1px solid rgba(255,255,255,0.1);padding-bottom:4px;margin-bottom:6px;">' +
            '<span style="font-weight:bold;font-size:12px;color:#00ffaa;display:flex;align-items:center;gap:4px;">' +
              '📡 CONVOY RADAR &middot; 📻 CH {{ currentChannel }}' +
            '</span>' +
            '<span style="font-size:11px;color:#a0aab8;font-weight:bold;">' +
              '{{ speedKmh }} km/h' +
            '</span>' +
          '</div>' +

          '<!-- Radar Targets List -->' +
          '<div style="max-height:85px;overflow-y:auto;display:flex;flex-direction:column;gap:4px;margin-bottom:6px;">' +
            '<div ng-repeat="target in targets" layout="row" layout-align="space-between center" style="background:rgba(255,255,255,0.05);padding:3px 6px;border-radius:3px;font-size:11px;">' +
              '<span style="color:#fff;font-weight:600;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;max-width:140px;">' +
                '{{ target.type === "truck" ? "🚚" : "🚙" }} {{ target.name }}' +
              '</span>' +
              '<span style="color:#FFB54A;font-weight:bold;">' +
                '{{ target.distanceM }}m' +
              '</span>' +
              '<span style="color:#8fe0ba;font-size:10px;">' +
                '{{ target.clockDirection }}' +
              '</span>' +
              '<span style="font-size:10px;padding:1px 4px;border-radius:2px;font-weight:bold;" ng-style="{ background: target.cargoHealth > 80 ? \'rgba(40,167,69,0.3)\' : \'rgba(220,53,69,0.3)\', color: target.cargoHealth > 80 ? \'#28a745\' : \'#dc3545\' }">' +
                '{{ target.cargoHealth }}%' +
              '</span>' +
            '</div>' +
            '<div ng-show="!targets || targets.length === 0" style="color:#788696;font-size:11px;font-style:italic;text-align:center;padding:4px 0;">' +
              'Radar scanning... No convoy members nearby' +
            '</div>' +
          '</div>' +

          '<!-- CB Radio Recent Chatter Ticker -->' +
          '<div style="background:rgba(0,0,0,0.4);border-radius:3px;padding:3px 6px;font-size:11px;color:#cbd5e1;display:flex;align-items:center;gap:6px;border:1px solid rgba(0,255,170,0.15);">' +
            '<span style="font-size:12px;">📻</span>' +
            '<span style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap;max-width:240px;color:#a3e635;">' +
              '{{ latestChatter }}' +
            '</span>' +
          '</div>' +

          '<!-- Quick Preset Callouts -->' +
          '<div layout="row" layout-align="space-between center" style="margin-top:6px;gap:4px;">' +
            '<button ng-click="sendCallout(\'10-4\')" style="flex:1;background:rgba(255,255,255,0.08);border:1px solid rgba(255,255,255,0.15);color:#fff;border-radius:3px;font-size:10px;padding:2px 0;cursor:pointer;">' +
              '10-4' +
            '</button>' +
            '<button ng-click="sendCallout(\'smokey\')" style="flex:1;background:rgba(255,255,255,0.08);border:1px solid rgba(255,255,255,0.15);color:#fff;border-radius:3px;font-size:10px;padding:2px 0;cursor:pointer;">' +
              '⚠️ Smokey' +
            '</button>' +
            '<button ng-click="sendCallout(\'hazard\')" style="flex:1;background:rgba(255,255,255,0.08);border:1px solid rgba(255,255,255,0.15);color:#fff;border-radius:3px;font-size:10px;padding:2px 0;cursor:pointer;">' +
              '⚠️ Hazard' +
            '</button>' +
            '<button ng-click="sendCallout(\'fuel\')" style="flex:1;background:rgba(255,255,255,0.08);border:1px solid rgba(255,255,255,0.15);color:#fff;border-radius:3px;font-size:10px;padding:2px 0;cursor:pointer;">' +
              '⛽ Fuel' +
            '</button>' +
          '</div>' +
        '</div>' +
      '</div>',
    replace: true,
    link: function (scope) {
      'use strict'
      scope.hidden = false
      scope.currentChannel = 19
      scope.speedKmh = 0
      scope.targets = []
      scope.latestChatter = 'Channel 19 idle &middot; Press preset to call'

      var hello = function (on) {
        bngApi.engineLua('if beamngEarth_core and beamngEarth_core.hudApp then beamngEarth_core.hudApp("convoy", ' + on + ') end')
      }

      scope.sendCallout = function (code) {
        var presets = {
          '10-4': '10-4, copy that good buddy!',
          'smokey': '⚠️ Smokey / speed trap spotted ahead!',
          'hazard': '⚠️ Road hazard / debris in lane. Slow down!',
          'fuel': '⛽ Pulling into fuel stop / rest area.'
        }
        var msg = presets[code] || '10-4'
        var lua = 'beamngEarth_settings.uiCbTransmit(' + scope.currentChannel + ', "' + msg + '", nil, "' + code + '")'
        bngApi.engineLua(lua)
      }

      scope.$on('BeamNGEarthHud', function (event, data) {
        scope.$evalAsync(function () {
          scope.hidden = !!(data && data.hidden)
          var cv = data && data.convoy
          if (!cv) return

          scope.currentChannel = cv.currentChannel || 19
          scope.speedKmh = cv.speedKmh || 0
          scope.targets = cv.radarTargets || []

          if (cv.recentChatter && cv.recentChatter.length > 0) {
            var top = cv.recentChatter[0]
            scope.latestChatter = '[' + top.callsign + '] ' + top.message
          }
        })
      })

      hello(true)
      var again = setInterval(function () { hello(true) }, 3000)
      scope.$on('$destroy', function () { clearInterval(again); hello(false) })
    }
  }
}]);
