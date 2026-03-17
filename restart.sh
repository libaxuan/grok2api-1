#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

HOST="${SERVER_HOST:-0.0.0.0}"
PORT="${SERVER_PORT:-8011}"
WORKERS="${SERVER_WORKERS:-1}"

echo "[restart] project: $ROOT_DIR"
echo "[restart] listening: ${HOST}:${PORT}  workers=${WORKERS}"

# Ensure local data/config exists (same logic as docker entrypoint)
DATA_DIR="${DATA_DIR:-$ROOT_DIR/data}"
LOG_DIR="${LOG_DIR:-$ROOT_DIR/logs}"
TMP_DIR="${TMP_DIR:-$DATA_DIR/tmp}"
mkdir -p "$DATA_DIR" "$LOG_DIR" "$TMP_DIR"
if [ ! -f "$DATA_DIR/config.toml" ]; then
  cp "$ROOT_DIR/config.defaults.toml" "$DATA_DIR/config.toml"
fi
if [ ! -f "$DATA_DIR/token.json" ]; then
  echo "{}" > "$DATA_DIR/token.json"
fi
chmod 600 "$DATA_DIR/config.toml" "$DATA_DIR/token.json" 2>/dev/null || true

if ! command -v uv >/dev/null 2>&1; then
  echo "[restart] ERROR: uv not found. Install uv first." >&2
  exit 1
fi

echo "[restart] syncing deps (uv sync)"
uv sync

echo "[restart] stopping any process on port ${PORT}"
if command -v lsof >/dev/null 2>&1; then
  PIDS="$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true)"
  if [ -n "${PIDS:-}" ]; then
    echo "[restart] killing: ${PIDS}"
    for p in $PIDS; do
      kill "$p" 2>/dev/null || true
    done
    sleep 1
    PIDS2="$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true)"
    if [ -n "${PIDS2:-}" ]; then
      echo "[restart] force killing: ${PIDS2}"
      for p in $PIDS2; do
        kill -9 "$p" 2>/dev/null || true
      done
      sleep 1
    fi
  fi
fi

LOG_FILE="$LOG_DIR/server_${PORT}.log"
echo "[restart] starting granian -> $LOG_FILE"
nohup uv run granian --interface asgi --host "$HOST" --port "$PORT" --workers "$WORKERS" main:app \
  >"$LOG_FILE" 2>&1 &

sleep 0.6
if command -v lsof >/dev/null 2>&1; then
  lsof -nP -iTCP:"$PORT" -sTCP:LISTEN || true
fi

echo "[restart] health check: http://127.0.0.1:${PORT}/health"
curl -fsS "http://127.0.0.1:${PORT}/health" >/dev/null && echo "[restart] OK"
echo "[restart] admin: http://127.0.0.1:${PORT}/admin/login"
