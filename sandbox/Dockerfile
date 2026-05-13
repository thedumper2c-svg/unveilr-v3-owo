FROM node:20-slim

# Base packages
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        unzip \
        lua5.4 \
    && rm -rf /var/lib/apt/lists/*

# Install rokit (use /opt as HOME so rokit stores tools in /opt/.rokit)
RUN mkdir -p /opt
ENV HOME="/opt"
ENV PATH="/opt/.rokit/bin:${PATH}"

RUN curl -sSf https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash \
    && if [ -x /root/.rokit/bin/rokit ] && [ ! -x /opt/.rokit/bin/rokit ]; then \
        rm -rf /opt/.rokit; \
        mv /root/.rokit /opt/.rokit; \
    fi

WORKDIR /opt
RUN /opt/.rokit/bin/rokit init || true

# Install tools via rokit (write manifest into /opt/rokit.toml)
RUN /opt/.rokit/bin/rokit trust lune-org/lune luau-lang/lute \
    && /opt/.rokit/bin/rokit add lune-org/lune \
    && /opt/.rokit/bin/rokit add luau-lang/lute@0.1.0-nightly.20260205 \
    && /opt/.rokit/bin/rokit install --no-trust-check \
    && LUNE_BIN=$(find /opt/.rokit/tool-storage/lune-org/lune -type f -name lune | head -n 1) \
    && LUTE_BIN=$(find /opt/.rokit/tool-storage/luau-lang/lute -type f -name lute | head -n 1) \
    && ln -sf "$LUNE_BIN" /usr/local/bin/lune \
    && ln -sf "$LUTE_BIN" /usr/local/bin/lute \
    && chmod -R a+rx /opt/.rokit /usr/local/bin/lune /usr/local/bin/lute

WORKDIR /app
