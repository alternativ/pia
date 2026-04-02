#!/usr/bin/env bash
set -e

# Resolve a friendly region name (e.g. "frankfurt", "milano") to a PIA region ID.
# Sets PREFERRED_REGION if REGION is provided.
resolve_region() {
  if [ -n "$REGION" ]; then
    server_list=$(curl -s 'https://serverlist.piaservers.net/vpninfo/servers/v6' | head -1)
    PREFERRED_REGION=$(echo "$server_list" | jq -r --arg q "$REGION" \
      '.regions[] | select(.name | ascii_downcase | contains($q | ascii_downcase)) | .id' | head -1)
    if [ -z "$PREFERRED_REGION" ]; then
      echo "No region found matching: $REGION"
      exit 1
    fi
    export PREFERRED_REGION
  fi
}

case "$1" in
  regions)
    unset PIA_USER PIA_PASS PIA_TOKEN
    resolve_region
    exec bash /opt/pia/get_region.sh
    ;;
  wireguard)
    export VPN_PROTOCOL=wireguard
    resolve_region
    exec bash /opt/pia/get_region.sh
    ;;
  *)
    echo "Usage: docker run pia-wg [regions|wireguard]"
    echo ""
    echo "  regions   - List available regions sorted by latency"
    echo "  wireguard - Generate WireGuard config (requires PIA_USER + PIA_PASS)"
    echo ""
    echo "Options (env vars):"
    echo "  REGION=<name>  Fuzzy region name, e.g. REGION=frankfurt or REGION=milano"
    exit 1
    ;;
esac
