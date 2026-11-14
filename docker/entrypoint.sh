#!/usr/bin/env bash
# Runs the three tiers from the README in one container:
#   nginx        0.0.0.0:8551  (the only published port)
#   auth-server  127.0.0.1:8552 (OAuth 2.1 / bearer token)
#   seerr-mcp    127.0.0.1:8550 (the MCP server, no login of its own)
# The two inner tiers stay on loopback, as the project requires.
set -euo pipefail

export APP_SLUG=seerr
export CONFIG_DIR="${CONFIG_DIR:-/config}"
export PORT=8552
export UPSTREAM="http://127.0.0.1:8550"
export MCP_PORT=8550
mkdir -p "$CONFIG_DIR"

if [[ -z "${ISSUER:-}" ]]; then
  echo "ISSUER is required: the public https URL this server is reached at" >&2
  exit 1
fi

# First run: store the sign-in password from APP_PASSWORD, once.
if [[ -n "${APP_PASSWORD:-}" && ! -f "$CONFIG_DIR/password-hash" ]]; then
  node /app/set-password.js "$APP_PASSWORD" >/dev/null
  echo "Stored sign-in password in $CONFIG_DIR/password-hash"
fi

pids=()
shutdown() {
  kill -TERM "${pids[@]}" 2>/dev/null || true
  wait 2>/dev/null || true
  exit 0
}
trap shutdown TERM INT

# CLI choices are stdio|http; http is the streamable-http transport.
seerr-mcp --transport http --host 127.0.0.1 --port "$MCP_PORT" &
pids+=($!)

node /app/auth-server.js &
pids+=($!)

nginx -c /etc/nginx/seerr-mcp.conf -g 'daemon off;' &
pids+=($!)

# If any tier exits, stop the rest and let Docker restart the container.
set +e
wait -n
status=$?
set -e
kill -TERM "${pids[@]}" 2>/dev/null || true
wait 2>/dev/null || true
exit "$status"
