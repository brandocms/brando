#!/usr/bin/env bash
# Starts and stops a background E2E server for one instance, for screenshots
# (scripts/shoot.mjs) and manual checks. It only ever signals the process group
# it started itself, recorded in a pidfile; it never matches processes by name,
# so servers from other worktrees and instances are safe.
#
#   cd e2e
#   BRANDO_E2E_INSTANCE=my_task scripts/server.sh start [--reset] [--assets]
#   BRANDO_E2E_INSTANCE=my_task scripts/server.sh status
#   BRANDO_E2E_INSTANCE=my_task scripts/server.sh stop
#   BRANDO_E2E_INSTANCE=my_task scripts/server.sh restart
#
# start    compiles, creates/migrates the instance database and seeds it when it
#          is empty (priv/repo/prepare_e2e.exs, like test_e2e.sh), then starts
#          `MIX_ENV=e2e mix phx.server` in the background and waits until the
#          admin login page answers. --reset drops and reseeds the database
#          first; --assets rebuilds e2e/assets/backend first (the server caches
#          the asset manifest, so JS/CSS changes need a rebuild and a restart).
# stop     sends TERM to the recorded process group, then KILL after 15s.
# status   prints the URL, pid and whether the server answers.
# log      tails the server log.
#
# Files: tmp/instances/<instance>/server.pid and server.log (e2e/tmp is ignored).
# Set BRANDO_E2E_INSTANCE before running: without it .envrc derives one from
# the worktree path, which is fine for one server per worktree.
# BRANDO_E2E_START_TIMEOUT (seconds, default 300) bounds the wait for the port.
set -euo pipefail

cd "$(dirname "$0")/.."
e2e_dir="$PWD"
# shellcheck disable=SC1091
source .envrc

instance_dir="$e2e_dir/tmp/instances/$(printf '%s' "$BRANDO_E2E_INSTANCE" | LC_CTYPE=C tr -c 'a-zA-Z0-9_' '_')"
pidfile="$instance_dir/server.pid"
logfile="$instance_dir/server.log"
login_url="$BRANDO_E2E_BASE_URL/admin/login"
timeout="${BRANDO_E2E_START_TIMEOUT:-300}"

# mix is not on PATH in non-interactive shells when Elixir comes from mise.
mix_cmd=(mix)
if ! command -v mix >/dev/null 2>&1; then
  if command -v mise >/dev/null 2>&1; then
    mix_cmd=(mise exec -- mix)
  elif [ -x "$HOME/.local/bin/mise" ]; then
    mix_cmd=("$HOME/.local/bin/mise" exec -- mix)
  else
    echo "mix not found on PATH (and no mise to run it with)" >&2
    exit 1
  fi
fi

answers() {
  curl -s -o /dev/null --max-time 5 -w '%{http_code}' "$login_url" 2>/dev/null | grep -qE '^[23]'
}

port_taken() {
  (exec 3<>"/dev/tcp/127.0.0.1/$BRANDO_E2E_PORT") 2>/dev/null
}

# The recorded pid, if that process is still alive and still leads its own
# process group (so a recycled pid belonging to something else is ignored).
own_pid() {
  [ -f "$pidfile" ] || return 1
  local pid pgid
  pid="$(cat "$pidfile")"
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$pid" 2>/dev/null || return 1
  pgid="$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')"
  [ "$pgid" = "$pid" ] || return 1
  echo "$pid"
}

status() {
  local pid
  echo "instance: $BRANDO_E2E_INSTANCE"
  echo "database: $BRANDO_E2E_DATABASE"
  echo "url:      $BRANDO_E2E_BASE_URL"
  echo "log:      $logfile"
  if pid="$(own_pid)"; then
    if answers; then echo "server:   running (pid $pid)"; else echo "server:   starting or not answering (pid $pid)"; fi
    return 0
  fi
  if answers; then
    echo "server:   answering, but not started by this script (no pidfile): leaving it alone"
    return 0
  fi
  echo "server:   stopped"
  return 3
}

start() {
  local reset=() assets=false pid
  for arg in "$@"; do
    case "$arg" in
      --reset) reset=(--reset) ;;
      --assets) assets=true ;;
      *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
  done

  if pid="$(own_pid)"; then
    echo "Already running (pid $pid) at $BRANDO_E2E_BASE_URL. Use restart to pick up changes."
    return 0
  fi
  if port_taken; then
    echo "Port $BRANDO_E2E_PORT is in use by a process this script did not start." >&2
    echo "Pick another BRANDO_E2E_INSTANCE, or stop that server where it was started." >&2
    exit 1
  fi
  mkdir -p "$instance_dir"
  rm -f "$pidfile"

  if [ "$assets" = true ]; then
    echo "Building e2e/assets/backend"
    if command -v pnpm >/dev/null 2>&1; then
      (cd assets/backend && pnpm build)
    else
      (cd assets/backend && CI=true npx -y pnpm@10 build)
    fi
  fi

  echo "Preparing $BRANDO_E2E_DATABASE (compile, migrate, seed if empty)"
  BRANDO_SEEDING=true MIX_ENV=e2e "${mix_cmd[@]}" do compile + run --no-start priv/repo/prepare_e2e.exs ${reset[@]+"${reset[@]}"}

  echo "Starting $BRANDO_E2E_BASE_URL (log: $logfile)"
  # A new session makes the server the leader of its own process group, so stop
  # can signal mix, the BEAM and anything they spawn without touching others.
  # Without setsid (macOS), job control gives the job its own group instead.
  if command -v setsid >/dev/null 2>&1; then
    MIX_ENV=e2e setsid "${mix_cmd[@]}" phx.server </dev/null >"$logfile" 2>&1 &
  else
    set -m
    MIX_ENV=e2e "${mix_cmd[@]}" phx.server </dev/null >"$logfile" 2>&1 &
    set +m
  fi
  pid=$!
  echo "$pid" >"$pidfile"

  local waited=0
  until answers; do
    if ! kill -0 "$pid" 2>/dev/null; then
      rm -f "$pidfile"
      echo "The server exited during startup. Last lines of $logfile:" >&2
      tail -n 30 "$logfile" >&2
      exit 1
    fi
    if [ "$waited" -ge "$timeout" ]; then
      echo "No answer from $login_url after ${timeout}s; still running as pid $pid. See $logfile, or stop it." >&2
      exit 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
  echo "Running (pid $pid) at $BRANDO_E2E_BASE_URL"
}

stop() {
  local pid waited=0
  if ! pid="$(own_pid)"; then
    rm -f "$pidfile"
    if answers; then
      echo "A server answers at $BRANDO_E2E_BASE_URL, but this script did not start it: leaving it alone."
    else
      echo "Not running."
    fi
    return 0
  fi
  kill -TERM -- "-$pid" 2>/dev/null || true
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge 15 ]; then
      echo "Still running after 15s, sending KILL to process group $pid"
      kill -KILL -- "-$pid" 2>/dev/null || true
      break
    fi
    sleep 1
    waited=$((waited + 1))
  done
  rm -f "$pidfile"
  echo "Stopped (pid $pid)"
}

command="${1:-status}"
shift || true
case "$command" in
  start) start "$@" ;;
  stop) stop ;;
  restart) stop; start "$@" ;;
  status) status ;;
  log) tail -n "${1:-50}" -f "$logfile" ;;
  *) echo "usage: scripts/server.sh start [--reset] [--assets] | stop | restart | status | log [lines]" >&2; exit 2 ;;
esac
