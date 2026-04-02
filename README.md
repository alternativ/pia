## Config generator (robbinvdh/pia)

See all regions

    docker run --rm -it robbinvdh/pia regions

Filter by name

    docker run --rm -it -e REGION=frankfurt robbinvdh/pia regions

Generate WireGuard config for Milano

    docker run --rm -it --cap-add NET_ADMIN \
      -e PIA_USER=your_user \
      -e PIA_PASS=your_pass \
      -e REGION=milano \
      -v $(pwd):/etc/wireguard \
      robbinvdh/pia wireguard

---

## Gateway container (robbinvdh/pia-gateway)

A long-running WireGuard VPN gateway that other containers can share via
`network_mode: "service:gateway"`.  Based on the same pia-foss scripts.

### Quick start

    cp .gateway.env.example .gateway.env
    # edit .gateway.env with your PIA credentials
    docker compose up -d

Any service declared with `network_mode: "service:gateway"` will have all
its traffic routed through the PIA WireGuard tunnel.

### Build the gateway image locally

    docker build -f Dockerfile.gateway -t robbinvdh/pia-gateway .

### Environment variables

| Variable                | Default     | Description                                      |
|-------------------------|-------------|--------------------------------------------------|
| `PIA_USER`              | *(required)*| PIA username                                     |
| `PIA_PASS`              | *(required)*| PIA password                                     |
| `REGION`                | auto        | Fuzzy region name, e.g. `"de berlin"`, `"milan"` |
| `KILLSWITCH`            | `true`      | Drop non-VPN traffic to prevent leaks            |
| `PIA_PF`                | `false`     | Request a forwarded port from PIA                |
| `HEALTH_CHECK_INTERVAL` | `30`        | Seconds between tunnel liveness checks           |

### Required container capabilities

    cap_add: [NET_ADMIN, SYS_MODULE]
    sysctls: [net.ipv4.ip_forward=1]
    devices: [/dev/net/tun]

### Notes

- The WireGuard interface is named `wg0` (kernel interface, not a TUN device).
  WireGuard kernel interfaces are not `/dev/net/tun`-based; the device is only
  needed for `wg-quick` internals on some kernels.
- Port forwarding (`PIA_PF=true`) requires `PIA_TOKEN` and `PF_GATEWAY` to be
  exported by the pia-foss scripts.  These are only available when the pia-foss
  scripts are called with `PIA_CONNECT=true`.  See `gateway-entrypoint.sh` for
  the workaround note.
- The `pia_wg_refresh.sh` script can still be used to rotate credentials and
  update a gluetun-style env file independently of the gateway container.
