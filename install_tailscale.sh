curl -fsSL https://tailscale.com/install.sh | sh


# enable https cert
sudo mkdir -p /etc/tailscale/certs
cd /etc/tailscale/certs
sudo tailscale cert $(tailscale status --json | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['Self']['DNSName'].rstrip('.'))")
# Creates: <hostname>.ts.net.crt and <hostname>.ts.net.key

# TODO go back to starting folder
