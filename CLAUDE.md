# EEVIAC (Claude-Multi-Workspace) — notes for agents

Single-container dev workspace: code-server (VS Code in the browser) + tmux +
Claude Code + CUDA/PyTorch, reached over Tailscale HTTPS. One host, one
container, host networking. Read this file first; `README.md` is the
user-facing setup guide. There is no test suite and no CI.

## Layout

| File | Role |
|---|---|
| `Dockerfile` | nvidia/cuda base, Python 3.12 (deadsnakes), PyTorch, Node 20, Claude Code (native installer, symlinked to `/usr/local/bin/claude`), code-server + extensions, `coder` user (UID = `HOST_UID` build arg) |
| `docker-compose.yml` | service `dev` → container `claude-workspace-c`, image `eeviac-dev`; bind mounts (incl. `~/.eeviac` for the SSH agent socket), all GPUs, `network_mode: host`, `restart: unless-stopped` |
| `entrypoint.sh` | runs as root: copies SSH keys for `coder`, symlinks git/Claude config, writes code-server config, detects the TLS cert, supervises code-server, starts a `main` tmux session |
| `code-server-config.yaml` | template copied into the container on every start; `bind-addr` sets the port (currently 8083) |
| `tmux-shell.sh` | VS Code's default terminal: `gosu coder tmux new-session -A -s <cwd basename>` |
| `start_docker.sh` / `stop_docker.sh` | the only supported way to bring the stack up/down (they export the env compose needs) |
| `renew_cert.sh` | renews the Tailscale HTTPS cert; `--install-cron` also installs a weekly root cron job |
| `install_tailscale.sh` | one-time host setup (Tailscale, cert, cron) |
| `connect_to_docker.sh` | `docker exec` shell as `coder` |

Untracked local files you may see: `Dockerfile_mine` (copy of the committed
CUDA 11.8 Dockerfile) and `TODO.txt` (docker-in-docker notes; impossible here
without `SYS_ADMIN`). Leave them alone unless asked.

## How it runs

- The host projects folder (`$PROJECTS_DIR`, default `~/projects`) is mounted
  at the **same absolute path** so Claude Code's per-project history lines up.
  `/workspace` inside the container is a symlink to it.
- Host `~/.claude`, `~/.claude.json`, `~/.gitconfig`, `~/.ssh` are mounted in;
  `coder` reaches them via symlinks into `/root` (`chmod 711 /root`).
- code-server runs as root; terminals drop to `coder` via tmux-shell so
  `claude --dangerously-skip-permissions` works (it refuses to run as root).
- SSH agent: `start_docker.sh` runs a dedicated `ssh-agent -a
  ~/.eeviac/ssh-agent.sock` on the host; compose mounts the directory at
  `/run/ssh-agent` and sets `SSH_AUTH_SOCK` to the socket inside it.
- TLS: the entrypoint uses the first `*.crt` in `/etc/tailscale/certs` that has
  a matching `.key`; otherwise plain HTTP.
- Host networking, so there is no port mapping; `EXPOSE` is informational.

## Operating it

```bash
./start_docker.sh            # sudo tailscale up → renew cert → build (cached) → up -d
./start_docker.sh --fresh    # rebuild without cache first
./stop_docker.sh             # compose down — ends every tmux/Claude session
./connect_to_docker.sh       # shell as coder
docker logs -f claude-workspace-c
```

Health checks:

```bash
docker ps --filter name=claude-workspace-c
ss -tlnp | grep 8083
openssl x509 -in /etc/tailscale/certs/*.crt -noout -dates
docker exec claude-workspace-c python3 -c 'import torch; print(torch.__version__, torch.cuda.is_available())'
docker exec claude-workspace-c ps -eo pid,user,etime,cmd   # code-server, tmux servers, claude
```

## Gotchas (all observed in practice)

1. **Compose env must be identical on every invocation.** `PROJECTS_DIR`,
   `CODE_SERVER_PASSWORD`, `CLAUDE_CODE_OAUTH_TOKEN` and `HOST_UID` are baked
   into the container config. A different value makes
   compose *recreate* the container (all tmux/Claude sessions die), and an
   unset password silently becomes `changeme`. Use the scripts and a gitignored
   `.env` next to `docker-compose.yml` (template: `.env.example`;
   `start_docker.sh` refuses to run while it still says `CHANGE-ME`). Never
   run bare `docker compose up` from a fresh shell.
2. **After a host reboot the container auto-restarts, but its SSH agent is
   dead** until the user logs in and runs `./start_docker.sh`, which recreates
   the socket in place (directory mount, so no container restart). Do not go
   back to bind-mounting the agent socket itself: the keyring socket under
   `/run/user/<uid>/` does not exist at boot, Docker created a directory
   there, runc refused to mount a directory onto a socket file, and the
   container never came back after reboots. If `~/.eeviac` is ever created
   by Docker (root-owned) because compose ran before `start_docker.sh`, the
   script stops with a `chown` hint.
3. **The HTTPS cert is a 90-day Let's Encrypt cert.** Only `renew_cert.sh`
   renews it (called by `start_docker.sh` and by the cron job it can install).
   code-server reads the cert only at startup; the entrypoint watches the files
   and restarts just code-server when they change, so tmux survives.
4. **Tailscale profiles.** `tailscale switch` changes the node's tailnet and
   DNS name. The cert is tied to one name; on another profile the host is
   unreachable from devices on the original tailnet and `renew_cert.sh` warns.
5. **Restarting the container kills sessions.** Prefer restarting only
   code-server (kill its PID inside the container; the supervisor relaunches
   it) over `docker restart`.
6. The port drifted 8080 → 8081 → 8083 across branches. `README.md`,
   `Dockerfile` (`EXPOSE`), `code-server-config.yaml` and the entrypoint banner
   must agree; the entrypoint reads the port from the config template.
7. `entrypoint.sh` runs with `set -e`; keep background work inside functions
   that call `set +e` (see `supervise_code_server`).
8. PID 1 starts with cwd `/workspace` (Dockerfile `WORKDIR`), which the
   entrypoint replaces with a symlink. It must `cd /` first: removing the cwd
   makes every child inherit a deleted directory and Node dies at startup
   with `process.cwd failed ... uv_cwd` (this happened). After any entrypoint
   edit, run the image once and read the log through `HTTPS server listening`.

## Branches

- `main`: CUDA 12.4 / torch 2.6.0.
- `feature/1080ti` and the committed state of `feature/5070`: CUDA 11.8 /
  torch 2.7.1 (for driver 535).
- `feature/5070` working tree (uncommitted when this was written): CUDA 12.8.1 /
  torch 2.11.0+cu128 for an RTX 5070 Ti on driver 580. This is what the running
  image was built from.

Match the CUDA base image to the host driver (`nvidia-smi` header) before
building; the `nvidia/cuda` image's `NVIDIA_REQUIRE_CUDA` enforces it.

## Verifying a change

For script/entrypoint edits: `bash -n <file>`, then `docker compose build`
(fast: the `COPY`s are the last layers), then `./start_docker.sh`. Confirm
`docker logs claude-workspace-c` shows `TLS cert valid until` and
`HTTPS server listening`, then load the URL from another device. Dockerfile
edits above the PyTorch layer trigger a multi-GB rebuild; say so before running
one.
