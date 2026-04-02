#!/usr/bin/env bash
set -euo pipefail

# ================================================================
# PIA WireGuard Gateway
# Long-running VPN gateway container, sharable via network_mode.
#
# Required env vars:
#   PIA_USER, PIA_PASS
#
# Optional env vars:
#   REGION                Fuzzy region name (e.g. "frankfurt", "de berlin")
#   KILLSWITCH            Block non-VPN traffic; default true
#   PIA_PF                Request a forwarded port from PIA; default false
#   HEALTH_CHECK_INTERVAL Seconds between tunnel liveness checks; default 30
# ================================================================

: "${PIA_USER:?PIA_USER is required}"
: "${PIA_PASS:?PIA_PASS is required}"

WG_IF=wg0
WG_CONF="/etc/wireguard/${WG_IF}.conf"
PIA_CONF="/etc/wireguard/pia.conf"
PIA_HOSTNAME_FILE="/etc/wireguard/pia-hostname"

log() { echo "[gateway] $*"; }
die() { log "ERROR: $*"; exit 1; }

# ----------------------------------------------------------------
# Resolve fuzzy region name → PREFERRED_REGION
# ----------------------------------------------------------------
resolve_region() {
  [ -z "${REGION:-}" ] && return

  log "Resolving region: $REGION"
  local server_list
  server_list=$(curl -sf 'https://serverlist.piaservers.net/vpninfo/servers/v6' | head -1)
  PREFERRED_REGION=$(echo "$server_list" | jq -r --arg q "$REGION" \
    '.regions[] | select(.name | ascii_downcase | contains($q | ascii_downcase)) | .id' | head -1)
  [ -n "$PREFERRED_REGION" ] || die "No region found matching: $REGION"
  export PREFERRED_REGION
  log "Region resolved to: $PREFERRED_REGION"
}

# ----------------------------------------------------------------
# Use pia-foss scripts to register a WireGuard key and write
# /etc/wireguard/pia.conf  (does NOT bring up the interface)
# ----------------------------------------------------------------
generate_config() {
  log "Fetching WireGuard config from PIA..."
  export VPN_PROTOCOL=wireguard
  export PIA_CONNECT=false   # generate config only; we bring up the tunnel ourselves
  export PIA_PF              # forwarded to pia-foss for server selection hint

  bash /opt/pia/get_region.sh

  [ -f "$PIA_CONF" ] || die "pia.conf not generated — check credentials and region"

  # Rename to our interface name so wg-quick names the interface correctly
  mv "$PIA_CONF" "$WG_CONF"
  log "Config written to $WG_CONF"
}

# ----------------------------------------------------------------
# Bring up the WireGuard tunnel
# ----------------------------------------------------------------
start_tunnel() {
  log "Bringing up $WG_IF..."

  # wg-quick tries to set net.ipv4.ip_forward via sysctl; pre-set it to
  # avoid failure in containers where sysctl writes may be restricted.
  echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null || true

  wg-quick up "$WG_IF" || die "wg-quick up $WG_IF failed"
  log "$WG_IF is up."
}

# ----------------------------------------------------------------
# Killswitch: drop all traffic that is not over the VPN tunnel.
# Applied AFTER the tunnel is up so the WireGuard handshake can
# complete first.  Only the VPN endpoint is whitelisted on eth0.
# ----------------------------------------------------------------
setup_killswitch() {
  [ "${KILLSWITCH}" = "true" ] || return

  log "Applying killswitch rules..."

  local endpoint_ip
  endpoint_ip=$(grep -m1 '^Endpoint' "$WG_CONF" | awk '{print $3}' | cut -d: -f1)

  # ---- INPUT chain ----
  iptables -A INPUT -i lo -j ACCEPT
  iptables -A INPUT -i "$WG_IF" -j ACCEPT
  iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  [ -n "$endpoint_ip" ] && iptables -A INPUT -s "$endpoint_ip" -j ACCEPT
  iptables -A INPUT -j DROP

  # ---- OUTPUT chain ----
  iptables -A OUTPUT -o lo -j ACCEPT
  iptables -A OUTPUT -o "$WG_IF" -j ACCEPT
  iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  [ -n "$endpoint_ip" ] && iptables -A OUTPUT -d "$endpoint_ip" -j ACCEPT
  iptables -A OUTPUT -j DROP

  # ---- FORWARD chain (for containers sharing this namespace) ----
  iptables -A FORWARD -i "$WG_IF" -j ACCEPT
  iptables -A FORWARD -o "$WG_IF" -j ACCEPT
  iptables -A FORWARD -j DROP

  log "Killswitch active. Endpoint whitelist: ${endpoint_ip:-<none>}"
}

# ----------------------------------------------------------------
# Port forwarding renewal loop (runs in background).
# Requires PIA_TOKEN and PF_GATEWAY exported by pia-foss scripts.
# ----------------------------------------------------------------
start_port_forwarding() {
  [ "${PIA_PF}" = "true" ] || return

  if [ -z "${PIA_TOKEN:-}" ] || [ -z "${PF_GATEWAY:-}" ]; then
    log "WARNING: PIA_TOKEN or PF_GATEWAY not set; skipping port forwarding."
    log "         Set PIA_CONNECT=true to let pia-foss export these variables."
    return
  fi

  log "Starting port forwarding renewal (PF_GATEWAY=$PF_GATEWAY)..."
  bash /opt/pia/port_forwarding.sh &
  PF_PID=$!
  log "Port forwarding loop running (PID $PF_PID)"
}

# ----------------------------------------------------------------
# Health monitor: if the tunnel interface disappears, attempt a
# full reconnect (regenerate config and re-raise the interface).
# ----------------------------------------------------------------
monitor_tunnel() {
  local interval="${HEALTH_CHECK_INTERVAL:-30}"
  log "Health monitor started (interval: ${interval}s)"

  while true; do
    sleep "$interval"

    if ! ip link show "$WG_IF" &>/dev/null; then
      log "Tunnel interface $WG_IF is gone — attempting reconnect..."
      wg-quick down "$WG_IF" 2>/dev/null || true
      generate_config
      start_tunnel
      log "Reconnected."
    fi
  done
}

# ----------------------------------------------------------------
# Graceful shutdown
# ----------------------------------------------------------------
cleanup() {
  log "Shutting down..."
  wg-quick down "$WG_IF" 2>/dev/null || true
  iptables -F          2>/dev/null || true
  iptables -t nat -F   2>/dev/null || true
}
trap cleanup EXIT TERM INT

# ================================================================
# Main
# ================================================================
log "PIA WireGuard Gateway starting..."
log "  Interface : $WG_IF"
log "  Killswitch: $KILLSWITCH"
log "  PF        : $PIA_PF"
log "  Region    : ${REGION:-<auto>}"

resolve_region
generate_config
start_tunnel
setup_killswitch
start_port_forwarding

log "Gateway ready. Other containers can use:"
log "  network_mode: \"container:<this-container-name>\""

monitor_tunnel
