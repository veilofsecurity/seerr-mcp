# syntax=docker/dockerfile:1

# Node dependencies for the OAuth front (auth-server.js). Built on the full
# image so better-sqlite3 can compile if no prebuilt binary matches.
FROM node:24-bookworm AS node-deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# Python package (the MCP server) into a self-contained virtualenv.
FROM python:3.13-slim-bookworm AS python-deps
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /src
COPY pyproject.toml README.md LICENSE ./
COPY src ./src
RUN python -m venv /opt/venv \
 && /opt/venv/bin/pip install .

FROM python:3.13-slim-bookworm
LABEL org.opencontainers.image.title="seerr-mcp" \
      org.opencontainers.image.description="Overseerr/Jellyseerr MCP server with OAuth 2.1 front, for Claude.ai and Claude Code" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.source="https://github.com/veilofsecurity/seerr-mcp"

# nginx-light: the public front door. tini: PID 1 and signal forwarding.
# libstdc++6: needed by the Node binary copied in below.
RUN apt-get update \
 && apt-get install -y --no-install-recommends nginx-light tini libstdc++6 \
 && rm -rf /var/lib/apt/lists/*

COPY --from=node-deps /usr/local/bin/node /usr/local/bin/node
COPY --from=python-deps /opt/venv /opt/venv

WORKDIR /app
COPY --from=node-deps /app/node_modules ./node_modules
COPY package.json auth-server.js set-password.js ./
COPY public ./public
COPY docker/nginx.conf /etc/nginx/seerr-mcp.conf
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh

ENV PATH=/opt/venv/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    CONFIG_DIR=/config \
    SEERR_URL=http://127.0.0.1:5055

VOLUME ["/config"]
EXPOSE 8551

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8551/healthz', timeout=4)" || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
