# Stage C validation

LuaJIT: 69 test files, 6429 passed, 0 failed; 0 nonzero exits.

| Test file | Passed | Failed | Exit |
| --- | ---: | ---: | ---: |
| test_african_weather.lua | 41 | 0 | 0 |
| test_autojoin.lua | 21 | 0 | 0 |
| test_banner.lua | 50 | 0 | 0 |
| test_beammp.lua | 28 | 0 | 0 |
| test_beammp_economy_client.lua | 823 | 0 | 0 |
| test_beammp_ledger.lua | 82 | 0 | 0 |
| test_beammp_plugin.lua | 26 | 0 | 0 |
| test_benchmark.lua | 50 | 0 | 0 |
| test_bushcamp.lua | 18 | 0 | 0 |
| test_camshift.lua | 72 | 0 | 0 |
| test_checkpoints.lua | 101 | 0 | 0 |
| test_collisionfoci.lua | 14 | 0 | 0 |
| test_convoy.lua | 59 | 0 | 0 |
| test_core_robustness.lua | 61 | 0 | 0 |
| test_core_stubbed.lua | 270 | 0 | 0 |
| test_corridor_traffic.lua | 41 | 0 | 0 |
| test_credits.lua | 69 | 0 | 0 |
| test_crossover.lua | 931 | 0 | 0 |
| test_detail_mode.lua | 25 | 0 | 0 |
| test_dev.lua | 69 | 0 | 0 |
| test_drive_driver.lua | 428 | 0 | 0 |
| test_drophold.lua | 35 | 0 | 0 |
| test_edgeguard.lua | 33 | 0 | 0 |
| test_expeditions.lua | 53 | 0 | 0 |
| test_farcars.lua | 29 | 0 | 0 |
| test_farfield.lua | 175 | 0 | 0 |
| test_farfield_spares.lua | 23 | 0 | 0 |
| test_follow.lua | 114 | 0 | 0 |
| test_framing.lua | 16 | 0 | 0 |
| test_freight.lua | 80 | 0 | 0 |
| test_geodesy.lua | 489 | 0 | 0 |
| test_governor.lua | 452 | 0 | 0 |
| test_gps.lua | 44 | 0 | 0 |
| test_horizon.lua | 29 | 0 | 0 |
| test_hudapps.lua | 29 | 0 | 0 |
| test_imagery.lua | 73 | 0 | 0 |
| test_issuefmt.lua | 40 | 0 | 0 |
| test_keybinds.lua | 3 | 0 | 0 |
| test_lattice.lua | 51 | 0 | 0 |
| test_loadprogress.lua | 14 | 0 | 0 |
| test_m4_probes.lua | 36 | 0 | 0 |
| test_mpanchor.lua | 12 | 0 | 0 |
| test_mpsession.lua | 44 | 0 | 0 |
| test_navgraph.lua | 36 | 0 | 0 |
| test_parking.lua | 20 | 0 | 0 |
| test_perflog.lua | 11 | 0 | 0 |
| test_perfmon.lua | 7 | 0 | 0 |
| test_places.lua | 157 | 0 | 0 |
| test_postfx.lua | 3 | 0 | 0 |
| test_rebase.lua | 33 | 0 | 0 |
| test_recouple.lua | 10 | 0 | 0 |
| test_recovery.lua | 15 | 0 | 0 |
| test_region.lua | 55 | 0 | 0 |
| test_report.lua | 17 | 0 | 0 |
| test_retex.lua | 77 | 0 | 0 |
| test_roads.lua | 81 | 0 | 0 |
| test_satmat_layer.lua | 10 | 0 | 0 |
| test_scoping.lua | 2 | 0 | 0 |
| test_sea.lua | 39 | 0 | 0 |
| test_seasonlook.lua | 9 | 0 | 0 |
| test_settings.lua | 150 | 0 | 0 |
| test_simhold.lua | 4 | 0 | 0 |
| test_sky.lua | 102 | 0 | 0 |
| test_statusbar.lua | 19 | 0 | 0 |
| test_surface_layers.lua | 52 | 0 | 0 |
| test_terrain_swap.lua | 29 | 0 | 0 |
| test_terrainpatch.lua | 14 | 0 | 0 |
| test_trees.lua | 50 | 0 | 0 |
| test_weather.lua | 274 | 0 | 0 |

## Syntax checks

`luajit -bl` compiled all 11 changed Lua files without execution:

- `beammp/Server/BeamNGEarth/main.lua`: PASS
- `beammp/Server/BeamNGEarth/otbt_economy.lua`: PASS
- `beammp/Server/BeamNGEarth/otbt_json.lua`: PASS
- `beammp/Server/BeamNGEarth/otbt_ledger.lua`: PASS
- `mod/beamng_earth/lua/ge/extensions/beamngEarth/checkpoints.lua`: PASS
- `mod/beamng_earth/lua/ge/extensions/beamngEarth/expeditions.lua`: PASS
- `mod/beamng_earth/lua/ge/extensions/beamngEarth/freight.lua`: PASS
- `mod/beamng_earth/lua/ge/extensions/beamngEarth/mpsession.lua`: PASS
- `mod/tests/test_beammp_economy_client.lua`: PASS
- `mod/tests/test_beammp_ledger.lua`: PASS
- `mod/tests/test_beammp_plugin.lua`: PASS

No lua5.3, lua, or luac executable was available on PATH or in the Homebrew installation; Lua 5.3 execution was unavailable.

The keybind suite checked the mod map only because BEAMNG_DIR is unset.
