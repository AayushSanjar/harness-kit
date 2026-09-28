# harness-kit

A reusable Claude Code harness, packaged as a plugin and served from this repository as its own marketplace.
The plugin lives in `plugins/harness-kit/`; `tests/validate.sh` checks it and runs in CI.
A release is made by the person, on the branch, with `plugins/harness-kit/scripts/release.sh v<version>`: it runs the check, pushes the branch, waits for CI, then fast-forwards `main` and pushes it with the tag.
Background research is in `research/`.
