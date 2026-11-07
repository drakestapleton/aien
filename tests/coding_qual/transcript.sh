#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# Render a cqa journal (DRA-184) as a readable transcript: every hex field decoded, one block per
# record. Evidence formatting only (derived from journal.log, which stays the record of truth).
# Usage: sh tests/coding_qual/transcript.sh JOURNAL > TRANSCRIPT
set -eu
dec() { if [ "$1" = - ]; then printf ''; else printf '%s' "$1" | xxd -r -p; fi; }
while IFS=' ' read -r k s a b c d e; do
  case $k in
    J) echo "== journal $s $a" ;;
    I) echo "== step $s: inference started" ;;
    R) echo "== step $s: model answer (prompt_tokens $a, completion_tokens $b, $c ms)"; dec "$d"; echo ;;
    N) echo "== step $s: inference failed reason $a (1 ctx, 2 http, 3 conn, 4 json) status $b" ;;
    A) echo "== step $s: action kind $a (0 none 1 LIST 2 READ 3 WRITE 4 TEST 5 DONE) ok $b (1 ok, 0 bad path, 2 not owned, 3 no block) path $(dec "$c")" ;;
    E) echo "== step $s: write intent $(dec "$a")" ;;
    D) echo "== step $s: write done length $a fnv64 $b" ;;
    O) echo "== step $s: observation"; dec "$a"; echo ;;
    X) echo "== cancel requested" ;;
    T) echo "== terminal state $a (1 DONE, 2 CANCELLED, 3 BUDGET, 4 FAILED)" ;;
    *) echo "== UNKNOWN RECORD: $k $s" ;;
  esac
done < "$1"
