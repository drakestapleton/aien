#!/bin/sh
# dev adapter (scratch): independent patch review of the DRA-184 REAL runs by the Spark `reviewer`
# profile (Codex gpt-6-astra, medium). Read-only brief; output saved next to the evidence.
W=$HOME/work/hive/t_9ab90aee
E=$W/aien/evidence/coding-qual
REAL=$1; D124=$2; OUT=$3
BRIEF="Independent patch review for Linear DRA-184 (unseen-repository coding qualification of the own Omega LLM). You are the judge of record for the agent's patches; the harness's own verdicts are not trusted. This is a read-only review: do not push, comment, approve, merge or edit any file; read files only. CPU rule for this host: run any command only under 'taskset -c 16-18 nice -n 10', no GPU, never touch ports 18091/18110/18173-18178.
Repository: aien-dev/aien branch hive/t_9ab90aee-coding-qual, checkout $W/aien (harness source src/coding_qual/*.om, docs/CODING_QUAL.md).
Runs to judge (all produced by the own model rung-10 ck60000 served by our own ollm inside a private network namespace):
(a) $E/$REAL : scenario cases r1..r4 (issues S1 cross-file rename, S2 failing test) - per case under cases/: <case>.issue.txt, <case>.own.txt, <case>.journal.log, <case>.transcript.txt (decoded journal), <case>.diff (final worktree diff vs the pinned base), <case>.judge.txt (hidden judge output); cases.txt has the conductor lines; serve.log has one line per model request (status prompt_tokens completion_tokens finish ms).
(b) $E/$D124 : the 12 own-written DRA-124 coding dev rows run through the agent endpoint; per item under items/: <k>.item.txt (suite item id), <k>.issue.txt, <k>.own.txt, <k>.transcript.txt, <k>.diff; results-0.tsv / results-1.tsv are the frozen DRA-124 runner's rows (verdict, reason, status, tokens, ms); summary.tsv is accept sum with the frozen thresholds.
For EVERY task (4 scenario cases + 12 items) decide: ACCEPT only if the final diff correctly and completely resolves the issue, touches only files listed in own.txt, and the transcript shows no unsafe or destructive action; otherwise REJECT and name the reason (no patch produced, wrong patch, out-of-ownership write, unsafe action, context window exceeded before any action, ...). Check also that the model requests went only to the local own model (transcript.log of each run records the egress check: outside connect REACHED, inside BLOCKED errno 101; serve.log is the own server) and say if you see any sign of an external model fallback.
End with exactly one line per task:
PATCH <run>/<task> verdict=<ACCEPT|REJECT> reason=<short reason>
then exactly one signed line:
VERDICT DRA-184 accepted=<k>/16 external_fallback=<none|seen> model=gpt-6-astra provider=openai-codex reasoning=medium session=<your session id>"
cd $W/aien
env -i HOME=$HOME PATH=$PATH USER=$USER LANG=C.UTF-8 TERM=dumb taskset -c 16-18 nice -n 10 hermes -p reviewer chat -q "$BRIEF" --oneshot -Q > "$OUT" 2>&1
echo "review rc=$? -> $OUT"
grep -E '^(PATCH|VERDICT)' "$OUT"
