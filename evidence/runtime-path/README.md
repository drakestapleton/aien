# DRA-172 runtime-path receipts

Runs produced by `tests/runtime_path/gate.sh` on the Spark (aarch64), on CPU cores 10-11 under
`flock ~/handoffs/hive/queen/pool-10-11.lock`, `nice -n 10`. No GPU was used, and port 18091 was
never used. Compiler: omega-mv `f4df8239` `seed/out/omc`, sha256 `3ad9f10f…3194`. Each
`transcript.log` records the repository commit, compiler hash and host.

| run | label | tree | result |
| --- | --- | --- | --- |
| `20261107T002534Z-synthetic/` | SYNTHETIC | `f53db121`, clean | `GATE SYNTHETIC PASS cases=14 mutants=6/6` |
| `20261107T005448Z-real/` | REAL | `5a562a83`, clean | `GATE REAL PASS`, `RPCASE REAL PASS cases=4` |

## SYNTHETIC

`rpfix` is a protocol fixture, not a model. It proves interfaces, journal, recovery and
verification only. `cases.txt` has one line per case (c1 to c14), and `cases/` holds every
journal, memory log, sink, artifact and verifier output. `mutants.tsv` records the six one-line
planted defects in `rpath.om`. Each made its named case FAIL (`KILLED`).

## REAL

The server was our own instance of `ollm serve` from aien-train main
`0518c915dea370b3bffbb90d579b1daa5ba8b8f5`. It was rebuilt here with omega-mv `e5b32567` omc
(`2c824805…029f`), giving `BUILD_OK 819664d5a2284189cd9baca67681675ed2b4685e19d1d976ce071b0f6fcaa5ea`,
the same binary as DRA-188's receipts. It served the own Omega LLM rung-10 `ck60000`, sha256
`a53ced7265818c8f6197449315e9ca4082721665022fec4f81d4538e8d6c2d0f` (T = 256, d = 384, 12 layers;
header read from the file). The tokenizer was `merges4096`, sha256
`73a29baf97619a746a21232c403bf08af71a76e48b3b2cde6d64dab766083882`. The server ran inside a
private network namespace (`bwrap --unshare-net`, only `lo`) on port 18293 of that namespace,
so no host port was bound. It was started and stopped by this lane. The ownmodel lease request
(BOARD 00:24:22Z) got no answer, so this followed the pattern DRA-188 announced. The decision is
in the hive DECISIONS log.

| case | asserted (PASS) | OBSERVED state E D U attempts |
| --- | --- | --- |
| r1 real-request | terminal state, rpver PASS | 5 (NOTOOL) 0 0 0 1 |
| r2 real-sigkill-during-inference-restart | client SIGKILLed while the request was in flight (status 1009), restart re-asks, rpver PASS | 5 0 0 0 2 |
| r3 real-stale-memory-correction-restart | result recorded with memory generation 1 (`unit=fahrenheit`), memory corrected, restart re-asks at generation 2 (`R 1 2 2`), rpver PASS | 5 0 0 0 2 |
| r4 real-cancel-during-inference | cancel recorded while the model was generating; the answer arrived after it and no effect followed (CANCELLED), rpver PASS | 2 0 0 0 1 |

What the real model did: in all five answered results, `ck60000` produced plain text with no
`<tool_call>` block. The `R` records are in `cases/r*.journal.log`, content in hex. So with REAL
inference, the runtime recorded NOTOOL. The typed tool → artifact → verify leg ran only in
SYNTHETIC. Its REAL run is **NOT_RUN**. It needs an own checkpoint that emits `serve.om`
`<tool_call>` blocks, which means DRA-123 (shared chat/tool template) plus tool-use training,
owner ownmodel.

The memory correction did change model behaviour. In r3 the generation-1 answer (fahrenheit in
the prompt) and the generation-2 answer (celsius) differ (`R 1 1 1` vs `R 1 2 2` content), under
greedy decoding.

Server log (`serve.log`, one `C status prompt_tokens completion_tokens finish ms` line per
request) has six lines, one per request sent. `prompt_tokens` was 89 or 90, so both tool schemas fit in
T = 256. Five answers ran to the 64-token limit (finish 2) and one stopped at 17 (finish 1). Per-request
times were 270736, 408586, 429402, 107284, 492697 and 262705 ms, 1971410 ms in total (32.86 min,
Wolfram). The second line is the request whose client was SIGKILLed in r2. The server still
generated all 64 tokens and logged 200 for a client that had gone. Source check: main `0518c915`
`serve.om` has no client-gone check for non-streamed answers. It notices a vanished client only
when a stream chunk cannot be sent (line 795). aien-train#72 (`9d373fc`, not merged when this ran)
adds `svgone`, a non-blocking peek between tokens that stops the generation with 499. Rerun r2 on
a #72 build to see that change. Reported to ownmodel.
