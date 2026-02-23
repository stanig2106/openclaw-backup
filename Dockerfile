ARG BASE_IMAGE=openclaw:base
FROM ${BASE_IMAGE}

USER root

# sudo + outils essentiels
RUN apt-get update && apt-get install -y --no-install-recommends \
    sudo \
    build-essential \
    procps \
    file \
    ffmpeg \
    python3-venv \
    && rm -rf /var/lib/apt/lists/* \
    && echo "node ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Go
ARG GO_VERSION=1.23.6
RUN ARCH=$(dpkg --print-architecture) \
    && curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" \
    | tar -C /usr/local -xzf -

# uv (Python package manager)
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

# Homebrew (doit être installé en tant que non-root)
USER node
ENV HOMEBREW_NO_ANALYTICS=1
ENV HOMEBREW_NO_AUTO_UPDATE=1
RUN NONINTERACTIVE=1 bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Bun
RUN curl -fsSL https://bun.sh/install | bash
RUN mkdir -p /home/node/go

# PATH avec tous les outils
ENV PATH="/home/node/.bun/bin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:/usr/local/go/bin:/home/node/go/bin:${PATH}"
ENV GOPATH="/home/node/go"

WORKDIR /app

# Exposer la CLI "openclaw" (wrapper vers node dist/index.js)
USER root
RUN printf '#!/bin/sh\nexec node /app/dist/index.js "$@"\n' > /usr/local/bin/openclaw \
 && chmod +x /usr/local/bin/openclaw
USER node

