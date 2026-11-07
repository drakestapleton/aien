#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# DRA-172 runtime-path gate: build the seeded Omega runtime path with the pinned compiler, run the
# scenario conductor, and (synthetic mode) show that every planted runtime defect is caught.
#   OMEGA_OMC=... bash tests/runtime_path/gate.sh synthetic
#   OMEGA_OMC=... RP_MODEL_ID="..." bash tests/runtime_path/gate.sh real PORT
# synthetic: label SYNTHETIC. rpfix is a protocol fixture, not a model: this proves interfaces,
#            journal, recovery and verification only. Prints `GATE SYNTHETIC PASS cases=N mutants=K/K`.
# real:      label REAL. A model server must already listen on 127.0.0.1:PORT (never started or
#            stopped here; never use 18091). RP_MODEL_ID (free text: checkpoint sha256, tokenizer
#            id, server commit) is copied into the receipt as given. Prints `GATE REAL PASS|FAIL`.
# Exit 0 PASS, 1 FAIL, 2 usage, 3 NOT_RUN (compiler or vendor pin mismatch).
# Evidence goes to ${RP_RUN_ROOT:-evidence/runtime-path}/<UTC>-<mode>/: transcript, cases, hashes,
# journals and verifier outputs of every case, mutant table. This shell is a migration adapter
# under aien#22; the runtime, fixture, verifier and conductor are .om.
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
mode=${1:-}
port=${2:-}
case $mode in
  synthetic) label=SYNTHETIC ;;
  real) label=REAL
        if ! printf '%s' "$port" | grep -Eq '^[0-9]{1,5}$' || [ "$port" = 18091 ]; then
          echo "usage: gate.sh real PORT (not 18091)" >&2; exit 2; fi ;;
  *) echo "usage: gate.sh synthetic | real PORT" >&2; exit 2 ;;
esac
: "${OMEGA_OMC:?set OMEGA_OMC to omega-mv f4df8239 seed/out/omc}"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
run_root=${RP_RUN_ROOT:-$repo/evidence/runtime-path}
run=$run_root/$stamp-$mode
mkdir -p "$run_root"
mkdir "$run"
scratch=$(mktemp -d "${RP_SCRATCH:-${TMPDIR:-/tmp}}/rp-gate-XXXXXX")
trap 'rm -rf "$scratch"' EXIT
log=$run/transcript.log
{
  echo "label $label"
  echo "repo $(git -C "$repo" rev-parse HEAD) dirty=$(git -C "$repo" status --porcelain -- src/runtime_path tests/runtime_path | wc -l)"
  echo "omc $(sha256sum < "$OMEGA_OMC" | cut -d' ' -f1)"
  echo "host $(uname -srm)"
  echo "started $stamp"
} > "$log"
rc=0
sh "$repo/tests/runtime_path/build.sh" "$scratch/bin" > "$run/hashes.txt" 2>> "$log" || rc=$?
if [ "$rc" -ne 0 ]; then
  echo "build rc $rc" >> "$log"
  if [ "$rc" -eq 3 ]; then echo "GATE $label NOT_RUN (pin)"; exit 3; fi
  echo "GATE $label FAIL (build)"; exit 1
fi
save_case_files() {
  local work=$1 dest=$2
  mkdir -p "$dest"
  for d in "$work"/*/; do
    [ -f "$d/journal.log" ] || continue
    c=$(basename "$d")
    cp "$d/journal.log" "$dest/$c.journal.log"
    [ -f "$d/memory.log" ] && cp "$d/memory.log" "$dest/$c.memory.log"
    [ -f "$d/sink/notify.log" ] && cp "$d/sink/notify.log" "$dest/$c.sink.log"
    for f in "$d"/out/*; do [ -f "$f" ] && cp "$f" "$dest/$c.out.$(basename "$f")"; done
    for s in ver st out; do [ -f "$work/$c.$s" ] && cp "$work/$c.$s" "$dest/$c.$s.txt"; done
  done
  [ -f "$work/fixture.log" ] && cp "$work/fixture.log" "$dest/fixture.log"
  return 0
}
if [ "$mode" = real ]; then
  echo "model ${RP_MODEL_ID:-UNRECORDED}" >> "$log"
  echo "port $port" >> "$log"
  crc=0
  "$scratch/bin/rpcase" real "$scratch/bin" "$scratch/work" "$port" > "$run/cases.txt" 2>> "$log" || crc=$?
  cat "$run/cases.txt" >> "$log"
  save_case_files "$scratch/work" "$run/cases"
  if [ "$crc" -eq 0 ]; then echo "GATE REAL PASS"; echo "GATE REAL PASS" >> "$log"; exit 0; fi
  echo "GATE REAL FAIL (rpcase rc $crc)"; echo "GATE REAL FAIL rc $crc" >> "$log"; exit 1
fi
crc=0
"$scratch/bin/rpcase" synthetic "$scratch/bin" "$scratch/work" > "$run/cases.txt" 2>> "$log" || crc=$?
cat "$run/cases.txt" >> "$log"
save_case_files "$scratch/work" "$run/cases"
ncases=$(grep -c '^CASE ' "$run/cases.txt" || true)
if [ "$crc" -ne 0 ]; then
  echo "GATE SYNTHETIC FAIL (baseline rpcase rc $crc)"; echo "baseline rc $crc" >> "$log"; exit 1
fi
printf 'id\tmust_fail\tbuild_rc\trpcase_rc\tobserved\tverdict\n' > "$run/mutants.tsv"
killed=0 total=0
while IFS=$'\t' read -r id want sedl what; do
  [ "$id" = id ] && continue
  total=$((total + 1))
  printf '%s\n' "$sedl" > "$scratch/m-$id.sed"
  brc=0
  sh "$repo/tests/runtime_path/build.sh" "$scratch/m-$id" "$scratch/m-$id.sed" >> "$run/mutant-hashes.txt" 2>> "$log" || brc=$?
  mrc=NA obs=NA verdict=INVALID
  if [ "$brc" -eq 0 ]; then
    mrc=0
    "$scratch/m-$id/rpcase" synthetic "$scratch/m-$id" "$scratch/mw-$id" > "$run/mutant-$id.txt" 2>> "$log" || mrc=$?
    obs=$(grep "^CASE $want " "$run/mutant-$id.txt" | awk '{print $4}')
    if [ "$mrc" -eq 1 ] && [ "$obs" = FAIL ]; then verdict=KILLED; killed=$((killed + 1)); else verdict=SURVIVED; fi
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$want" "$brc" "$mrc" "$obs" "$verdict" >> "$run/mutants.tsv"
done < "$repo/tests/runtime_path/mutants.tsv"
cat "$run/mutants.tsv" >> "$log"
if [ "$killed" -eq "$total" ] && [ "$total" -gt 0 ]; then
  echo "GATE SYNTHETIC PASS cases=$ncases mutants=$killed/$total" | tee -a "$log"; exit 0
fi
echo "GATE SYNTHETIC FAIL cases=$ncases mutants=$killed/$total" | tee -a "$log"; exit 1
