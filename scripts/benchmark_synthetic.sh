#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${PORT:-4000}"
HOST="${HOST:-127.0.0.1}"
BENCHMARK_LABEL="${BENCHMARK_LABEL:-json_channels}"
BENCHMARK_WARMUP_SECONDS="${BENCHMARK_WARMUP_SECONDS:-3}"
BENCHMARK_LOG_DIR="${BENCHMARK_LOG_DIR:-$ROOT_DIR/benchmark_logs}"
BENCHMARK_OPEN_BROWSER="${BENCHMARK_OPEN_BROWSER:-1}"
URL="http://${HOST}:${PORT}/benchmark/synthetic"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$BENCHMARK_LOG_DIR/${TIMESTAMP}_${BENCHMARK_LABEL}.log"

cd "$ROOT_DIR"
mkdir -p "$BENCHMARK_LOG_DIR"

export LIVE_TRIVIA_BENCHMARK=1
export LIVE_TRIVIA_BENCHMARK_LABEL="$BENCHMARK_LABEL"
export PHX_SERVER=true
export PORT

command -v mix >/dev/null 2>&1 || {
  echo "mix is not available on PATH" >&2
  exit 1
}

printf 'Benchmark label: %s\n' "$BENCHMARK_LABEL"
printf 'Benchmark log: %s\n' "$LOG_FILE"
printf 'Starting server on %s...\n' "http://${HOST}:${PORT}"

mix phx.server >"$LOG_FILE" 2>&1 &
SERVER_PID=$!
tail -f "$LOG_FILE" &
TAIL_PID=$!

cleanup() {
  kill "$TAIL_PID" 2>/dev/null || true
  kill "$SERVER_PID" 2>/dev/null || true
}
trap cleanup EXIT

printf 'Waiting for server readiness...\n'
READY=0
for _ in $(seq 1 60); do
  if curl -fsS "http://${HOST}:${PORT}/" >/dev/null 2>&1; then
    READY=1
    break
  fi
  sleep 0.5
done

if [ "$READY" != "1" ]; then
  printf 'Server did not become ready. See log: %s\n' "$LOG_FILE" >&2
  exit 1
fi

printf 'Warmup before browser launch: %ss\n' "$BENCHMARK_WARMUP_SECONDS"
sleep "$BENCHMARK_WARMUP_SECONDS"

if [ "$BENCHMARK_OPEN_BROWSER" = "1" ]; then
  printf 'Opening benchmark: %s\n' "$URL"
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$URL" >/dev/null 2>&1 || true
  elif command -v open >/dev/null 2>&1; then
    open "$URL" >/dev/null 2>&1 || true
  elif command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoProfile -Command "Start-Process '$URL'" >/dev/null 2>&1 || true
  else
    printf 'No browser opener found. Open manually: %s\n' "$URL"
  fi
else
  printf 'Browser launch disabled. Open manually: %s\n' "$URL"
fi

printf '\nBenchmark telemetry is enabled. Press Ctrl+C to stop the server.\n'
printf 'Logs are being saved to: %s\n\n' "$LOG_FILE"
wait "$SERVER_PID"
