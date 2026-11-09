# Instructions for agents working in aien-dev/aien

Read before any edit, in this order:

1. `docs/MISSION.md`, `docs/PHASES.md` and `docs/PLAN.md` (mission, current phase ledger and planned streams).
2. aien-architecture-mv: `PLAN_AUTHORITY.md`, `CURRENT_EXECUTION_PLAN.md`, accepted ADR 0035 (Aien boundary), ADR 0022 (Cortex owner), ADR 0024 (Rust scaffolding, Omega destination).
3. `docs/PLAN.md` identifies the owners of planned `docs/B0_ACCEPTANCE_CONTRACT.md` and `docs/SOURCE_MAP.md`. Neither file is on `main` yet. Read them only when they land; do not treat a branch or plan as an accepted contract or source map.

Rules:

- My stack only: Rust now, Omega as destination. No Python, no C++, no CUDA, no third-party inference engine. Outside tools are yardsticks or test oracles, never shipped.
- Raw conversations, credentials, weights and private training samples never enter this repository, in any branch, issue, PR or CI log. Publish synthetic fixtures and access-controlled references (host, path, digest, count). The source-control guard planned for `guard/` is not on `main`; check this boundary yourself rather than relying on an automatic guard.
- Drake's words are preserved as written, including profanity. Style or frustration is never turned into a claim about feelings, permission or correctness.
- Every number names its source: a file under `evidence/`, a receipt, or the arithmetic. No estimates without evidence.
- Status words are separate from verdicts: progress is PROPOSED, SCOPED, ACTIVE, IN_REVIEW, COMPLETE; qualification is PASS, FAIL, INCONCLUSIVE, NOT_RUN. A closed issue with waived or NOT_RUN criteria is not complete. The programme close guard is planned, not running on `main`; check phase and prerequisite evidence manually until it exists.
- Phase numbers (P0 to P7) are sequence, not priority. Model generation ids are recorded separately from Aien's identity; a checkpoint is not Aien.
- One owner per directory; see `docs/PLAN.md`. Push branches and write a READY line for the PR desk; do not open or merge pull requests yourself.
- Git identity for commits made on Drake's behalf: Drake Stapleton <drake@aienos.com>.
