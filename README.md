# Remote Dev Container — Phone-Friendly Claude Code Workspace

## What this gives you

- **VS Code in your phone's browser** via code-server (with autocorrect, spell check, image preview)
- **Claude Code** in the integrated terminal with full permissions
- **GPU access** for your Blue Gamma / PyTorch work
- **Tailscale** (optional) so you can reach it from anywhere without port forwarding

## Quick start

```bash
# 1. Clone / copy this folder to your workstation

# 2. Set your secrets
export CODE_SERVER_PASSWORD="something-secure"

# 3. Build and run; or just run
docker compose up -d --build
docker compose up -d 

# 4. Open in browser (local network)
#    http://your-workstation-ip:8080

# 5. Logs if needed on server
docker compose logs -f

# 6. shut down docker if needed
docker compose down
```

## Phone access with Tailscale

If you only access from your local network, the above is sufficient. For access from
anywhere (coffee shop, on the go):

1. Install Tailscale on your workstation and phone
2. **Option A — Host-level Tailscale (simpler):**
   Just install Tailscale on the workstation directly. The container's port 8080 is
   already forwarded to the host, so `http://workstation-tailscale-ip:8080` works.

3. **Option B — Sidecar container (no host install needed):**
   Uncomment the `tailscale` service in `docker-compose.yml`, set `TS_AUTHKEY`,
   and `docker compose up -d`. Access at `http://claude-workspace:8080`.

## Remote access from a laptop

For accessing from a different machine on your network or over the internet:

**Local network:**
Open `http://<workstation-ip>:8080` in any browser. Find your workstation's IP with `hostname -I` or `ip addr`.

**Over the internet (via Tailscale):**
1. Install Tailscale on both your workstation and laptop
2. On the workstation, run `tailscale ip` to get its Tailscale IP (e.g. `100.x.y.z`)
3. From your laptop, open `http://100.x.y.z:8080`

**SSH tunnel (no Tailscale needed):**
If you have SSH access to the workstation, forward the port:
```bash
ssh -L 8080:localhost:8080 user@workstation-ip
```
Then open `http://localhost:8080` on your laptop. This also works through firewalls since it only needs outbound SSH.

**Claude Code login from inside the container:**
```bash
docker exec -it claude-workspace bash
claude login
```
It will print an OAuth URL — open it in your laptop/phone browser. Because the container uses host networking, the callback reaches it directly. The credential persists in your host's `~/.claude/`.

## Usage from your phone

1. Open your phone browser → go to the code-server URL
2. Enter your password
3. You get full VS Code: file explorer, terminal, image viewer
4. Open a terminal (hamburger menu → Terminal → New Terminal)
5. Run `claude` to start Claude Code
6. View plots: click any `.png`/`.svg` in the file explorer sidebar — it opens in a tab

## Session persistence

code-server runs server-side, so **closing your browser doesn't stop running processes**.
When you reconnect, your terminals and any running Claude Code session are still there.

For extra resilience on very long-running tasks, run Claude inside tmux within a
code-server terminal:
```bash
tmux new -s claude
claude
# detach: Ctrl+B, D
# reattach: tmux attach -t claude
```
This way the process survives even if code-server itself restarts — as long as the
container stays up.

## Tips

- **Viewing plots**: Matplotlib's `plt.savefig('plot.png')` → click it in the sidebar.
  Or use the Jupyter extension for inline plots.
- **Multiple terminals**: code-server supports split terminals, so you can have
  Claude Code in one and a regular shell in another.
- **Persist across rebuilds**: VS Code settings and Claude auth are stored in Docker
  volumes, so `docker compose down && docker compose up` won't lose your config.
- **Mobile keyboard**: code-server respects your phone's keyboard autocorrect.
  For even better mobile typing, try the "Hacker Keyboard" app (Android) or just
  rely on iOS/Android native keyboard.

## Updating

```bash
docker compose down
docker compose build --no-cache
docker compose up -d
```
