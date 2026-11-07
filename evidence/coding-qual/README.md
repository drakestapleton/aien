# DRA-184 coding qualification receipts

These runs were produced by `tests/coding_qual/gate.sh` on the Spark (aarch64), at harness commit
`7771e99dcd33a9c2459542d4deb0de86103efb9d`. The harness was compiled with omega-mv `f4df8239`
`seed/out/omc` (sha256 `3ad9f10f…3194`); `hashes.txt` in each run has the source and binary sha256
of `cqa`, `cqfix` and `cqcase`. CPU use followed the hive rule: the SYNTHETIC run used pool 8-9 and
the REAL runs used pool 16-18, each under `flock -o` and `nice -n 10`. No GPU was used, and port
18091 was never used.

| run | label | result |
| --- | --- | --- |
| `20261107T022946Z-synthetic/` | SYNTHETIC | `GATE SYNTHETIC PASS cases=13 serve=PASS mutants=6/6` |
| `20261107T023102Z-real/` | REAL | `GATE REAL PASS`, `CQCASE REAL PASS cases=4`; every OBSERVED patch judge result is FAIL |
| `20261107T024331Z-dra124/` | REAL | frozen DRA-124 runner: coding dev **0 / 12 PASS**, reasons `ctx=12` |

## Identity of the REAL runs (pinned)

| item | value |
| --- | --- |
| model | own Omega LLM rung-10 `ck60000`, sha256 `a53ced7265818c8f6197449315e9ca4082721665022fec4f81d4538e8d6c2d0f` (T = 256, d = 384, 12 layers), the DRA-124 baseline candidate (PREREG §7) |
| tokenizer | `merges4096` (OLLMTOK), sha256 `73a29baf97619a746a21232c403bf08af71a76e48b3b2cde6d64dab766083882` |
| server | our own `ollm serve` instance, aien-train main `0518c915dea370b3bffbb90d579b1daa5ba8b8f5` `native/omegallm/serve.om` (DRA-119), built with omega-mv `e5b32567` omc (sha256 `2c824805…029f`): `BUILD_OK 819664d5a2284189cd9baca67681675ed2b4685e19d1d976ce071b0f6fcaa5ea` |
| suite | aien-train `feat/ollm-accept-124` `83f4f1820cbc529846d1934232288c7c1a61758b`: PREREG.md `7133f654…4c9`, `suite/thresholds.tsv` `393200ab…1e9`, `suite/SHA256SUMS` checked, runner `accept` `8c4fb0cb9f8de0c27da96d29ad69ccf4601b703132d78cd68aaecfc3b97eb5bd` (built with omc `2c824805…`) |
| target repos | `textkit` fixture: `cq-s1` `af278fb303f77fd63bafe2048d68d2fc21c4180c`, `cq-s2` `c7d591ec376ede76903ebd37ea181f6c1c1c7c18` (fixed identity and dates, `fixture.txt`). Each DRA-124 item is committed as its own repository; the commit is in `items/<k>.base.txt` |
| tools | git 2.43.0, python3 3.12.3 (target-repository tests and hidden judges only), bwrap 0.9.0, jq 1.7 (suite filtering in `gate.sh`) |
| agent | `steps=6 maxtok=256`, temperature 0, seed 1 |

## No external model: the egress-blocked environment

Both REAL runs ran inside `sovereign-intelligence` `tests/egress/egress-env.sh` (DRA-188, branch
`hive/t_c0b0db35-egress` `c45e6888`). Its probe, `egress.om`, was built here with omc
`62775d2a…712b`. The launcher is `tests/coding_qual/egress-run.sh`, and its console output is
`20261107T023102Z-real/egress-console.log`. The environment has the following properties:

- Its own network namespace: the only interface is `lo` (`netns-if lo 127.0.0.1/8`).
- An emptied environment. The command saw only these variable names: `ACCEPT ACCEPT_OMC
  ACCEPT_SUITE CK CQ_MAXTOK CQ_MODEL_ID CQ_RUN_ROOT CQ_SCRATCH CQ_SRV CQ_STEPS EGRESS_BIN EGRESS_ENV
  EGRESS_PROBE HOME LANG LC_ALL MERGES OMEGA_OMC PATH PROBE_IP PWD TERM TMPDIR TZ`.
- `~/.hermes`, `~/.codex` and `~/.config/gh` are hidden.

The negative control is this connect to `api.openai.com` (`172.66.0.243:443`):

    OUTER ... CONNECT 172.66.0.243 443 REACHED        (host: the provider is reachable)
    INNER ... CONNECT 172.66.0.243 443 BLOCKED errno 101   (inside: ENETUNREACH)

The model server ran on port 18294 of that namespace and `cqa serve` on 18295. No host port was
bound. `cqa` refuses port 18091 and holds no model, provider or fallback other than
`127.0.0.1:MPORT`. Each `serve.log` (the `ollm serve` log, one `C status prompt completion
finish ms` line per request) is the complete list of inference requests: 31 in all, 16 answered
(200) and 15 refused (400 `context_length_exceeded`).

## SYNTHETIC (`20261107T022946Z-synthetic/`)

`cqfix` is a scripted fixture, not a model. All 13 cases passed (`cases.txt`; journals, diffs,
scripts, fixture logs and judge outputs are in `cases/`). Each of the six one-line defects in
`cqa.om` made its named case FAIL (`mutants.tsv`: every row is KILLED).

The serve-path controls ran through the frozen DRA-124 runner and `cqa serve`. Reference
answers passed 12/12 coding dev rows (`serve-ref.summary.tsv`) and garbage passed 0/12
(`serve-garbage.summary.tsv`), as required.

## REAL scenarios (`20261107T023102Z-real/`)

| case | asserted (PASS) | OBSERVED |
| --- | --- | --- |
| r1 cross-file change (S1) | terminal state, verifier PASS | state 4 FAILED (ctx at step 2), 0 writes, judge FAIL |
| r2 failing test (S2) | terminal state, verifier PASS | state 4 FAILED (ctx at step 2), 0 writes, judge FAIL |
| r3 cancel mid-task (S2) | cancel during inference 1: no effect, verifier PASS | state 2 CANCELLED, 0 writes, judge FAIL (bug kept, as required) |
| r4 resume after SIGKILL (S1) | client SIGKILLed during inference 1 (status 1009), restart asks once, no duplicate, verifier PASS | state 4 FAILED (ctx at step 2), 0 writes, judge FAIL |

The model did the same thing in all four cases. Its step-1 answer, for example r1's "I'm sorry,
I'm sorry. ...", held no action line. With that answer and the observation added to the history,
the step-2 prompt was 324 to 337 tokens, which exceeds T = 256. See `cases/<case>.transcript.txt`.
In r4 the killed request still ran to completion on the server, and the restart's request waited
for it (258119 ms). This matches the DRA-172 finding that main `0518c915` has no client-gone
check for non-streamed requests.

## DRA-124 coding rows (`20261107T024331Z-dra124/`)

The frozen runner (`accept run`, 2 workers, as pre-registered) sent the 12 own-written coding
dev rows (repos `ringbuf` and `semver`; these rows are excluded from training, so the model has
not seen them) to `cqa serve`. `accept sum` with the frozen `thresholds.tsv` gives
(`summary.tsv`):

| role | split | n | pass | Wilson 95% | reasons | gate |
| --- | --- | --- | --- | --- | --- | --- |
| coding | dev | 12 | 0 | [0, 0.2425] | ctx = 12 | report (not gated) |
| coding | test | 0 | 0 | — | — | **NOT_RUN** (private holdout, held by the evaluator) |

The pre-registered coding gate is the 28-row test split: Wilson lower bound >= 0.500, p95
<= 120 s, context >= 8192, and zero ctx rows. This checkpoint's window is T = 256 < 8192, and
every dev row ended `ctx`. On the dev rows the measured lower bound is 0 (Wolfram:
`Wilson(0, 12)` = [2.1e-17, 0.242494], z = 1.959963984540054). That is below 0.500, and the
`ctx` rows alone fail the gate's zero-ctx rule. The gated test line was not run here. The
evaluator can run it with `ACCEPT_HOLDOUT=<holdout> gate.sh dra124 PORT test` without handing
over the holdout. Even with 28/28 rows failing, the upper bound would be 0.1206 (Wolfram), so
this candidate cannot pass.

What the model did: 1 of 12 items (`cd-de-ringbuf-fix-rotate-0`) was refused at step 1, because
its issue prompt alone was 259 tokens. The other 11 got one answer each. One answer (item 2,
`cd-de-ringbuf-write-rotate`) began a line with `TEST`, and the harness ran the build check
(`tests: exit 0`). The other 10 answers held no action line. Each of these 11 then hit
`context_length_exceeded` at step 2. No item produced a WRITE, so every diff is empty.
Per-item `items/<k>.transcript.txt` and `<k>.item.txt` (suite id) carry the details.

Measured from `serve.log`, covering both REAL runs (computed by Wolfram):

- 16 answered requests generated 540 tokens in 2362186 ms (39.37 min): 4.374 s per token on
  average, ranging from 4.171 to 4.732.
- The largest context used was 256 tokens, the whole window.

## Notes and deviations

- `20261107T024331Z-dra124/transcript.log` records `dirty=1`. The one path is the untracked
  `tests/coding_qual/transcript.sh` (the journal renderer, added during the run and committed
  with this evidence). No gate step executes it.
- In both REAL runs, `serve.log` is the full `ollm serve` log for both gates. `egress-run.sh`
  copied it over the dra124 run's `cqa serve` stdout, so the per-item `CQA ...` summary lines of
  that run were lost. The per-item journals hold the same facts, and the script now writes
  `model-serve.log` instead.
- `*.transcript.txt` files are derived by `tests/coding_qual/transcript.sh` from the journals,
  which stay the record.
- Independent patch verdicts come from the Spark `reviewer` profile (Codex gpt-6-astra, medium,
  read-only brief `REVIEW-20261107.brief.sh`). Its output is `REVIEW-20261107.txt`: all 16 REAL
  tasks are REJECT (no patch produced; item 2 ran only the build check), and the signed line is
  `VERDICT DRA-184 accepted=0/16 external_fallback=none model=gpt-6-astra provider=openai-codex
  reasoning=medium session=local-2a4f37683f228e94163d4ca05da919a4e19b8b9f96a864bbcea1b8be3aa8d60f`.
  It reviewed checkout `d5391a93` and assessed the recorded evidence; it did not rerun anything.
  The first attempt failed before any message was sent (`invalid_params`), because the worker's
  `HERMES_*` environment leaked into the child `hermes`. The script now starts it with `env -i`.
