// BeamNG.Earth Trucker HUD App (lua/ge/extensions/beamngEarth/freight.lua)
angular.module('beamng.apps')
.directive('beamngEarthFreight', [function () {
  return {
    template:
      '<div class="bngApp" style="width:100%;height:100%;background:transparent;box-shadow:none;overflow:visible;" layout="column">' +
        '<div ng-show="active && !hidden" style="background:rgba(12,15,20,0.85);border-left:4px solid #FF9500;border-radius:4px;padding:6px 12px;color:#f0f2f5;font-family:sans-serif;box-shadow:0 4px 12px rgba(0,0,0,0.5);">' +
          '<div layout="row" layout-align="space-between center">' +
            '<span style="font-weight:bold;font-size:14px;color:#fff;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;max-width:280px;">' +
              '📦 {{ cargoName }}' +
            '</span>' +
            '<span style="font-size:12px;padding:2px 6px;border-radius:3px;font-weight:bold;" ng-style="healthStyle">' +
              '🛡️ {{ health }}%' +
            '</span>' +
          '</div>' +
          '<div layout="row" layout-align="space-between center" style="margin-top:3px;font-size:12px;color:#a0aab8;">' +
            '<span>📍 {{ destName }} ({{ distRemaining }})</span>' +
            '<span style="color:#FFB54A;font-weight:bold;">${{ payout }}</span>' +
          '</div>' +
          '<div ng-show="arrived" style="margin-top:4px;background:#28a745;color:#fff;text-align:center;padding:3px;border-radius:3px;font-weight:bold;font-size:12px;animation:pulse 1.5s infinite;">' +
            '🎯 DESTINATION REACHED — OPEN LOGISTICS (M) TO DELIVER' +
          '</div>' +
        '</div>' +
        '<div ng-show="!active && company && !hidden" style="background:rgba(12,15,20,0.65);border-left:4px solid #6c757d;border-radius:4px;padding:4px 10px;color:#c0c8d4;font-size:12px;">' +
          '<span>🏢 {{ company.name }} &middot; Vault: <strong style="color:#28a745;">${{ company.vault }}</strong> &middot; Rep: {{ company.reputation }}%</span>' +
        '</div>' +
      '</div>',
    replace: true,
    link: function (scope) {
      'use strict'
      scope.active = false
      scope.company = null
      scope.cargoName = ''
      scope.destName = ''
      scope.distRemaining = ''
      scope.payout = ''
      scope.health = 100
      scope.arrived = false
      scope.hidden = false
      scope.healthStyle = { 'background': '#28a745', 'color': '#fff' }

      var hello = function (on) {
        bngApi.engineLua('if beamngEarth_core and beamngEarth_core.hudApp then beamngEarth_core.hudApp("freight", ' + on + ') end')
      }

      scope.$on('BeamNGEarthHud', function (event, data) {
        scope.$evalAsync(function () {
          scope.hidden = !!(data && data.hidden)
          var fr = data && data.freight
          if (!fr) {
            scope.active = false
            return
          }
          scope.company = fr.company
          var c = fr.activeContract
          if (c && c.status === 'in_transit') {
            scope.active = true
            scope.cargoName = (c.cargo && c.cargo.name) || 'Cargo'
            scope.destName = (c.destination && c.destination.name) || 'Destination'

            var dM = c.currentDistanceM || 0
            if (dM > 1000) {
              scope.distRemaining = (dM / 1000).toFixed(1) + ' km'
            } else {
              scope.distRemaining = Math.round(dM) + ' m'
            }

            scope.payout = (c.totalPayout || 0).toLocaleString()
            var h = 100
            if (c.slots && c.slots[0]) {
              h = Math.round(c.slots[0].cargoHealth || 100)
            }
            scope.health = h
            if (h >= 90) {
              scope.healthStyle = { 'background': '#28a745', 'color': '#fff' }
            } else if (h >= 65) {
              scope.healthStyle = { 'background': '#ffc107', 'color': '#000' }
            } else {
              scope.healthStyle = { 'background': '#dc3545', 'color': '#fff' }
            }
            scope.arrived = !!fr.canDeliver
          } else {
            scope.active = false
          }
        })
      })

      hello(true)
      var again = setInterval(function () { hello(true) }, 3000)
      scope.$on('$destroy', function () { clearInterval(again); hello(false) })
    }
  }
}]);
