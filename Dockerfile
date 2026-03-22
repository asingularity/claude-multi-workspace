FROM nvidia/cuda:11.8.0-devel-ubuntu22.04

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

# Install PyTorch with CUDA 11.8
RUN pip install --no-cache-dir \
    torch==2.7.1+cu118 \
    torchaudio==2.7.1+cu118 \
    torchvision==0.22.1+cu118 \
    --index-url https://download.pytorch.org/whl/cu118

# Install remaining dependencies
RUN pip install --no-cache-dir \
    e3nn==0.5.9 \
    numpy==2.4.0 \
    scipy==1.16.3 \
    matplotlib==3.10.8 \
    PyYAML==6.0.3 \
    pytest==9.0.2 \
    line_profiler==5.0.0

# Install Node.js (for Claude CLI)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Install Claude Code
RUN npm install -g @anthropic-ai/claude-code

# Install gosu for dropping privileges
RUN apt-get update && apt-get install -y --no-install-recommends gosu && rm -rf /var/lib/apt/lists/*

# Create non-root user (Claude Code refuses --dangerously-skip-permissions as root)
RUN useradd -m -s /bin/bash -u 1000 coder

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

WORKDIR /home/csaba/projects

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
