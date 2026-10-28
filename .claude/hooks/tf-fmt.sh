#!/usr/bin/env bash
# PostToolUse(Edit|Write): format the Terraform file that was just written.
# CI gates on fmt, so a file left unformatted is a red build later.
set -uo pipefail

f=$(jq -r '.tool_response.filePath // .tool_input.file_path // empty')
case "$f" in
	*.tf | *.tftest.hcl) ;;
	*) exit 0 ;;
esac
[ -f "$f" ] || exit 0
command -v terraform >/dev/null || exit 0

if ! out=$(terraform fmt -no-color "$f" 2>&1); then
	# Exit 2 hands the parse error back to Claude to fix.
	printf 'terraform fmt failed on %s:\n%s\n' "$f" "$out" >&2
	exit 2
fi
exit 0
