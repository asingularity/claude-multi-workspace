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

This installs Tailscale (if not already installed) and generates TLS certificates in `/etc/tailscale/certs/`. These are auto-detected by the container at startup.

### 3. Set your password

```bash
export CODE_SERVER_PASSWORD="something-secure"
```

### 4. Start the container

```bash
./start_docker.sh
```

This builds the image (if needed) and starts the container. Subsequent runs reuse cached layers.

### 5. Access from any device

Open `https://<your-tailscale-hostname>:8080` in your phone or laptop browser to access the full projects folder, then use the vs code interface to open a specific project.  

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

**Workaround — use an API key instead of OAuth:**

If you have access to the [Claude Console](https://console.anthropic.com/), set `ANTHROPIC_API_KEY`
in `start_docker.sh`. This bypasses OAuth entirely and has no refresh race. Note: this uses
API billing, not your subscription quota.

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

If you must use a subscription, minimize the issue by avoiding simultaneous sessions
that are idle long enough for tokens to expire (~15 hours). Active sessions are fine;
the race only triggers when multiple sessions try to refresh at the same time.

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

## Git

Git config and SSH keys are mounted read-only from the host. Push, pull, and clone work out of the box — no additional setup needed inside the container.

## Rebuilding

```bash
./stop_docker.sh
docker compose build --no-cache
./start_docker.sh
```

VS Code settings and Claude auth persist across rebuilds (stored in Docker volumes and host bind-mounts).

## Logs

```bash
docker compose logs -f
```
