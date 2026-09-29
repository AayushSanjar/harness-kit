#!/usr/bin/env bash
# Tests for plugins/harness-kit/scripts/background-guard.mjs, the PreToolUse hook that
# refuses a background Bash command not wrapped in the time-limit helper. Each call is given
# to the hook as hook input, never run. Prints one PASS or FAIL line per case and exits
# non-zero if any fail.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$(cd "$ROOT/plugins/harness-kit/scripts" && pwd)"
GUARD="$SCRIPTS/background-guard.mjs"
TL="$SCRIPTS/time-limit.mjs"
failures=0

result() {
  local label="$1" ok="$2" detail="$3"
  if [ "$ok" = yes ]; then
    echo "PASS $label"
  else
    echo "FAIL $label"
    sed 's/^/    /' <<<"$detail"
    failures=$((failures + 1))
  fi
}

# decide COMMAND [fg]: the hook's decision for a Bash call of COMMAND, in the background
# unless "fg": "allow" (nothing printed, exit 0), or "deny: " and the reason.
decide() {
  local out status
  out="$(node -e '
    const [command, where] = process.argv.slice(1);
    console.log(JSON.stringify({ tool_name: "Bash", tool_input: { command, run_in_background: where !== "fg" } }));
  ' "$1" "${2:-bg}" | node "$GUARD")"
  status=$?
  if [ "$status" -ne 0 ]; then
    echo "exit $status: $out"
  elif [ -z "$out" ]; then
    echo allow
  else
    printf 'deny: %s\n' "$(node -e 'console.log(JSON.parse(process.argv[1]).hookSpecificOutput.permissionDecisionReason)' "$out")"
  fi
}

# 1. A background command that is not wrapped is denied, with the wrapped form to use and
# the command named.
got="$(decide 'bash tests/validate.sh --skip-reviewed')"
if grep -qxF "deny: BLOCKED by harness-kit background-guard: a background command must run under a time limit. Run it as: node $TL run --limit <seconds> -- <command>" <<<"$got" &&
  grep -qxF 'Not wrapped: `bash tests/validate.sh --skip-reviewed`' <<<"$got"; then
  result "background-guard: a background Bash command that is not wrapped in the time-limit helper is denied, with the wrapped form to use" yes ""
else
  result "background-guard: a background Bash command that is not wrapped in the time-limit helper is denied, with the wrapped form to use" no "$got"
fi

# 2. Wrapped in the helper (by path, through a variable, with a limit's name, --name,
# --merge, an assignment in front, sh -c for a cd), it is allowed; a foreground command is
# not read at all.
problems=""
for command in \
  "node $TL run --limit 60 -- sleep 30" \
  'node "$CLAUDE_PLUGIN_ROOT/scripts/time-limit.mjs" run --limit check --name validate --merge -- bash tests/validate.sh' \
  "X=1 node plugins/harness-kit/scripts/time-limit.mjs run --limit 1.5 -- sh -c 'cd /tmp && make | tee log'" \
  "node $TL run --limit 60 -- a >out.log 2>&1 && node $TL run --limit 60 -- b"; do
  got="$(decide "$command")"
  [ "$got" = allow ] || problems="$problems
$command -> $got"
done
got="$(decide 'sleep 999; rm -rf build' fg)"
[ "$got" = allow ] || problems="$problems
(foreground) sleep 999; rm -rf build -> $got"
if [ -z "$problems" ]; then
  result "background-guard: a background command wrapped in the helper is allowed, and a foreground command is not read" yes ""
else
  result "background-guard: a background command wrapped in the helper is allowed, and a foreground command is not read" no "$problems"
fi

# 3. After a wrapped command, an unwrapped one in a list, a pipeline, a command substitution
# (in the wrapped command's arguments or a redirection) or a subshell is denied, named; and
# so is a limit that is not one.
problems=""
while IFS=$'\t' read -r command unwrapped; do
  got="$(decide "$command")"
  grep -qxF "Not wrapped: \`$unwrapped\`" <<<"$got" || problems="$problems
$command -> $got"
done <<EOF
node $TL run --limit 60 -- sleep 1; sleep 999	sleep 999
node $TL run --limit 60 -- make && cd dist	cd dist
node $TL run --limit 60 -- make | tee log	tee log
node $TL run --limit 60 -- echo \$(sleep 999)	sleep 999
node $TL run --limit 60 -- make >"\$(date)"	date
(node $TL run --limit 60 -- a); (b)	b
node $TL run --limit 0 -- sleep 1	node $TL run --limit 0 -- sleep 1
node $TL run --limit forever -- sleep 1	node $TL run --limit forever -- sleep 1
EOF
if [ -z "$problems" ]; then
  result "background-guard: a wrapped command followed by an unwrapped one, in a list, a pipeline or a command substitution, is denied" yes ""
else
  result "background-guard: a wrapped command followed by an unwrapped one, in a list, a pipeline or a command substitution, is denied" no "$problems"
fi

# 4. A background line that cannot be read (an unclosed quote or substitution) is denied.
problems=""
for command in "node $TL run --limit 60 -- echo \"oops" "node $TL run --limit 60 -- echo \$(date"; do
  got="$(decide "$command")"
  grep -qxF 'This line could not be read: it ends inside a quote, a backtick or a $( ... ).' <<<"$got" || problems="$problems
$command -> $got"
done
if [ -z "$problems" ]; then
  result "background-guard: a background line that cannot be parsed is denied" yes ""
else
  result "background-guard: a background line that cannot be parsed is denied" no "$problems"
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures background-guard case(s) failed"
  exit 1
fi
