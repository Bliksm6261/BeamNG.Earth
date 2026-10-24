#!/usr/bin/env bash
# The Off the Beaten Track BeamMP server on a fresh Ubuntu VPS (OTBT's: beamng.offthebeatentrack.world), in one go:
#
#   sudo bash setup_otbt_server.sh      (asks for the AuthKey from https://keymaster.beammp.com the first time)
#
# What it does (again on a re-run: it updates the server and the edition, and keeps ServerConfig.toml):
#   1. installs what BeamMP's server needs (apt), and git + python3 to build the edition's files
#   2. gets BeamMP's latest Linux server build from its GitHub releases into /opt/beammp
#   3. builds the edition's server files from the fork (tools/package.py --beammp) and unzips them over the server:
#      Resources/Client/beamng_earth.zip (sent to every player) and Resources/Server/BeamNGEarth (the plugin)
#   4. writes ServerConfig.toml (first run only): the edition's map, port 30814, name, AUTHKEY
#   5. opens port 30814 TCP and UDP (ufw, when it is on) and runs the server as a systemd service, "beammp"
#
# Settings (environment): AUTHKEY (needed the first time), BRANCH (the fork's branch, default main), PORT (30814),
# PRIVATE (true: not in BeamMP's public server list; default true), MAXPLAYERS (default 10).
# Logs: journalctl -u beammp -f   Restart: systemctl restart beammp
set -euo pipefail

REPO=https://github.com/Bliksm6261/BeamNG.Earth.git
BRANCH=${BRANCH:-main}
PORT=${PORT:-30814}
PRIVATE=${PRIVATE:-true}
MAXPLAYERS=${MAXPLAYERS:-10}
DIR=/opt/beammp
SRC=/opt/beammp-src
USER_NAME=beammp

[ "$(id -u)" = 0 ] || { echo "run as root (sudo)"; exit 1; }

echo "== packages"
apt-get update -qq
apt-get install -y -qq curl ca-certificates git python3 unzip liblua5.3-0 libssl3 >/dev/null || \
  apt-get install -y -qq curl ca-certificates git python3 unzip liblua5.3-0 >/dev/null

id "$USER_NAME" >/dev/null 2>&1 || useradd --system --home "$DIR" --shell /usr/sbin/nologin "$USER_NAME"
mkdir -p "$DIR"

echo "== BeamMP server (latest release)"
# the build for this machine (BeamMP names them like BeamMP-Server.ubuntu.24.04.x86_64 / .arm64): its processor, and
# the newest build of this distribution not newer than its version (else the newest one)
ARCH=$(uname -m); case "$ARCH" in aarch64|arm64) ARCH=arm64 ;; x86_64|amd64) ARCH=x86_64 ;; esac
. /etc/os-release
URL=$(curl -fsSL https://api.github.com/repos/BeamMP/BeamMP-Server/releases/latest | \
  OS_ID="$ID" OS_VER="$VERSION_ID" ARCH="$ARCH" python3 -c '
import json, os, re, sys
ver = lambda t: tuple(int(x) for x in t.split(".") if x.isdigit())
mine, arch, os_id = ver(os.environ["OS_VER"]), os.environ["ARCH"], os.environ["OS_ID"].lower()
best = None
for a in json.load(sys.stdin)["assets"]:
    m = re.fullmatch(r"BeamMP-Server[.-](ubuntu|debian)[.-]([\d.]+)[.-](x86_64|arm64|aarch64)", a["name"], re.I)
    if not m or m[3].lower().replace("aarch64", "arm64") != arch:
        continue
    v = ver(m[2])
    key = (m[1].lower() == os_id, m[1].lower() == os_id and v <= mine, v)
    if best is None or key > best[0]:
        best = (key, a["browser_download_url"])
print(best[1] if best else "")')
[ -n "$URL" ] || { echo "no BeamMP server build for $ID $VERSION_ID $ARCH (github.com/BeamMP/BeamMP-Server/releases)"; exit 1; }
echo "   $URL"
curl -fsSL "$URL" -o "$DIR/BeamMP-Server.new"
chmod +x "$DIR/BeamMP-Server.new"
mv -f "$DIR/BeamMP-Server.new" "$DIR/BeamMP-Server"

echo "== the edition's server files ($BRANCH)"
if [ -d "$SRC/.git" ]; then
  # FETCH_HEAD: the first clone may be a single-branch clone of another BRANCH (no origin/<BRANCH> then)
  git -C "$SRC" fetch -q --depth 1 origin "$BRANCH" && git -C "$SRC" checkout -q -f -B "$BRANCH" FETCH_HEAD
else
  git clone -q --depth 1 --branch "$BRANCH" "$REPO" "$SRC"
fi
rm -rf "$SRC/dist"
(cd "$SRC" && python3 tools/package.py --beammp --out dist >/dev/null)
ZIP=$(ls "$SRC"/dist/*BeamMP-Server*.zip | head -1)
echo "   $ZIP"
unzip -o -q "$ZIP" -d "$DIR"

if [ ! -f "$DIR/ServerConfig.toml" ]; then
  # asked here when not given: typed at this prompt it stays out of the process list (sudo AUTHKEY=... shows in ps)
  if [ -z "${AUTHKEY:-}" ] && [ -t 0 ]; then read -rsp "BeamMP AuthKey (https://keymaster.beammp.com): " AUTHKEY; echo; fi
  [ -n "${AUTHKEY:-}" ] || { echo "AUTHKEY is needed the first time (https://keymaster.beammp.com)"; exit 1; }
  echo "== ServerConfig.toml"
  cat > "$DIR/ServerConfig.toml" <<EOF
[General]
Name = "Off the Beaten Track: Southern Africa"
Description = "Overland Southern Africa. Join with the Off the Beaten Track app: offthebeatentrack.world"
Tags = "Freeroam,Offroad"
Map = "/levels/beamng_earth/info.json"
Port = $PORT
MaxCars = 2
MaxPlayers = $MAXPLAYERS
Private = $PRIVATE
Debug = false
LogChat = true
ResourceFolder = "Resources"
AuthKey = "$AUTHKEY"
EOF
  chmod 600 "$DIR/ServerConfig.toml"
else
  echo "== ServerConfig.toml kept (delete it to write a new one)"
fi
chown -R "$USER_NAME:$USER_NAME" "$DIR"

if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
  echo "== firewall: $PORT tcp+udp"
  ufw allow "$PORT"/tcp >/dev/null
  ufw allow "$PORT"/udp >/dev/null
fi

echo "== service"
cat > /etc/systemd/system/beammp.service <<EOF
[Unit]
Description=BeamMP server (Off the Beaten Track)
After=network-online.target
Wants=network-online.target

[Service]
User=$USER_NAME
WorkingDirectory=$DIR
ExecStart=$DIR/BeamMP-Server
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable -q beammp
systemctl restart beammp
sleep 5
systemctl --no-pager --lines=15 status beammp || true
echo
echo "Done. Players join beamng.offthebeatentrack.world:$PORT (the app does it by itself)."
echo "Check the log for '[BeamNG.Earth] plugin loaded':  journalctl -u beammp -f"
