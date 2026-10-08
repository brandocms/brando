#!/usr/bin/env bash
# Prints "E2E server ready on :PORT" once the server answers HTTP on PORT,
# then exits. Polls the port rather than reading logs: the E2E logger runs
# at :warning, so Phoenix's "Running ... Endpoint at" line never appears.
#
#   ./server_ready.sh PORT [SUFFIX] &
#
# test_e2e.sh and test_e2e_parallel.sh start it in the background and stop it
# when they exit, so a server that never comes up prints nothing here.
port="${1:?usage: server_ready.sh PORT [SUFFIX]}"
suffix="${2:-}"

until curl -s -o /dev/null --max-time 2 "http://localhost:$port/"; do
  sleep 1
done
echo "E2E server ready on :$port${suffix:+ $suffix}"
