# harness-kit

A reusable Claude Code harness, packaged as a plugin and served from this repository as its own marketplace.
The plugin lives in `plugins/harness-kit/`; `tests/validate.sh` checks it and runs in CI.
A release is made by the person, on the branch, with `plugins/harness-kit/scripts/release.sh v<version>`: it runs the check, pushes the branch, waits for CI, then fast-forwards `main` and pushes it with the tag. When gh cannot read the CI result (after 3 tries, 10 seconds apart), it stops with "CI result unknown" and pushes nothing to `main`.
CI runs the fault replays (`plugins/harness-kit/scripts/replay-faults.sh`, every entry of `.harness/mutations.tsv`) on each push to main, as one baseline job and 8 shard jobs side by side, judged together; to run them on a branch: `gh workflow run validate.yml --ref <branch>`.
Background research is in `research/`.
