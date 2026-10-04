# Claude-Multi-Workspace
## Motivation

I wanted to have a way to [relatively] safely use claude in a dangerously-skip-permissions way across my projects, on my workstation, and to access my projects from any device at any time in a persistent manner.

## What this gives you

An nvidia and pytorch-enabled, containerized, assumed self-hosted worskpace, with multiple projects. Session persistence via tmux. 

- **VS Code in your phone or laptop browser** via [code-server](https://github.com/coder/code-server), with server-side persistence
- **Tmux enabled** [tmux](https://github.com/tmux/tmux/wiki) automatically as default terminal, with per-project named sessions
- **Claude Code** via CLI in the integrated terminal, containerized
- **Git configured** via proper ssh mounts
- **GPU access** for PyTorch / CUDA work
- **HTTPS** via Tailscale so you can access it securely from anywhere

## Prerequisites

- Docker with Compose
- NVIDIA GPU + drivers (for GPU access)
- Tailscale account

## Setup

### 1. Projects folder

By default, `~/projects` is mounted into the container. To use a different folder:

```bash
export PROJECTS_DIR=/path/to/your/projects
```

The folder is mounted at the same absolute path inside the container so that Claude Code's chat history (which is indexed by project path) stays linked correctly.

### 2. Install Tailscale and generate HTTPS certs

```bash
./install_tailscale.sh
```

This installs Tailscale (if not already installed), generates TLS certificates in `/etc/tailscale/certs/` (auto-detected by the container at startup), and installs a weekly cron job that renews them. See [HTTPS certificate renewal](#https-certificate-renewal).

### 3. Set your password

```bash
export CODE_SERVER_PASSWORD="something-secure"
```

Or, instead of exporting anything, copy `.env.example` to `.env` next to `docker-compose.yml` and fill in the password (and the Claude token described below); compose reads it automatically and it is gitignored. Use the same values on every start: a different value makes compose recreate the container, which ends every tmux session inside it.

### 4. Start the container

```bash
./start_docker.sh
```

This builds the image (if needed) and starts the container. Subsequent runs reuse cached layers.

### 5. Access from any device

Open `https://<your-tailscale-hostname>:8083` in your phone or laptop browser to access the full projects folder, then use the vs code interface to open a specific project. (The port is `bind-addr` in `code-server-config.yaml`.)

Find your hostname with `tailscale status` — it will be something like `myhost.tail1234.ts.net`.

### 6. Stop

```bash
./stop_docker.sh
```

## Claude Code

### Authentication

Log in from inside a code-server terminal (or via `./connect_to_docker.sh`):

```bash
claude login
```

It will print an OAuth URL — open it in any browser. Because the container uses host networking, the callback reaches it directly. The credential persists in your host's `~/.claude/`.

### Known issue: frequent logouts with multiple sessions

OAuth refresh tokens are single-use. When multiple concurrent Claude sessions share
the same `~/.claude/.credentials.json`, they race to refresh the token — one session
wins, the rest get 401 errors and force re-login. This is a [known upstream bug](https://github.com/anthropics/claude-code/issues/24317) with several open issues (#37678, #36911).

**Workaround 1 - use long-lived auth token. Export before starting docker:**

```bash
export CLAUDE_CODE_OAUTH_TOKEN="..."      # recommended: long-lived subscription token (run `claude setup-token` to generate)
```

**Workaround 2 — use an API key instead of OAuth:**

If you have access to the [Claude Console](https://console.anthropic.com/), set `ANTHROPIC_API_KEY`
in `start_docker.sh`. This bypasses OAuth entirely and has no refresh race. Note: this uses
API billing, not your subscription quota.

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

### Running with full permissions

Terminals run as a non-root `coder` user, so `--dangerously-skip-permissions` works:

```bash
claude --dangerously-skip-permissions
```

This gives Claude full autonomy — no prompts for file edits, shell commands, web searches, etc.

### Existing sessions

Your host's `~/.claude` and `~/.claude.json` are bind-mounted into the container, so existing chat history and auth carry over. Claude indexes sessions by absolute project path, which is why the projects folder is mounted at the same path inside the container.

**Note:** Don't run Claude on the same project from host and container simultaneously — this can cause file contention.

## Session persistence

code-server runs server-side, so **closing your browser doesn't stop running processes**. When you reconnect, your terminals and any running Claude Code session are still there.

Terminals auto-attach to project-specific tmux sessions (named after the project folder). This means long-running Claude sessions survive even if code-server restarts — as long as the container stays up.

### After a host reboot

The container comes back on its own (`restart: unless-stopped`). The SSH agent inside it is unavailable until you log in and run `./start_docker.sh` again, which recreates the agent socket in place (passphrase asked once per boot) and renews the HTTPS certificate if needed. tmux sessions do not survive a reboot.

## Git

Git config and SSH keys are mounted read-only from the host. Push, pull, and clone work out of the box — no additional setup needed inside the container.

Passphrase-protected keys are served by a dedicated `ssh-agent` that `start_docker.sh` runs on the host. Its socket lives in `~/.eeviac/` and that directory is mounted into the container, so the agent can be restarted (after a reboot, say) without restarting the container.

## HTTPS certificate renewal

`tailscale cert` issues 90-day Let's Encrypt certificates, and nothing renews the files on disk by itself. Once the certificate expires, browsers show an "expired certificate" warning or refuse to connect at all.

- `./start_docker.sh` runs `./renew_cert.sh` on every start.
- `./install_tailscale.sh` (or `./renew_cert.sh --install-cron`) installs `/etc/cron.d/tailscale-cert-renew`, which renews weekly while the container keeps running for months.
- The container watches the certificate files and restarts only code-server when they change, so tmux sessions (and Claude sessions inside them) survive.

Check the current expiry:

```bash
openssl x509 -in /etc/tailscale/certs/*.crt -noout -enddate
```

Renew by hand with `./renew_cert.sh`. The host must be on the Tailscale profile the certificate was issued for (`tailscale status` shows the active node name).

## Rebuilding

```bash
./stop_docker.sh
docker compose build --no-cache
./start_docker.sh
```

VS Code settings and Claude auth persist across rebuilds (stored in Docker volumes and host bind-mounts).

## Logs

```bash
docker logs -f claude-workspace-c
```

Startup prints the TLS status (`TLS cert valid until: ...` or a loud `EXPIRED` warning) followed by code-server's own `HTTPS server listening` line.
