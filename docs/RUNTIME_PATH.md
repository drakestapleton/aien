# Runtime path acceptance harness (DRA-172)

Status: IN_REVIEW. Qualification: SYNTHETIC PASS (interfaces only). REAL: see the newest
`evidence/runtime-path/*-real/` run, or NOT_RUN when none exists.

One request goes through the whole runtime path:

    request -> own-model inference -> typed tool call (schema-checked) -> artifact on disk
            -> independent verification -> durable task and memory state -> kill + restart
            -> recovery with no duplicate effect

Everything new is seeded Omega under `src/runtime_path/`, compiled with omega-mv
`f4df82394e35893dcf1354dda69a2fe028d94bc1` `seed/out/omc` (sha256
`3ad9f10f64309e7acf8a725082b28e23a2a4aeb07e98322fb4dc0fcd8fc93194`). The JSON and HTTP units
are vendored unmodified from the same commit; `src/runtime_path/vendor/PIN` lists their sha256
and `tests/runtime_path/build.sh` refuses to compile when any pin differs (exit 3, NOT_RUN).

## Programs

| program | source | role |
| --- | --- | --- |
| `rpath` | `rpath.om` | the runtime: journal, memory, inference client, typed tools, recovery |
| `rpfix` | `rpfix.om` | SYNTHETIC protocol fixture: answers like `aien-train` `serve.om` (DRA-119), is not a model |
| `rpver` | `rpver.om` | independent verifier: re-derives every outcome from the journal and checks the disk |
| `rpcase` | `rpcase.om` | scenario conductor: runs the three above as processes, kills and restarts `rpath` |

`rpcom.om` holds only byte, number and file mechanism shared by all four.

### rpath

`rpath init|submit|cancel|remember|run|status DIR ...` keeps all state in DIR:

- `journal.log`, append-only and fsync'd, one record per line:
  `Q` request, `X` cancel, `I` inference started (attempt, memory generation),
  `R` inference result (tool name, arguments, content, all hex), `N` inference failure,
  `A` schema verdict, `E` effect intent, `D` effect done (length, FNV-1a 64, recovered flag),
  `U` outcome unknown, `T` terminal state.
- `memory.log`, append-only: `M key value`. The effective memory is the last record of each key;
  it goes into the system prompt of every inference. A correction is a later record, and the
  memory generation (the record count) is stored on every `I` and `R`.
- `out/<id>-<name>` artifacts and `sink/notify.log`, the write-only notify channel.

`rpath run DIR PORT` sends `POST /v1/chat/completions` to `127.0.0.1:PORT` with two typed tools:

- `write_artifact {name, text}`: both required strings, no other member. `name` is 1 to 64 bytes of
  `[a-z0-9._-]` and must not start with `.`. `text` is 1 to 4096 bytes with no control byte
  except tab and newline. The effect is idempotent: a temporary file is written and fsync'd, then
  renamed with `RENAME_NOREPLACE`, so the artifact is either absent or complete. Recovery finds an
  existing artifact, hashes it and records `D ... recovered=1`; it never writes twice.
- `notify {channel, message}`: `channel` must be `ops`, and `message` is 1 to 256 bytes. The
  effect is one line in a sink the runtime never reads back. A notify that was interrupted
  between `E` and `D` is recorded `U` with state UNKNOWN and is never retried.

Recovery rules, applied on every `run`:

- A torn last journal line is cut off before anything else.
- `T` present: the request is finished.
- `X` present before any `E`: CANCELLED, with no effect.
- `E` without `D`: write_artifact is completed or recovered. notify becomes UNKNOWN.
- A rejected `A`: REJECTED, with no effect.
- An `R` whose memory generation is not the current one (stale memory) or older than the last
  `I`: the result is discarded and the model is asked again.
- Otherwise the `R` is schema-checked (`A`), then `E`, effect, `D`, `T DONE`.

Terminal states are 1 DONE, 2 CANCELLED, 3 REJECTED, 4 UNKNOWN, 5 NOTOOL (the model answered
without a tool call) and 6 FAILED (three inference failures).

`crash=I|R|E|W` makes `rpath` exit 77 right after that step is durable. W means the effect was
performed but `D` is not yet recorded. The conductor also uses real SIGKILL while an inference is
in flight.

### rpver

`rpver DIR` uses no `rpath` code. It checks the following:

- Every request has exactly one `T` and at most one `E`, `D` and `U`.
- Every `E` follows an accepted `A`.
- DONE write_artifact: the file equals the `text` argument of the last `R`, and its length and
  FNV-1a 64 equal those on the `D`.
- DONE notify: exactly one sink line, matching the arguments.
- REJECTED, CANCELLED, NOTOOL and FAILED: no `E`, no `D`, no artifact and no sink line.
- UNKNOWN: notify only, `E` and `U` present, no `D`, at most one sink line.
- No temporary file is left in `out/`, and no file in `out/` lacks a DONE record.

## Cases

`bash tests/runtime_path/gate.sh synthetic` (label SYNTHETIC) runs these cases:

| case | what happens | what must hold |
| --- | --- | --- |
| c1 happy-path | request -> tool -> artifact | DONE, artifact `unit=celsius value=21`, rpver PASS |
| c2 crash-after-intent-restart | exit after `E` | no artifact before restart; DONE after, one `D` |
| c3 crash-after-effect-restart | exit after the rename, before `D` | restart recovers; artifact inode and mtime unchanged |
| c4 sigkill-during-inference-restart | SIGKILL while the fixture holds the answer | restart asks again (attempt 2), DONE once |
| c5 cancel-during-inference | `cancel` while the answer is in flight | CANCELLED, no artifact, a second run adds no record |
| c6 cancel-kill-restart | cancel, SIGKILL, restart | CANCELLED, no new inference (attempts 1) |
| c7 stale-memory-correction-restart | result made with `unit=fahrenheit`, exit, owner corrects to `celsius`, restart | stale result discarded, re-asked with generation 2, artifact says celsius; a later request in a new process also says celsius |
| c8 invalid-tool-arguments | `name ../escape.txt`, `text` a number | REJECTED, no artifact |
| c9 uncertain-outcome-unknown | exit after the notify line, before `D` | UNKNOWN, still exactly one sink line after two more runs, journal unchanged by the third |
| c10 notify-happy-path | notify | DONE, one matching sink line |
| c11 no-tool-call | plain answer | NOTOOL |
| c12 verifier-negative-artifact-tamper | one byte appended to a good artifact | rpver FAIL |
| c13 verifier-negative-stray-file | a file no record accounts for | rpver FAIL |
| c14 torn-journal-tail-restart | exit after effect, torn `D` appended | tail cut, one well-formed `D`, DONE |

Planted defects (`tests/runtime_path/mutants.tsv`) are each a one-line change to `rpath.om`, and
each must make its named case FAIL. They are: re-sending an interrupted notify, ignoring a schema
refusal, reusing a stale-memory result, acting on a cancelled request, rewriting an existing
artifact, and not cutting a torn journal tail. The gate passes only when the baseline passes every
case and every mutant is killed.

`bash tests/runtime_path/gate.sh real PORT` (label REAL) points the same runtime at a model
server already listening on `127.0.0.1:PORT`, such as `aien-train` `serve.om` (DRA-119) with an own
checkpoint. It is never port 18091, and the gate never starts or stops the server.
Cases r1 to r4 assert the invariants that do not depend on what the model chooses:
recovery, no duplicate effect, cancellation, a stale result re-asked after a memory correction, and
rpver PASS. Its `OBSERVED` lines record what the model actually did. `RP_MODEL_ID` carries the
checkpoint sha256, tokenizer id and server commit into the receipt.

## Limits

- SYNTHETIC proves interfaces, journal and recovery only. It says nothing about model quality.
- One process runs a directory at a time. Two concurrent `rpath run` on one DIR are not supported
  (no lock yet).
- The journal is read whole into 1 MiB, and requests are capped at 64 per directory.
- The shell scripts under `tests/runtime_path/` are build and evidence adapters under aien#22
  (shell retirement). All runtime, fixture, verification and scenario logic is `.om`.
