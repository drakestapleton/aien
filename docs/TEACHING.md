# How it works: one objective through the microjob admission kernel

This lesson follows one synthetic objective through the only evaluation flow implemented on `main`: the seeded Omega admission kernel for Aien #13 ([docs/GOAL_MICROJOBS.md](GOAL_MICROJOBS.md)). It covers the expected verdict, the refusals, and what the evidence does not show. The B0 contract, the source map, `inventory/` and `guard/` are still planned (see [PHASES.md](PHASES.md) and [PLAN.md](PLAN.md)). This lesson does not stand in for them.

## The problem

Aien keeps one persistent objective across many small jobs, some run by a model. A planner or model that reports its own success cannot be trusted to decide what counts as done. The design separates **proposing** from **admitting**: workers and models append events, and one small deterministic program decides from the plan and the journal alone which events are admitted.

## The mechanism

- **Identity, memory and authority stay outside.** The kernel holds no identity and writes no Cortex memory or runtime authority. The journal is the local replay log of one objective, not a second memory store (ADR 0022 owns durable memory; the Cortex writer does not exist yet). The boundary table is in [GOAL_MICROJOBS.md § Boundary](GOAL_MICROJOBS.md#boundary).
- **The kernel** is [`src/goal_microjobs/kernel.om`](../src/goal_microjobs/kernel.om), compiled by [`scripts/goal_microjobs/build.sh`](../scripts/goal_microjobs/build.sh) with the pinned seeded compiler. It reads a header record, node records and event records as decimal words on stdin. It prints the derived state (`100`/`101`/`102`/`103` lines) or refuses with `199 seq code` and exits with that code.
- **Admission rules** are in the event table of [GOAL_MICROJOBS.md § Records](GOAL_MICROJOBS.md#records-local-replay-abi-canonical-adapter-below). For example: a VERIFY is admitted only from the node's named verifier, never from the worker, and only when its digest equals the result. A DISPATCH is admitted only when every dependency is done and the budget can fund the reservation.
- **The gate** [`tests/goal_microjobs/gate.sh`](../tests/goal_microjobs/gate.sh) runs the 12-node synthetic acceptance objective (concurrent nodes, a model failure with retry, a SIGKILL'd writer, an owner correction that resets exactly nodes 3, 7–12). It then rebuilds the kernel nine times, each with one rule deliberately broken, and requires every broken kernel to be caught.

### Why these choices

- **Seeded `.om`, one compiler pin.** The decision logic is first-party Omega, built by a compiler that rebuilds from seed-0. The build refuses any other compiler digest, so a replay cannot pass with a different compiler.
- **Refusal codes, not booleans.** Each rule has its own exit code (33 wrong state, 34 stale generation, 39 wrong verifier, …), so a mutant that drops one rule shows up as a wrong code.
- **Limitation, recorded at the time:** the historical compiler was an untracked build artifact, so the 2026-10-22 recipe ended `BLOCKED` on a fresh clone ([GOAL_MICROJOBS.md § Reproduce](GOAL_MICROJOBS.md#reproduce)). The replay below rebuilds it from seed instead.

## Replay (offline, no model, no GPU)

Requirements: Linux aarch64 (the compiler emits arm64 ELF), POSIX `sh`, `bash`, `git`, `python3`, `sha256sum`. No network after cloning, no account, no model.

```sh
set -eu
git clone https://github.com/aien-dev/aien.git aien-lesson
git clone https://github.com/aien-dev/omega-mv.git omega-seed
git -C aien-lesson checkout --detach c149760e8722ed943abcc5e3c7a33e2065b4036c
# 1. Rebuild the historical compiler from seed-0 at the commit that published it.
git -C omega-seed worktree add --detach ../omega-29b1 29b12760f4c962606411d6bf25032aedef063301
(cd omega-29b1 && rm seed/out/omc && sh seed/omega-from-seed.sh)   # ends RC=0
sha256sum omega-29b1/seed/out/omc   # 191b776ef98821597c3e30655da6d680a9b66edbc9ceaca3c39c61ea6df098e9
# 2. Lay it out where build.sh expects it, under the pinned Omega checkout.
git -C omega-seed worktree add --detach ../omega-c434 c434565c67552c0b01df2d7f76c1a04287c70560
T=omega-c434/build/L574/toolchain
mkdir -p "$T/build/bootstrap" "$T/seed/omc" "$T/tools"
cp omega-29b1/seed/out/omc "$T/build/bootstrap/omc"
cp omega-29b1/seed/omc/omc.om "$T/seed/omc/omc.om"   # 8608fa11f6a2cf1c50db22d871eef16b00d5bc719bc1a222cc3e456984ac5ebf
git clone https://github.com/aien-dev/omega-bridge.git
git -C omega-bridge show e461b7a:tools/verify-elf.sh > "$T/tools/verify-elf.sh"   # afe24b29f105241f268fbaf3bfdd8e010c790a13b8f807de1263f92aacca76cd
# 3. Run the gate, writing outside the checkout.
OMEGA_WORKTREE="$PWD/omega-c434" GM_RUN_ROOT="$PWD/run" bash aien-lesson/tests/goal_microjobs/gate.sh
```

**Expected:** exit 0 and one line `PASS <run>/offline-<time>/receipt.json checks=158`. The receipt records `verdict PASS`, `compiler_sha256 191b776e…`, `omega_source_commit c434565c…`, `mutants_caught 9`, `model_inference NOT_RUN`. `mutations.tsv` lists each broken rule, the probe, the refusal code a correct kernel gives, and the code the broken kernel gave instead.

**Refusal cases:**
- Inside the gate, the nine mutants (wrong verifier, self-reported success, dispatch before dependencies, stale generation, duplicate effect, model-call budget, double cancel, plan cycle, privacy-owner change) are each caught.
- At the edge, pointing `OMEGA_WORKTREE` at any other Omega commit exits 3 with `BLOCKED: Omega checkout must be c434565c…`. A missing or different compiler also exits 3, before anything is compiled.

The 2026-11-05 run of exactly this recipe is recorded in [teaching-replay-2026-11-05.txt](teaching-replay-2026-11-05.txt).

## What this does and does not establish

The receipt establishes the following, offline on synthetic fixtures at the pinned revisions: the kernel admits the acceptance objective's journal and every one of the nine rule mutants changes an observed refusal. It does **not** establish model inference, a Cortex write or restart, routing comparison, a B0 qualification, a phase completion, or any GPU or hardware behaviour. Those remain NOT_RUN, as [GOAL_MICROJOBS.md](GOAL_MICROJOBS.md) states. The receipt is unsigned.

Upstream components: the seed chain and compiler are from [aien-dev/omega-mv](https://github.com/aien-dev/omega-mv) (commit `29b12760`, "omc born from seed-0"); `verify-elf.sh` is from [aien-dev/omega-bridge](https://github.com/aien-dev/omega-bridge); the microjob wire format follows the MJB1 draft in aien-protocols-mv#50.
