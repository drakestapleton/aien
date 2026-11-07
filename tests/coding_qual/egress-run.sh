#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# DRA-184 REAL run inside the DRA-188 AI-egress-blocked environment (sovereign-intelligence
# tests/egress/egress-env.sh: own network namespace with only lo, emptied environment, /home, /run,
# /tmp and /dev/shm hidden except the paths bound below). Inside it this script starts OUR OWN
# `ollm serve` (aien-train DRA-119) with an own Omega LLM checkpoint on a candidate port of that
# namespace only (no host port is bound; never 18091), runs `gate.sh real` (r1..r4) and
# `gate.sh dra124` (the frozen DRA-124 coding rows through `cqa serve`), and stops the server.
# Outside, before entering, it records the negative control: the provider address IS reachable
# from the host (else the run proves nothing and is INCONCLUSIVE).
# Usage (outer): EGRESS_ENV=.../egress-env.sh EGRESS_BIN=.../egress OLLM=... CK=... MERGES=... \
#   OMEGA_OMC=... ACCEPT=... ACCEPT_OMC=... ACCEPT_SUITE=... CQ_RW=<dir> CQ_SCRATCH=<dir> \
#   sh tests/coding_qual/egress-run.sh [PORT] [SPLIT]
# Run it under the hive CPU rule, e.g. flock -o <pool lock> taskset -c <cores> nice -n 10 sh ...
# This shell is a migration adapter under aien#22 (it only wires processes together).
set -u
here=$(cd "$(dirname "$0")/../.." && pwd)
if [ "${1:-}" = __inner ]; then
  shift
  port=$1; split=$2
  echo "INNER $(date -u +%FT%TZ) uid $(id -u) env $(env | cut -d= -f1 | sort | tr '\n' ' ')"
  ip -o addr 2>/dev/null | awk '{print "netns-if", $2, $4}'
  "$EGRESS_BIN" connect "$PROBE_IP" 443 3000; echo "inside_connect rc=$?"
  ls -d /home/drakestapleton/.hermes /home/drakestapleton/.codex /home/drakestapleton/.config/gh 2>&1 | sed 's/^/hidden-check /'
  slog=$CQ_SCRATCH/serve-$port.log
  "$CQ_SRV" serve "$port" "$CK" "$MERGES" > "$slog" 2>&1 &
  sp=$!
  i=0
  while [ $i -lt 600 ] && ! grep -q '^PORT ' "$slog"; do sleep 0.1; i=$((i + 1)); done
  head -1 "$slog"
  export CQ_MODEL_ID
  rc1=0; bash "$here/tests/coding_qual/gate.sh" real "$port" || rc1=$?
  echo "gate real rc=$rc1"
  rc2=0; bash "$here/tests/coding_qual/gate.sh" dra124 "$port" "$split" || rc2=$?
  echo "gate dra124 rc=$rc2"
  kill "$sp" 2>/dev/null; wait "$sp" 2>/dev/null
  for d in $(ls -d "$CQ_RUN_ROOT"/*-real "$CQ_RUN_ROOT"/*-dra124 2>/dev/null | tail -2); do cp "$slog" "$d/serve.log"; done
  echo "INNER done $(date -u +%FT%TZ)"
  exit 0
fi
port=${1:-18294}
split=${2:-dev}
[ "$port" = 18091 ] && { echo "never 18091" >&2; exit 2; }
for v in EGRESS_ENV EGRESS_BIN OLLM CK MERGES OMEGA_OMC ACCEPT ACCEPT_OMC ACCEPT_SUITE CQ_RW CQ_SCRATCH; do
  eval "x=\${$v:-}"; [ -n "$x" ] || { echo "NOT_RUN: set $v" >&2; exit 3; }
done
PROBE_IP=$(getent ahostsv4 api.openai.com | awk 'NR==1 {print $1}')
echo "OUTER $(date -u +%FT%TZ) probe api.openai.com $PROBE_IP"
"$EGRESS_BIN" connect "$PROBE_IP" 443 3000; echo "outside_connect rc=$?"
CQ_MODEL_ID=${CQ_MODEL_ID:-"ollm $(sha256sum < "$OLLM" | cut -d' ' -f1) ck $(sha256sum < "$CK" | cut -d' ' -f1) merges $(sha256sum < "$MERGES" | cut -d' ' -f1) port $port (private netns)"}
echo "model $CQ_MODEL_ID"
exec sh "$EGRESS_ENV" \
  --ro "$(dirname "$OLLM")" --ro "$CK" --ro "$MERGES" --ro "$OMEGA_OMC" --ro "$ACCEPT" \
  --ro "$ACCEPT_OMC" --ro "$(dirname "$ACCEPT_SUITE")" --rw "$CQ_RW" --rw "$CQ_SCRATCH" \
  --env "CQ_SRV=$OLLM" --env "CK=$CK" --env "MERGES=$MERGES" --env "OMEGA_OMC=$OMEGA_OMC" \
  --env "ACCEPT=$ACCEPT" --env "ACCEPT_OMC=$ACCEPT_OMC" --env "ACCEPT_SUITE=$ACCEPT_SUITE" \
  --env "CQ_SCRATCH=$CQ_SCRATCH" --env "CQ_RUN_ROOT=${CQ_RUN_ROOT:-$here/evidence/coding-qual}" \
  --env "CQ_MODEL_ID=$CQ_MODEL_ID" --env "EGRESS_BIN=$EGRESS_BIN" --env "PROBE_IP=$PROBE_IP" \
  --env "CQ_STEPS=${CQ_STEPS:-6}" --env "CQ_MAXTOK=${CQ_MAXTOK:-256}" --env "TMPDIR=$CQ_SCRATCH" \
  -- /bin/sh "$here/tests/coding_qual/egress-run.sh" __inner "$port" "$split"
