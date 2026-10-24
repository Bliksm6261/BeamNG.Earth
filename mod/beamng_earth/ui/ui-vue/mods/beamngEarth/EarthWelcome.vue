<template>
  <!-- A one-time welcome (the user, 2026-10-15: "add a 1 time popup with info about this project"): what it is,
       the companion server, the keys, credits. Shown once per WELCOME_VERSION by settings.lua; again from the
       settings page's "Show welcome". -->
  <div class="earth-welcome" @keydown.esc.stop="done" tabindex="-1" ref="rootEl">
    <div class="card">
      <div class="head">
        <!-- the Off the Beaten Track logo (branding/otbt_logo_white.png at 160 px, inline: no file path to resolve) -->
        <img class="logo" alt="Off the Beaten Track" src="data:image/png;base64,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"/>
        <div>
          <div class="title">Welcome to Off the Beaten Track</div>
          <div class="sub">Overland Southern Africa, the real roads and tracks. <span class="brand">offthebeatentrack.world</span></div>
        </div>
      </div>

      <div class="server" :class="{ ok: connected, bad: connected === false }">
        <span class="dot"></span>
        <span v-if="connected">World server connected: the world is building around you.</span>
        <span v-else-if="connected === false">World server not running. Start the <b>Off the Beaten Track</b> app,
          then come back.</span>
        <span v-else>Checking the world server…</span>
      </div>

      <div class="cols">
        <div class="col">
          <div class="h">How it works</div>
          <p>The Off the Beaten Track app on your PC builds Southern Africa as you drive: real terrain, roads, gravel
            tracks, towns, trees, water and aerial photos, from open map data. Keep it running while you play.</p>
          <p>Ten countries: South Africa, Namibia, Botswana, Zimbabwe, Zambia, Mozambique, Lesotho, Eswatini, Malawi
            and Tanzania. Start from a major South African city or one of the overland spots.</p>
          <p>A place you visit for the first time takes a few seconds to appear; after that it comes from the cache.</p>
          <div class="h">Getting around</div>
          <ul>
            <li><b>M</b>: the world map. Search an address, right-click to teleport, left-click to set a GPS route.</li>
            <li><b>Autodrive</b> on the GPS bar: the car drives the route by itself.</li>
            <li><b>Places</b> on the map: save spots and jump back to them.</li>
          </ul>
        </div>
        <div class="col">
          <div class="h">Help make it better</div>
          <ul>
            <li><b>Ctrl+Shift+E</b>: report a problem here (a screenshot, the place and your frame rate are saved as a
              ready-to-post issue).</li>
            <li><b>Ctrl+Shift+Y</b>: record a 30-second performance profile.</li>
          </ul>
          <div class="h">Settings</div>
          <p>Pause menu → Mods → <b>BeamNG.Earth</b> (the engine under this edition): view distance, weather and sky, grass, the download cache.</p>
          <div class="h">Data</div>
          <p class="small">Imagery, elevation and map data from open sources: USGS, USDA NAIP, state and national
            mapping agencies, EOX Sentinel-2 cloudless, Overture Maps / OpenStreetMap contributors, Mapterhorn.
            The sources in use are credited on screen while you drive.</p>
          <p class="small">Built on BeamNG.Earth (MIT). Multiplayer by BeamMP.</p>
          <p class="small preview">A beta: expect some rough edges. Thanks for trying it!</p>
        </div>
      </div>

      <div class="btns">
        <button class="btn" @click="openMap">Open the map</button>
        <button class="btn primary" @click="done">Start driving</button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted, nextTick } from "vue"

const rootEl = ref(null)
const connected = ref(null)
let timer = null

function engineLua(script, cb) {
  if (window.bngApi && window.bngApi.engineLua) window.bngApi.engineLua(script, cb)
}
function poll() {
  engineLua("beamngEarth_settings and beamngEarth_settings.uiMapState and beamngEarth_settings.uiMapState() or nil", s => {
    connected.value = s ? !!s.connected : false
  })
}
// marks the welcome seen and goes back to driving (or to the map)
function finish(state) {
  engineLua(`if beamngEarth_settings and beamngEarth_settings.uiWelcomeDone then beamngEarth_settings.uiWelcomeDone() end; ` +
            `if beamngEarth_settings and beamngEarth_settings.navigate then beamngEarth_settings.navigate('${state}') ` +
            `else guihooks.trigger('ChangeState', {state = '${state}'}) end`)
}
function done() { finish("play") }
function openMap() { finish("beamngEarthMap") }

onMounted(() => {
  poll()
  timer = setInterval(poll, 1000)
  nextTick(() => rootEl.value && rootEl.value.focus())
})
onUnmounted(() => clearInterval(timer))
</script>

<style scoped>
.earth-welcome {
  position: absolute; inset: 0; display: flex; align-items: center; justify-content: center;
  background: rgba(8, 10, 14, 0.62); outline: none; font-family: inherit; color: #e8edf2;
}
.card {
  width: min(980px, 92vw); max-height: 88vh; overflow-y: auto; padding: 26px 30px 22px;
  background: rgba(18, 22, 28, 0.96); border: 1px solid rgba(255, 255, 255, 0.14); border-radius: 10px;
  box-shadow: 0 18px 60px rgba(0, 0, 0, 0.55);
}
.head { display: flex; gap: 16px; align-items: center; margin-bottom: 16px; }
.logo { height: 80px; width: auto; flex: none; }
.title { font-size: 28px; font-weight: 700; letter-spacing: 0.01em; }
.sub { font-size: 15px; color: #9fb0c0; margin-top: 2px; }
.server {
  display: flex; gap: 10px; align-items: center; padding: 9px 12px; margin-bottom: 18px; font-size: 14px;
  border-radius: 6px; background: rgba(255, 255, 255, 0.05);
}
.server .dot { width: 10px; height: 10px; border-radius: 50%; background: #8a949e; flex: none; }
.server.ok .dot { background: #4cc46a; }
.server.bad { background: rgba(224, 118, 28, 0.14); }
.server.bad .dot { background: #e0761c; }
.cols { display: flex; gap: 28px; }
.col { flex: 1; min-width: 0; }
.h { margin: 14px 0 6px; font-size: 12px; text-transform: uppercase; letter-spacing: 0.06em; color: #9fb0c0; }
.h:first-child { margin-top: 0; }
p { margin: 0 0 8px; font-size: 14px; line-height: 1.45; }
ul { margin: 0 0 8px; padding-left: 18px; font-size: 14px; line-height: 1.45; }
li { margin-bottom: 4px; }
.small { font-size: 12px; color: #aab6c2; }
.preview { color: #ffc070; }
.btns { display: flex; justify-content: flex-end; gap: 10px; margin-top: 18px; }
.btn {
  padding: 9px 18px; font-size: 14px; color: #fff; background: rgba(255, 255, 255, 0.08);
  border: 1px solid rgba(255, 255, 255, 0.22); border-radius: 5px; cursor: pointer;
}
.btn:hover { background: rgba(255, 255, 255, 0.16); }
.btn.primary { background: #FF9500; border-color: #FF9500; color: #1c1c1c; }
.btn.primary:hover { background: #ffab3d; }
.brand { color: #FF9500; }
@media (max-width: 760px) { .cols { flex-direction: column; gap: 4px; } }
</style>
