#!/bin/bash
# Generates prometheus/web-config.yml from the PROMETHEUS_* settings in .env.
# Run before `docker compose up` (setup.sh does this automatically).
#
# If PROMETHEUS_TLS_ENABLED=true, place the PFX certificate issued by your
# certificate team at prometheus/certs/prometheus.pfx before running this.
# You'll be prompted for the PFX password to extract the PEM cert/key pair
# Prometheus needs; the password itself is never written to disk.
set -euo pipefail

cd "$(dirname "$0")/.."
set -a
source .env
set +a

: "${PROMETHEUS_TLS_ENABLED:=false}"
: "${PROMETHEUS_USER:?PROMETHEUS_USER must be set in .env}"
: "${PROMETHEUS_PASSWORD:?PROMETHEUS_PASSWORD must be set in .env}"

CERT_DIR="prometheus/certs"
PFX_FILE="$CERT_DIR/prometheus.pfx"
CERT_FILE="$CERT_DIR/prometheus.crt"
KEY_FILE="$CERT_DIR/prometheus.key"
mkdir -p "$CERT_DIR"

if [ "${PROMETHEUS_TLS_ENABLED,,}" = "true" ]; then
    if [ -f "$PFX_FILE" ]; then
        # Only re-extract when the PFX is new/updated, so this doesn't prompt on every run.
        if [ "$PFX_FILE" -nt "$CERT_FILE" ] || [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
            read -r -s -p "Enter password for $PFX_FILE: " PFX_PASSWORD
            echo
            openssl pkcs12 -in "$PFX_FILE" -clcerts -nokeys -passin pass:"$PFX_PASSWORD" -out "$CERT_FILE"
            openssl pkcs12 -in "$PFX_FILE" -nocerts -nodes -passin pass:"$PFX_PASSWORD" -out "$KEY_FILE"
            unset PFX_PASSWORD
        fi
    elif [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
        echo "ERROR: PROMETHEUS_TLS_ENABLED=true but neither $PFX_FILE nor $CERT_FILE/$KEY_FILE were found." >&2
        echo "Place the PFX certificate from your certificate team at $PFX_FILE and re-run." >&2
        exit 1
    fi
    # Readable by the container's unprivileged user.
    chmod 644 "$CERT_FILE" "$KEY_FILE"
    SCHEME=https
else
    SCHEME=http
fi

# Consumed by the grafana service (see docker-compose.yml env_file) so the
# datasource can pick the matching scheme via Grafana's $__env{} expansion.
echo "PROMETHEUS_SCHEME=${SCHEME}" > prometheus/generated.env

BCRYPT_HASH=$(docker run --rm httpd:alpine htpasswd -nbB -C 10 "$PROMETHEUS_USER" "$PROMETHEUS_PASSWORD" | cut -d: -f2)

{
    if [ "${PROMETHEUS_TLS_ENABLED,,}" = "true" ]; then
        echo "tls_server_config:"
        echo "  cert_file: /etc/prometheus/certs/prometheus.crt"
        echo "  key_file: /etc/prometheus/certs/prometheus.key"
        echo
    fi
    echo "basic_auth_users:"
    echo "  ${PROMETHEUS_USER}: ${BCRYPT_HASH}"
} > prometheus/web-config.yml

echo "Generated prometheus/web-config.yml (PROMETHEUS_TLS_ENABLED=${PROMETHEUS_TLS_ENABLED})"
