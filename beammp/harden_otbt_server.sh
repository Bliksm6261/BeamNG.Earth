#!/usr/bin/env bash
# Lock down OTBT's BeamMP VPS the way OTBT's other servers are (otbt docs: infrastructure/networking.md, the 2026-04-08
# security audit): Tailscale with SSH, SSH reachable over Tailscale only, key-only logins as ehnadmin, UFW deny-by-default,
# fail2ban, automatic security updates. The only public port left is the game's (30814 TCP+UDP).
#
#   sudo TS_AUTHKEY=tskey-auth-... SSH_PUBKEY="ssh-ed25519 AAAA... chad@EHN-Laptop" bash harden_otbt_server.sh
#
# TS_AUTHKEY: a Tailscale auth key (admin console > Settings > Keys). SSH_PUBKEY: the key for ehnadmin's logins (the dev
# machine's ~/.ssh/id_ed25519.pub); optional when root already has authorized_keys (they are copied to ehnadmin).
# Run it from the provider's console or the current SSH session: it closes public SSH only after Tailscale is up, and
# stops before touching the firewall if it is not. Safe to run again.
set -euo pipefail

ADMIN=ehnadmin
HOSTNAME_TS=${HOSTNAME_TS:-otbt-beamng}
GAME_PORT=${GAME_PORT:-30814}

[ "$(id -u)" = 0 ] || { echo "run as root (sudo)"; exit 1; }

echo "== packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl ufw fail2ban unattended-upgrades >/dev/null

echo "== admin user: $ADMIN (key-only, passwordless sudo)"
id "$ADMIN" >/dev/null 2>&1 || adduser --disabled-password --gecos "" "$ADMIN" >/dev/null
usermod -aG sudo "$ADMIN"
echo "$ADMIN ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-$ADMIN
chmod 440 /etc/sudoers.d/90-$ADMIN
install -d -m 700 -o "$ADMIN" -g "$ADMIN" /home/$ADMIN/.ssh
AK=/home/$ADMIN/.ssh/authorized_keys
touch "$AK"
if [ -n "${SSH_PUBKEY:-}" ]; then grep -qxF "$SSH_PUBKEY" "$AK" || echo "$SSH_PUBKEY" >> "$AK"; fi
if [ -s /root/.ssh/authorized_keys ]; then
  while IFS= read -r k; do [ -z "$k" ] || grep -qxF "$k" "$AK" || echo "$k" >> "$AK"; done < /root/.ssh/authorized_keys
fi
chown "$ADMIN:$ADMIN" "$AK"; chmod 600 "$AK"
[ -s "$AK" ] || { echo "no SSH key for $ADMIN: pass SSH_PUBKEY=\"ssh-ed25519 ...\""; exit 1; }

echo "== Tailscale (with Tailscale SSH)"
command -v tailscale >/dev/null || curl -fsSL https://tailscale.com/install.sh | sh
if ! tailscale ip -4 >/dev/null 2>&1; then
  [ -n "${TS_AUTHKEY:-}" ] || { echo "Tailscale is not up: pass TS_AUTHKEY=tskey-auth-..."; exit 1; }
  tailscale up --ssh --authkey="$TS_AUTHKEY" --hostname="$HOSTNAME_TS"
else
  tailscale set --ssh --hostname="$HOSTNAME_TS"
fi
TSIP=$(tailscale ip -4 2>/dev/null | head -1)
[ -n "$TSIP" ] || { echo "Tailscale did not come up; the firewall and SSH were not changed"; exit 1; }
echo "   tailscale: $TSIP ($HOSTNAME_TS)"

echo "== SSH: keys only, no root, no passwords"
cat > /etc/ssh/sshd_config.d/99-hardening.conf <<EOF
PasswordAuthentication no
PermitRootLogin no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
EOF
sshd -t
systemctl reload ssh 2>/dev/null || systemctl reload sshd

echo "== firewall: deny by default; SSH on tailscale0 only; game port $GAME_PORT public"
ufw --force reset >/dev/null
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw allow in on tailscale0 >/dev/null
ufw allow in on tailscale0 to any port 22 proto tcp >/dev/null
ufw allow "$GAME_PORT"/tcp >/dev/null
ufw allow "$GAME_PORT"/udp >/dev/null
ufw --force enable >/dev/null
ufw status verbose

echo "== fail2ban (sshd jail) and automatic security updates"
systemctl enable -q --now fail2ban
dpkg-reconfigure -f noninteractive unattended-upgrades >/dev/null
systemctl enable -q --now unattended-upgrades

echo
echo "Done. SSH now only over Tailscale:  ssh $ADMIN@$TSIP   (or: ssh $ADMIN@$HOSTNAME_TS)"
echo "Public: only $GAME_PORT TCP+UDP (the game). Check from your laptop before closing this session."
