#!/usr/bin/env bash
# PreToolUse(Bash): a shell command that names a secret file goes to the human.
# Read() deny rules cover the Read tool; this covers `cat .env` and friends.
# A heuristic that prefers a needless prompt to a missed read; not a sandbox.
set -uo pipefail

cmd=$(jq -r '.tool_input.command // empty')
[ -n "$cmd" ] || exit 0

b="(^|[[:space:]'\"=/<>(:])"
e="([^A-Za-z0-9_]|$)"
pattern="${b}\.env(\.[A-Za-z0-9_-]+)?${e}|\.tfstate|\.tfvars${e}|\.pem${e}|${b}[^[:space:]'\"]*\.key${e}|\.p12${e}|\.pfx${e}|\.aws/credentials|id_(rsa|ed25519)${e}"

if printf '%s' "$cmd" | grep -qE "$pattern"; then
	jq -n '{
		hookSpecificOutput: {
			hookEventName: "PreToolUse",
			permissionDecision: "ask",
			permissionDecisionReason: "This command names a secret-bearing file (.env, *.tfstate, *.tfvars, *.pem, *.key, credentials). Guardrails: secrets are the human'"'"'s call."
		}
	}'
fi
exit 0
