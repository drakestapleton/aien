#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# Build the DRA-172 runtime-path programs (rpath, rpfix, rpver, rpcase) from seeded Omega.
# Usage: OMEGA_OMC=/path/to/omega-mv-f4df8239/seed/out/omc sh tests/runtime_path/build.sh OUTDIR [MUTANT_SED_FILE]
# The compiler must be omega-mv f4df8239's seed/out/omc (sha256 below) and the vendored units must
# match src/runtime_path/vendor/PIN; anything else exits 3 (NOT_RUN) before compiling. A refused
# compile exits with omc's error number and leaves no executable under that name.
# MUTANT_SED_FILE (optional): a file holding one `s|OLD|NEW|` line applied to rpath.om only; the
# build checks that exactly one line changed and writes OUTDIR/rpath as the mutant.
# This shell is a migration build adapter under aien#22 (shell retirement), not runtime logic.
set -eu
here=$(cd "$(dirname "$0")/../.." && pwd)
src=$here/src/runtime_path
out=${1:?usage: build.sh OUTDIR [MUTANT_SED_FILE]}
mut=${2:-}
omc=${OMEGA_OMC:?set OMEGA_OMC to omega-mv f4df8239 seed/out/omc}
pin=3ad9f10f64309e7acf8a725082b28e23a2a4aeb07e98322fb4dc0fcd8fc93194
got=$(sha256sum < "$omc" | cut -d' ' -f1)
if [ "$got" != "$pin" ]; then
  echo "NOT_RUN: omc sha256 $got is not the pinned $pin" >&2
  exit 3
fi
tail -n +2 "$src/vendor/PIN" | while read -r sum origin file; do
  have=$(sha256sum < "$src/vendor/$file" | cut -d' ' -f1)
  if [ "$have" != "$sum" ]; then
    echo "NOT_RUN: vendor/$file sha256 $have is not $sum ($origin)" >&2
    exit 3
  fi
done
mkdir -p "$out"
lib="$src/vendor/json.om $src/vendor/jsonw.om $src/vendor/http.om $src/vendor/notls.om $src/rpcom.om"
build() {
  name=$1; unit=$2
  { printf 'om2\n'; cat $lib "$unit"; } > "$out/$name.full.om"
  rc=0
  "$omc" < "$out/$name.full.om" > "$out/$name.new" 2> "$out/$name.err" || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "BUILD FAIL $name: $(cat "$out/$name.err") (rc $rc)" >&2
    : > "$out/$name.new"
    exit "$rc"
  fi
  chmod 700 "$out/$name.new"
  mv "$out/$name.new" "$out/$name"
  printf '%s %s %s\n' "$name" "$(sha256sum < "$unit" | cut -d' ' -f1)" "$(sha256sum < "$out/$name" | cut -d' ' -f1)"
}
rpath_src=$src/rpath.om
if [ -n "$mut" ]; then
  sed -f "$mut" "$src/rpath.om" > "$out/rpath.mutant.om"
  changed=$(diff "$src/rpath.om" "$out/rpath.mutant.om" | grep -c '^<' || true)
  if [ "$changed" != 1 ]; then
    echo "INVALID mutant $mut: $changed lines changed, need exactly 1" >&2
    exit 4
  fi
  rpath_src=$out/rpath.mutant.om
fi
build rpath "$rpath_src"
build rpfix "$src/rpfix.om"
build rpver "$src/rpver.om"
build rpcase "$src/rpcase.om"
