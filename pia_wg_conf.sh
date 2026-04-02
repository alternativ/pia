#!/bin/sh
set -e

# === Configuration ===
IMAGE_NAME="robbinvdh/pia"
REGION="de berlin"  # Default region (fuzzy name, e.g. "frankfurt", "milano")
OUTPUT_FILE="pia.conf"

# === Parse flags ===
while [ "$#" -gt 0 ]; do
  case "$1" in
    --user)
      USERNAME="${2:?Missing value for --user}"
      shift 2
      ;;
    --pass)
      PASSWORD="${2:?Missing value for --pass}"
      shift 2
      ;;
    --region)
      REGION="${2:?Missing value for --region}"
      shift 2
      ;;
    --out)
      OUTPUT_FILE="${2:?Missing value for --out}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: $0 --user <PIA_USERNAME> --pass <PIA_PASSWORD> [--region <REGION>] [--out <FILE>]"
      exit 1
      ;;
  esac
done

# === Validate required args ===
if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
  echo "Error: --user and --pass are required."
  echo "Usage: $0 --user <PIA_USERNAME> --pass <PIA_PASSWORD> [--region <REGION>] [--out <FILE>]"
  exit 1
fi

# === Generate config via Docker ===
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "[+] Generating WireGuard config for region: $REGION..."
docker run --rm \
  --cap-add NET_ADMIN \
  -e PIA_USER="$USERNAME" \
  -e PIA_PASS="$PASSWORD" \
  -e REGION="$REGION" \
  -v "$TMPDIR:/etc/wireguard" \
  "$IMAGE_NAME" wireguard 2>&1

# === Validate output ===
CONF="$TMPDIR/pia.conf"
if [ ! -f "$CONF" ]; then
  echo "Error: pia.conf was not generated. Check credentials and region."
  exit 1
fi

# === Write final config ===
# Inject DNS after the Address line if not already present
if ! grep -q '^DNS' "$CONF"; then
  sed 's/^Address = .*/&\nDNS = 1.1.1.1/' "$CONF" > "$OUTPUT_FILE"
else
  cp "$CONF" "$OUTPUT_FILE"
fi

SERVER_NAME=$(cat "$TMPDIR/pia-hostname" 2>/dev/null | tr -d '[:space:]')
if [ -n "$SERVER_NAME" ]; then
  echo "[+] Server: $SERVER_NAME"
fi
