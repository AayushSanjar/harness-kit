# Research

Background research for harness-kit, one topic folder each. A folder's `00-decision.md` (or its `README.md`, for the first topic) holds its conclusion; the other files hold the evidence, and each folder's `sources.csv` lists what it cites.

| Folder | Date | Status | Conclusion |
|---|---|---|---|
| `initial-harness/` | 26 September 2026 | Current, except the plugin folder layout proposed in `04-replication.md` Part C, superseded by what was built (`repo-structure-and-docs/01-repo-structure.md`, finding 3) | A plugin cannot carry the boundary itself, so the kit is a generic plugin plus project-owned settings, agent copies and CI checks, and CI must load the plugin explicitly and check that it loaded. (`README.md`) |
| `design/` | 27 September 2026 | Current | Judge a user interface in three layers (universal quality, platform conformance, taste and purpose), with scripts owning everything measurable and the AI judge never asked to see geometry. (`01-benchmark.md`; this folder has no `00-decision.md`) |
| `ci-process-overview/` | 30 September 2026 | Current, as a working description of CI at v0.20.0; its full-replay time of about 25 minutes predates part B's speed-up | For a normal change, CI replays no faults on the branch before it merges; the faults are replayed only on `main`, after the merge. (`harness-kit-ci-process.md`; this folder has one file) |
| `ci-and-github/` | 30 September 2026 | Current; its 25-minute replay figure is corrected in its own `07-independent-review.md` | Keep how releases work, but have `release.sh` run the full fault replay on the exact commit and wait for it before `main` moves. (`00-decision.md`) |
| `repo-structure-and-docs/` | 30 September 2026 | Current, except its advice to leave the first topic's files where they were, superseded by this folder layout | Generate and check, or delete, every list, number and index a document shares with the code; give each script one test file; let AI gardening report, never merge. (`00-decision.md`) |
| `harness-backlog/` | 30 September 2026 | Current | harness-kit scores 4.4 out of 10; six moves reach about 7.5 to 8: the plan and backlog in the repository and on GitHub Issues, fault replay before `main` moves, harness-kit under its own plugin, sandbox and permission rules, evals of the AI parts, and simplifying. (`00-decision.md`) |

**Former paths.** Until 30 September 2026 the first topic's files were at the top of this folder: `research/<file>` is now `research/initial-harness/<file>`, for `README.md`, `sources.csv` and `00-glossary.md` to `07-open-questions.md`. The append-only defect log (`.harness/defects.tsv`) still names `research/02-claude-features.md`; read it as `research/initial-harness/02-claude-features.md`.
