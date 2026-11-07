#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# DRA-184 coding qualification gate: build the seeded Omega harness with the pinned compiler, make the
# fixture repository, run the scenario conductor, and prove the harness can fail.
#   OMEGA_OMC=... bash tests/coding_qual/gate.sh synthetic
#   OMEGA_OMC=... CQ_MODEL_ID="..." bash tests/coding_qual/gate.sh real PORT
#   OMEGA_OMC=... ACCEPT=... ACCEPT_OMC=... ACCEPT_SUITE=... CQ_MODEL_ID="..." \
#       bash tests/coding_qual/gate.sh dra124 PORT [SPLIT]
# synthetic  label SYNTHETIC. cqfix is a scripted protocol fixture, not a model: cases c1..c13 prove the
#            agent loop, journal, cancel, kill/resume, ownership and the verifier/judge; then the
#            serve-path controls (the frozen DRA-124 runner through `cqa serve`: reference answers must
#            pass every coding dev row, garbage none) when ACCEPT is set; then every planted one-line
#            defect in cqa.om (tests/coding_qual/mutants.tsv) must make its named case FAIL.
# real       label REAL. Cases r1..r4 against a model already listening on 127.0.0.1:PORT (never
#            started or stopped here; never 18091): model-independent invariants are asserted, what
#            the model did is printed as OBSERVED lines.
# dra124     label REAL. The frozen DRA-124 suite runner (aien-train tests/omegallm/accept, ACCEPT =
#            its binary, ACCEPT_SUITE = its suite/ dir) sends every coding row of SPLIT (default dev)
#            to `cqa serve` (own port), which runs the agent loop against the model on PORT; then
#            `accept sum` applies the frozen thresholds.tsv. Two runner workers, as pre-registered.
# Exit 0 PASS, 1 FAIL, 2 usage, 3 NOT_RUN (compiler or vendor pin mismatch, missing inputs).
# Evidence: ${CQ_RUN_ROOT:-evidence/coding-qual}/<UTC>-<mode>/. This shell is a migration adapter
# under aien#22; the agent, fixture, verifier, judge driver and conductor are .om.
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
mode=${1:-}
port=${2:-}
okport() { printf '%s' "$1" | grep -Eq '^[0-9]{1,5}$' && [ "$1" != 18091 ]; }
case $mode in
  synthetic) label=SYNTHETIC ;;
  real|dra124) label=REAL
        if ! okport "$port"; then echo "usage: gate.sh $mode PORT (not 18091)" >&2; exit 2; fi ;;
  *) echo "usage: gate.sh synthetic | real PORT | dra124 PORT [SPLIT]" >&2; exit 2 ;;
esac
: "${OMEGA_OMC:?set OMEGA_OMC to omega-mv f4df8239 seed/out/omc}"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
run_root=${CQ_RUN_ROOT:-$repo/evidence/coding-qual}
run=$run_root/$stamp-$mode
mkdir -p "$run_root"
mkdir "$run"
scratch=$(mktemp -d "${CQ_SCRATCH:-${TMPDIR:-/tmp}}/cq-gate-XXXXXX")
[ -n "${CQ_KEEP:-}" ] || trap 'rm -rf "$scratch"' EXIT
log=$run/transcript.log
{
  echo "label $label"
  echo "repo $(git -C "$repo" rev-parse HEAD) dirty=$(git -C "$repo" status --porcelain -- src/coding_qual tests/coding_qual | wc -l)"
  echo "omc $(sha256sum < "$OMEGA_OMC" | cut -d' ' -f1)"
  echo "git $(git --version | cut -d' ' -f3) python3 $(/usr/bin/python3 --version | cut -d' ' -f2) bwrap $(bwrap --version | cut -d' ' -f2)"
  echo "host $(uname -srm)"
  echo "started $stamp"
} > "$log"
rc=0
sh "$repo/tests/coding_qual/build.sh" "$scratch/bin" > "$run/hashes.txt" 2>> "$log" || rc=$?
if [ "$rc" -ne 0 ]; then
  echo "build rc $rc" >> "$log"
  if [ "$rc" -eq 3 ]; then echo "GATE $label NOT_RUN (pin)"; exit 3; fi
  echo "GATE $label FAIL (build)"; exit 1
fi
# The fixture repository: branch cq-s1 is the clean scenario S1 base, cq-s2 adds one planted
# regression (truncate_words drops a word) for scenario S2. Fixed identity and dates make the
# commit ids reproducible; they are recorded in the receipt.
base=$scratch/base
mkdir -p "$base"
cp -r "$repo/tests/coding_qual/fixtures/textkit/." "$base/"
gitf() { env GIT_AUTHOR_NAME=cq GIT_AUTHOR_EMAIL=cq@invalid GIT_COMMITTER_NAME=cq GIT_COMMITTER_EMAIL=cq@invalid \
  GIT_AUTHOR_DATE=2026-11-07T00:00:00Z GIT_COMMITTER_DATE=2026-11-07T00:00:00Z git -C "$base" "$@"; }
gitf init -q -b cq-s1
gitf add -A
gitf commit -q -m "textkit fixture (DRA-184 S1 base)"
gitf checkout -q -b cq-s2
sed -i 's/words\[:n\]) if/words[:n - 1]) if/' "$base/textkit/words.py"
gitf commit -q -am "regression: truncate_words (DRA-184 S2 planted bug)"
gitf checkout -q cq-s1
echo "fixture cq-s1 $(gitf rev-parse cq-s1) cq-s2 $(gitf rev-parse cq-s2)" | tee -a "$log" > "$run/fixture.txt"
judges=$repo/tests/coding_qual/judges
save_cases() {
  local work=$1 dest=$2
  mkdir -p "$dest"
  for d in "$work"/*/; do
    [ -f "$d/journal.log" ] || continue
    c=$(basename "$d")
    for f in journal.log issue.txt own.txt test.txt item.txt base.txt; do
      [ -f "$d/$f" ] && cp "$d/$f" "$dest/$c.$f"
    done
    git -C "$d/repo" diff > "$dest/$c.diff" 2>/dev/null || true
    for s in script fix out1 out2 out3 judge git; do [ -f "$work/$c.$s" ] && cp "$work/$c.$s" "$dest/$c.$s.txt"; done
  done
  return 0
}
if [ "$mode" = real ]; then
  echo "model ${CQ_MODEL_ID:-UNRECORDED}" >> "$log"
  echo "port $port" >> "$log"
  crc=0
  "$scratch/bin/cqcase" real "$scratch/bin" "$scratch/work" "$base" "$judges" "$port" > "$run/cases.txt" 2>> "$log" || crc=$?
  cat "$run/cases.txt" >> "$log"
  save_cases "$scratch/work" "$run/cases"
  if [ "$crc" -eq 0 ]; then echo "GATE REAL PASS" | tee -a "$log"; exit 0; fi
  echo "GATE REAL FAIL (cqcase rc $crc)" | tee -a "$log"; exit 1
fi
if [ "$mode" = dra124 ]; then
  split=${3:-dev}
  : "${ACCEPT:?set ACCEPT to the DRA-124 accept binary}"; : "${ACCEPT_OMC:?set ACCEPT_OMC}"; : "${ACCEPT_SUITE:?set ACCEPT_SUITE}"
  ( cd "$ACCEPT_SUITE" && sha256sum -c --quiet SHA256SUMS ) || { echo "GATE REAL NOT_RUN (suite hash mismatch)"; exit 3; }
  if [ "$split" = test ]; then src=${ACCEPT_HOLDOUT:?set ACCEPT_HOLDOUT}/items-test.jsonl; else src=$ACCEPT_SUITE/items-$split.jsonl; fi
  mkdir -p "$scratch/suite" "$scratch/serve"
  jq -c 'select(.role=="coding")' "$src" > "$scratch/suite/items.jsonl"
  cp "$ACCEPT_SUITE/critical.txt" "$ACCEPT_SUITE/hive-system.txt" "$scratch/suite/"
  n=$(wc -l < "$scratch/suite/items.jsonl")
  sport=${CQ_SERVE_PORT:-18295}
  { echo "model ${CQ_MODEL_ID:-UNRECORDED}"; echo "model_port $port serve_port $sport split $split items $n"
    echo "accept $(sha256sum < "$ACCEPT" | cut -d' ' -f1) prereg $(sha256sum < "$ACCEPT_SUITE/../PREREG.md" | cut -d' ' -f1) thresholds $(sha256sum < "$ACCEPT_SUITE/thresholds.tsv" | cut -d' ' -f1)"
    echo "agent steps=${CQ_STEPS:-6} maxtok=${CQ_MAXTOK:-256}"; } >> "$log"
  "$scratch/bin/cqa" serve "$sport" "$port" "$scratch/serve" "steps=${CQ_STEPS:-6}" "maxtok=${CQ_MAXTOK:-256}" "max=$((n + 1))" > "$run/serve.log" 2>&1 &
  sp=$!
  sleep 0.5
  "$ACCEPT" run 127.0.0.1 "$sport" "$scratch/suite" "$scratch/out" "$ACCEPT_OMC" cqa-agent 0 1 0 2 > "$run/accept-w0.log" 2>&1 &
  w0=$!
  "$ACCEPT" run 127.0.0.1 "$sport" "$scratch/suite" "$scratch/out" "$ACCEPT_OMC" cqa-agent 0 1 1 2 > "$run/accept-w1.log" 2>&1 || true
  wait "$w0" || true
  kill "$sp" 2>/dev/null || true
  wait "$sp" 2>/dev/null || true
  src=0
  "$ACCEPT" sum "$scratch/out" "$ACCEPT_SUITE/thresholds.tsv" > "$run/summary.tsv" 2>&1 || src=$?
  cp "$scratch/out"/results-*.tsv "$run/" 2>/dev/null || true
  save_cases "$scratch/serve" "$run/items"
  cat "$run/summary.tsv" >> "$log"
  echo "accept sum rc $src" | tee -a "$log"
  echo "GATE REAL RAN (dra124 $split; verdict in summary.tsv)" | tee -a "$log"
  exit 0
fi
crc=0
"$scratch/bin/cqcase" synthetic "$scratch/bin" "$scratch/work" "$base" "$judges" > "$run/cases.txt" 2>> "$log" || crc=$?
cat "$run/cases.txt" >> "$log"
save_cases "$scratch/work" "$run/cases"
ncases=$(grep -c '^CASE ' "$run/cases.txt" || true)
if [ "$crc" -ne 0 ]; then
  echo "GATE SYNTHETIC FAIL (baseline cqcase rc $crc)" | tee -a "$log"; exit 1
fi
serve_ok=NOT_RUN
if [ -n "${ACCEPT:-}" ]; then
  serve_ok=PASS
  for arm in ref garbage; do
    sd=$scratch/sv-$arm
    mkdir -p "$sd/suite" "$sd/serve"
    jq -c 'select(.role=="coding")' "$ACCEPT_SUITE/items-dev.jsonl" > "$sd/suite/items.jsonl"
    cp "$ACCEPT_SUITE/critical.txt" "$ACCEPT_SUITE/hive-system.txt" "$sd/suite/"
    : > "$sd/script"
    while read -r it; do
      t=$(printf '%s' "$it" | jq -r '.rules[0][2]')
      if [ $arm = ref ]; then
        { printf 'WRITE %s\n' "$t"; printf '%s' "$it" | jq -r '.ref.content'; } | { printf 'C 0 '; xxd -p | tr -d '\n'; echo; } >> "$sd/script"
      else
        printf 'zq\n' | { printf 'C 0 '; xxd -p | tr -d '\n'; echo; } >> "$sd/script"
      fi
      printf 'DONE\n' | { printf 'C 0 '; xxd -p | tr -d '\n'; echo; } >> "$sd/script"
    done < "$sd/suite/items.jsonl"
    "$scratch/bin/cqfix" "$sd/script" 200 > "$sd/fix.log" 2>&1 &
    fp=$!
    sleep 0.3
    fport=$(sed -n 's/^PORT //p' "$sd/fix.log")
    "$scratch/bin/cqa" serve 18295 "$fport" "$sd/serve" steps=2 max=12 > "$run/serve-$arm.log" 2>&1 &
    sp=$!
    sleep 0.3
    "$ACCEPT" run 127.0.0.1 18295 "$sd/suite" "$sd/out" "$ACCEPT_OMC" cqa-synthetic-$arm 0 1 0 1 > "$run/accept-$arm.log" 2>&1 || true
    kill "$sp" "$fp" 2>/dev/null || true
    wait "$sp" "$fp" 2>/dev/null || true
    "$ACCEPT" sum "$sd/out" "$ACCEPT_SUITE/thresholds.tsv" > "$run/serve-$arm.summary.tsv" 2>&1 || true
    cp "$sd/out/results-0.tsv" "$run/serve-$arm.results.tsv"
    got=$(awk -F'\t' 'NF>=15 && $1=="coding" && $2=="dev" {print $4"/"$3}' "$run/serve-$arm.summary.tsv")
    want=12/12; [ $arm = garbage ] && want=0/12
    echo "SERVE $arm coding-dev $got want $want" | tee -a "$log"
    [ "$got" = "$want" ] || serve_ok=FAIL
  done
fi
printf 'id\tmust_fail\tbuild_rc\tcqcase_rc\tobserved\tverdict\n' > "$run/mutants.tsv"
killed=0 total=0
while IFS=$'\t' read -r id want sedl what; do
  [ "$id" = id ] && continue
  total=$((total + 1))
  printf '%s\n' "$sedl" > "$scratch/m-$id.sed"
  brc=0
  CQ_UNITS=cqa sh "$repo/tests/coding_qual/build.sh" "$scratch/m-$id" "$scratch/m-$id.sed" >> "$run/mutant-hashes.txt" 2>> "$log" || brc=$?
  mrc=NA obs=NA verdict=INVALID
  if [ "$brc" -eq 0 ]; then
    cp "$scratch/bin/cqfix" "$scratch/bin/cqcase" "$scratch/m-$id/"
    mrc=0
    "$scratch/m-$id/cqcase" synthetic "$scratch/m-$id" "$scratch/mw-$id" "$base" "$judges" > "$run/mutant-$id.txt" 2>> "$log" || mrc=$?
    obs=$(grep "^CASE $want " "$run/mutant-$id.txt" | awk '{print $4}')
    if [ "$mrc" -eq 1 ] && [ "$obs" = FAIL ]; then verdict=KILLED; killed=$((killed + 1)); else verdict=SURVIVED; fi
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$want" "$brc" "$mrc" "$obs" "$verdict" >> "$run/mutants.tsv"
done < "$repo/tests/coding_qual/mutants.tsv"
cat "$run/mutants.tsv" >> "$log"
if [ "$killed" -eq "$total" ] && [ "$total" -gt 0 ] && [ "$serve_ok" != FAIL ]; then
  echo "GATE SYNTHETIC PASS cases=$ncases serve=$serve_ok mutants=$killed/$total" | tee -a "$log"; exit 0
fi
echo "GATE SYNTHETIC FAIL cases=$ncases serve=$serve_ok mutants=$killed/$total" | tee -a "$log"; exit 1
