FROM nvidia/cuda:12.4.1-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

# Install Python 3.12 from deadsnakes PPA (matches host)
RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common && \
    add-apt-repository ppa:deadsnakes/ppa && \
    apt-get update && apt-get install -y --no-install-recommends \
    python3.12 python3.12-venv python3.12-dev \
    git curl wget tmux htop jq openssh-client \
    # code-server needs these
    libx11-6 libxkbfile1 libsecret-1-0 \
    && rm -rf /var/lib/apt/lists/*

RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 && \
    update-alternatives --install /usr/bin/python python /usr/bin/python3.12 1

# Bootstrap pip for 3.12
RUN curl -sS https://bootstrap.pypa.io/get-pip.py | python3.12

# Install PyTorch with CUDA 12.4
RUN pip install --no-cache-dir \
    torch==2.6.0+cu124 \
    torchaudio==2.6.0+cu124 \
    torchvision==0.21.0+cu124 \
    --index-url https://download.pytorch.org/whl/cu124

# Install remaining dependencies
RUN pip install --no-cache-dir \
    e3nn==0.5.9 \
    numpy==2.4.0 \
    scipy==1.16.3 \
    matplotlib==3.10.8 \
    PyYAML==6.0.3 \
    pytest==9.0.2 \
    line_profiler==5.0.0

# Install Node.js (used by code-server; Claude Code has its own native binary)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Install Claude Code via the native installer.
# WORKDIR must be set before running — installing from / causes the installer
# to scan the whole filesystem and hang (per Anthropic's Docker troubleshooting).
# The installer drops the binary at ~/.local/bin/claude; symlink into /usr/local/bin
# so it's on PATH for all users (root, coder) without further setup.
WORKDIR /tmp
RUN curl -fsSL https://claude.ai/install.sh | bash && \
    ln -s /root/.local/bin/claude /usr/local/bin/claude

# Install gosu for dropping privileges
RUN apt-get update && apt-get install -y --no-install-recommends gosu && rm -rf /var/lib/apt/lists/*

# Create non-root user (Claude Code refuses --dangerously-skip-permissions as root)
# UID must match host user so bind-mounted files (~/.claude) are accessible
ARG HOST_UID=1000
RUN useradd -m -s /bin/bash -u ${HOST_UID} coder

# Install code-server
RUN curl -fsSL https://code-server.dev/install.sh | sh

# Install useful VS Code extensions
RUN code-server --install-extension ms-python.python && \
    code-server --install-extension ms-toolsai.jupyter && \
    code-server --install-extension mhutchie.git-graph

# code-server config template (entrypoint copies to config dir on first run)
COPY code-server-config.yaml /etc/code-server-config.yaml

# tmux shell wrapper — auto-attaches terminals to project-named sessions
COPY tmux-shell.sh /usr/local/bin/tmux-shell
RUN chmod +x /usr/local/bin/tmux-shell

# Entrypoint that starts code-server and keeps a bash session available
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /workspace

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
