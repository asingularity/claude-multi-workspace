#!/bin/bash
# Renew (or create) the Tailscale HTTPS certificate that code-server serves.
#
# Tailscale issues 90-day Let's Encrypt certs and does NOT renew file-based
# certs by itself: something has to re-run `tailscale cert`. This script is safe
# to run at any time. tailscaled only talks to Let's Encrypt when the cached
# cert has less than MIN_VALIDITY left; otherwise it just rewrites the files.
# The running container notices the changed files and restarts code-server
# (see entrypoint.sh); tmux sessions survive that.
#
# Usage:
#   ./renew_cert.sh                 # renew if needed (start_docker.sh does this)
#   ./renew_cert.sh --install-cron  # also install a weekly root cron job
set -euo pipefail

CERT_DIR="${CERT_DIR:-/etc/tailscale/certs}"
MIN_VALIDITY="${MIN_VALIDITY:-336h}"   # renew when fewer than 14 days remain

DOMAIN=$(tailscale status --json 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['Self']['DNSName'].rstrip('.'))" 2>/dev/null || true)
if [ -z "$DOMAIN" ]; then
    echo "renew_cert: cannot determine this node's Tailscale DNS name (is tailscale up?)" >&2
    exit 1
fi

# The container uses the first *.crt it finds in CERT_DIR. Point out certs for
# other names (typically: the host is on a different Tailscale profile now).
for other in "$CERT_DIR"/*.crt; do
    [ -e "$other" ] || continue
    [ "$(basename "$other")" = "$DOMAIN.crt" ] || \
        echo "renew_cert: note: $other is for a different name than the active Tailscale node ($DOMAIN)" >&2
done

sudo mkdir -p "$CERT_DIR"
sudo tailscale cert --min-validity "$MIN_VALIDITY" \
    --cert-file "$CERT_DIR/$DOMAIN.crt" --key-file "$CERT_DIR/$DOMAIN.key" "$DOMAIN"
sudo chmod 644 "$CERT_DIR/$DOMAIN.crt"
sudo chmod 600 "$CERT_DIR/$DOMAIN.key"
echo "renew_cert: $DOMAIN $(openssl x509 -in "$CERT_DIR/$DOMAIN.crt" -noout -enddate)"

if [ "${1:-}" = "--install-cron" ]; then
    CRON_FILE=/etc/cron.d/tailscale-cert-renew
    sudo tee "$CRON_FILE" >/dev/null <<CRON
# Installed by EEVIAC/renew_cert.sh --install-cron: renew the Tailscale HTTPS cert weekly.
# The EEVIAC container restarts code-server by itself when these files change.
17 4 * * 1 root tailscale cert --min-validity $MIN_VALIDITY --cert-file $CERT_DIR/$DOMAIN.crt --key-file $CERT_DIR/$DOMAIN.key $DOMAIN
CRON
    sudo chmod 644 "$CRON_FILE"
    echo "renew_cert: installed $CRON_FILE"
fi
