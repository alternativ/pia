#!/bin/sh
# Patch get_region.sh to write WG_HOSTNAME to /etc/wireguard/pia-hostname
# after a successful WireGuard config generation.
TARGET=/opt/pia/get_region.sh

awk '
BEGIN { patched = 0 }
{
  if (!patched && index($0, "rm -f /opt/piavpn-manual/latencyList")) {
    print "  echo \"$bestServer_WG_hostname\" > /etc/wireguard/pia-hostname"
    patched = 1
  }
  print
}
' "$TARGET" > /tmp/patched.sh && mv /tmp/patched.sh "$TARGET" && chmod +x "$TARGET"
