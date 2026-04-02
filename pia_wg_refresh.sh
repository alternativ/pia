#!/bin/sh
set -e

# === Configuration ===
IMAGE_NAME="robbinvdh/pia"
ENV_FILE="/opt/docker/services_private/.gluetun.env"
REGION="de berlin"  # Default region (fuzzy name, e.g. "frankfurt", "milano")

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
    *)
      echo "Unknown argument: $1"
      echo "Usage: $0 --user <PIA_USERNAME> --pass <PIA_PASSWORD> [--region <REGION>]"
      exit 1
      ;;
  esac
done

# === Validate required args ===
if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
  echo "Error: --user and --pass are required."
  echo "Usage: $0 --user <PIA_USERNAME> --pass <PIA_PASSWORD> [--region <REGION>]"
  exit 1
fi

# === Run container, capture output and config ===
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "[+] Generating WireGuard config for region: $REGION..."
LOGFILE="$TMPDIR/output.log"
docker run --rm \
  --cap-add NET_ADMIN \
  -e PIA_USER="$USERNAME" \
  -e PIA_PASS="$PASSWORD" \
  -e REGION="$REGION" \
  -v "$TMPDIR:/etc/wireguard" \
  "$IMAGE_NAME" wireguard 2>&1 | tee "$LOGFILE"
OUTPUT=$(cat "$LOGFILE")

# === Parse pia.conf ===
CONF="$TMPDIR/pia.conf"
if [ ! -f "$CONF" ]; then
  echo "Error: pia.conf was not generated. Check credentials and region."
  exit 1
fi

PRIVATE_KEY=$(grep '^PrivateKey' "$CONF" | awk '{print $3}')
ADDRESS=$(grep '^Address'    "$CONF" | awk '{print $3}')
PUBLIC_KEY=$(grep '^PublicKey'  "$CONF" | awk '{print $3}')
ENDPOINT=$(grep '^Endpoint'   "$CONF" | awk '{print $3}')
ENDPOINT_IP=$(echo "$ENDPOINT" | cut -d: -f1)
ENDPOINT_PORT=$(echo "$ENDPOINT" | cut -d: -f2)

# SERVER_NAMES comes from the hostname file written by the patched get_region.sh
SERVER_NAME=$(cat "$TMPDIR/pia-hostname" 2>/dev/null | tr -d '[:space:]')

# === Helper: update or append key in env file ===
set_env_value() {
  local file=$1 key=$2 value=$3
  if grep -q "^$key=" "$file"; then
    sed -i "s|^$key=.*|$key=$value|" "$file"
  else
    echo "$key=$value" >> "$file"
  fi
}

# === Update env file ===
set_env_value "$ENV_FILE" "SERVER_NAMES"           "$SERVER_NAME"
set_env_value "$ENV_FILE" "WIREGUARD_PRIVATE_KEY"  "$PRIVATE_KEY"
set_env_value "$ENV_FILE" "WIREGUARD_PUBLIC_KEY"   "$PUBLIC_KEY"
set_env_value "$ENV_FILE" "WIREGUARD_ADDRESSES"    "$ADDRESS"
set_env_value "$ENV_FILE" "WIREGUARD_ENDPOINT_IP"  "$ENDPOINT_IP"
set_env_value "$ENV_FILE" "WIREGUARD_ENDPOINT_PORT" "$ENDPOINT_PORT"

echo "[+] Updated WireGuard values in $ENV_FILE"
echo "[+] Done."
