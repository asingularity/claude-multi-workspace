#!/bin/bash
# One-time host setup: install Tailscale, join the tailnet, generate the HTTPS
# cert that code-server serves, and install a weekly cron job that renews it.
# Safe to re-run. Requires MagicDNS + HTTPS certificates to be enabled in the
# tailnet's DNS settings (https://login.tailscale.com/admin/dns).
set -e
cd "$(dirname "$0")"

curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# Writes /etc/tailscale/certs/<hostname>.ts.net.{crt,key} (auto-detected by the
# container at startup) and /etc/cron.d/tailscale-cert-renew.
./renew_cert.sh --install-cron
