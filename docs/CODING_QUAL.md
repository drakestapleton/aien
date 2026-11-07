# Unseen-repository coding qualification harness (DRA-184)

Status: IN_REVIEW. Results and labels are in `evidence/coding-qual/README.md`:
SYNTHETIC PASS (13 cases, 6/6 mutants, serve-path controls); REAL scenario invariants PASS (4/4);
DRA-124 coding dev rows 0/12 (ctx 12) with the rung-10 ck60000 candidate; gated test line NOT_RUN.

The harness runs one coding path end to end, with the own Omega LLM as the only model:

    unfamiliar issue -> repository inspection (LIST, READ) -> patch (WRITE, owned files only)
        -> build/test (TEST, and after every WRITE) -> DONE -> hidden-test judge -> reviewer verdict

All harness logic is seeded Omega under `src/coding_qual/`, built by `tests/coding_qual/build.sh`
with omega-mv `f4df82394e35893dcf1354dda69a2fe028d94bc1` `seed/out/omc` (sha256
`3ad9f10f…3194`) and the JSON/HTTP units vendored for DRA-172 (`src/runtime_path/vendor/PIN`).
A different compiler or a changed vendored unit exits 3 (NOT_RUN) before anything compiles.

## Programs

| program | source | role |
| --- | --- | --- |
| `cqa` | `cqa.om` | the coding agent runtime: task directory, journal, inference client, actions, effects, recovery; `serve` mode is the endpoint for the frozen DRA-124 suite runner |
| `cqfix` | `cqfix.om` | SYNTHETIC scripted protocol fixture in the shape of aien-train `serve.om` answers; not a model |
| `cqcase` | `cqcase.om` | scenario conductor, independent verifier and hidden-test judge driver |

### The agent (`cqa task DIR MPORT [steps=N] [maxtok=N]`)

A task directory holds `issue.txt` (the unfamiliar issue), `own.txt` (the files the agent may
change), `test.txt` (the build/test command, one argv entry per line) and `repo/` (an isolated
`git worktree` of the target repository at its pinned commit). Each step is one
`POST /v1/chat/completions` to `127.0.0.1:MPORT` with temperature 0 and seed 1. The request
carries the system protocol, the issue, the owned file list and the replayed history of earlier
steps. Port 18091 is refused, and no other model, provider or fallback exists in the program.

aien-train `serve.om` (DRA-119) ignores `tools` ("this model never calls tools"). The agent
therefore speaks a text protocol. The first reply line that starts with `LIST`, `READ <path>`,
`WRITE <path>` (followed by one fenced block holding the whole new file), `TEST` or `DONE` is
the action. Paths must be relative, use `[A-Za-z0-9._/-]` only, and contain no `..`, `//` or
`.git`. A WRITE to a path that is not a line of `own.txt` is refused, and the refusal is told to
the model. Tests run in `bwrap --unshare-all` (no network, read-only `/`, private `/tmp`,
read-only repo, 20 s limit).

`journal.log` is the checkpoint. It is append-only and fsync'd, with one line per record:
`I` inference started, `R` answer (tokens, ms, hex content), `N` inference failure (1 ctx,
2 http, 3 conn, 4 json), `A` parsed action, `E` write intent, `D` write done (length,
FNV-1a 64), `O` observation, `X` cancel, `T` terminal (1 DONE, 2 CANCELLED, 3 BUDGET, 4 FAILED).
Every run applies these recovery rules:

- A torn last line is cut.
- A step with an `R` is never asked again. Its answer is replayed, so the next request is
  byte-identical to the one that was interrupted.
- An `X` before a step's `E` cancels the step with no effect.
- An `E` without its `D` repeats the idempotent full-file write (temporary file, fsync,
  rename) once.

`cqa cancel DIR` appends `X`.

### The DRA-124 endpoint (`cqa serve PORT MPORT WORK`)

The frozen DRA-124 suite (aien-train `feat/ollm-accept-124` `83f4f182`, PREREG.md sha256
`7133f654…4c9`, `suite/thresholds.tsv` sha256 `393200ab…1e9`, runner `accept` `8c4fb0cb…`) is
not modified. Its runner sends each coding item to `cqa serve`. The serve endpoint handles one
item as follows:

1. It writes the item's files into a fresh git repository `WORK/<k>/repo` and commits them as
   `base.txt`.
2. It sets the issue to the item's `Task:` paragraph and `own.txt` to the target named in the
   item. Its build check compiles every owned file in the sandbox. The item's tests stay hidden,
   because they are the suite's judge.
3. It runs the same agent loop against the own model.
4. It answers with the final target file in one python block, which the suite's `exec repo`
   checker judges with its hidden driver and nonce.

A context failure is answered `400 context_length_exceeded`, as `serve.om` does. The suite then
records reason `ctx`. Scoring is `accept sum` with the frozen `thresholds.tsv`: Wilson 95% lower
bound, nearest-rank p95 latency, and context window, all computed by `accept.om`, not by this
harness. The coding gate is the private test split (n = 28, Wilson lower bound >= 0.500,
p95 <= 120 s, context >= 8192). The split is held by the evaluator (lead ownmodel). This harness
runs the public own-written dev rows (12 items, repos ringbuf and semver, excluded from
training). It gives the evaluator `gate.sh dra124 PORT test` with `ACCEPT_HOLDOUT` to run the
test rows on the evaluator's side.

### Cases (`cqcase`)

SYNTHETIC (`gate.sh synthetic`): scripted fixture, which proves interfaces only.

| case | what must hold |
| --- | --- |
| c1 cross-file-change | rename across `norm.py` and `words.py`: DONE, 2 writes, verifier PASS, hidden judge PASS |
| c2 failing-test-fixed | first TEST shows `exit 1`, fix, TEST shows `exit 0`, judge PASS |
| c3 cancel-mid-task | cancel while inference 2 is in flight: CANCELLED, no `E`, rerun adds no record, judge FAIL (bug kept) |
| c4 resume-after-sigkill | SIGKILL during inference 3, restart: step 2's write not repeated, exactly one re-sent request whose body equals the killed one, DONE, judge PASS |
| c5 / c6 crash-after-intent / -after-write | exit 77 between `E` and the write, or between the write and `D`: one `D` after resume, no re-ask, judge PASS |
| c7 ownership-refusal | WRITE to `tests/test_words.py` refused (`A 1 3 2`), no effect, judge FAIL |
| c8 context-exceeded | 400 context_length_exceeded: FAILED with reason 1, no effect |
| c9 no-action-budget | replies with no action: 3 "No action found" observations, BUDGET |
| c10 path-escape-refusal | `../`, absolute, `.git` paths refused (4 refusals), no effect |
| c11 judge-negative-control | both hidden judges FAIL on unmodified worktrees |
| c12 verifier-negative-control | one appended byte, then one stray file: verifier FAIL each time |
| c13 torn-journal-tail-resume | partial `D` line cut on restart, one well-formed `D`, judge PASS |

Each planted one-line defect in `tests/coding_qual/mutants.tsv` must make its named case FAIL:
no ownership check, cancel ignored after inference, completed steps asked again, a done write
repeated, no torn-tail cut, and `..` paths accepted.

The gate then runs the serve-path controls through the frozen runner. Reference answers through
`cqa serve` must pass 12/12 coding dev rows, and garbage must pass 0/12.

REAL (`gate.sh real PORT`): the same two issues against the own model. These invariants do not
depend on what the model chooses: a terminal state is reached, the verifier passes, cancel
during inference produces no effect, and after a SIGKILL during inference the restart asks once
more and produces no duplicate effect. `OBSERVED` lines record the state, the number of writes
and answers, and the hidden judge result.

`tests/coding_qual/egress-run.sh` runs both REAL modes inside the DRA-188 egress-blocked
environment, with our own `ollm serve` on a port of that private namespace.

## Limits

- SYNTHETIC proves interfaces, journal, recovery and verification. It says nothing about model
  quality.
- One process runs a task directory at a time. The journal is read whole into 1 MiB, and there
  are at most 64 steps.
- `serve` answers one connection at a time. The suite's second worker waits in the listen
  backlog, and that wait is counted in its latency, as it would be in production.
- The shell under `tests/coding_qual/` is a build and wiring adapter under aien#22 (shell
  retirement). Agent, fixture, verifier, judge driver and conductor are `.om`. The hidden judges
  are Python because the target repositories are Python.
