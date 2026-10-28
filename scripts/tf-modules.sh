#!/usr/bin/env bash
# Per-module helpers for a monorepo of independent modules. Nothing here plans
# against or applies to AWS.
#
#   scripts/tf-modules.sh list                 every module directory
#   scripts/tf-modules.sh changed [BASE_REF]   modules touched vs BASE_REF, or vs HEAD incl. untracked
#   scripts/tf-modules.sh examples MODULE      example dirs that call the module
#   scripts/tf-modules.sh check MODULE...      fmt, validate, test, examples, linters
#   scripts/tf-modules.sh release-check MODULE VERSION

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

die() { printf 'error: %s\n' "$*" >&2; exit 2; }

list() {
	for d in modules/*/; do
		compgen -G "${d}*.tf" >/dev/null && basename "$d"
	done
}

changed() {
	local base="${1:-}" paths
	if [ -n "$base" ]; then
		paths=$(git diff --name-only "$base"...HEAD)
	else
		paths=$( { git diff --name-only HEAD; git ls-files --others --exclude-standard; } )
	fi
	printf '%s\n' "$paths" | sed -nE 's#^modules/([^/]+)/.*#\1#p' | sort -u | while read -r m; do
		[ -d "modules/$m" ] && echo "$m"
	done
}

examples() {
	local m="$1"
	[ -d "modules/$m" ] || die "no module modules/$m"
	{
		[ -d "modules/$m/examples" ] && find "modules/$m/examples" -name '*.tf' -not -path '*/.terraform/*' -exec dirname {} \;
		# Root examples call modules by relative path; match the exact module, not a prefix.
		grep -lE "source[[:space:]]*=[[:space:]]*\"(\.\./)+modules/$m/?\"" examples/*/*.tf 2>/dev/null | xargs -r -n1 dirname
	} | sort -u
}

# Records a step's outcome and keeps going, so one failure does not hide the rest.
failures=()
step() {
	local label="$1"; shift
	printf '\n== %s\n' "$label"
	if "$@"; then echo "ok: $label"; else failures+=("$label"); fi
}
quiet() { "$@" >/dev/null; }

check_one() {
	local m="$1" dir="modules/$1"
	[ -d "$dir" ] || die "no module $dir"

	step "$m: fmt" terraform fmt -check -recursive -diff "$dir"
	step "$m: init" quiet terraform -chdir="$dir" init -backend=false -input=false
	step "$m: validate" terraform -chdir="$dir" validate
	if compgen -G "$dir/tests/*.tftest.hcl" >/dev/null; then
		step "$m: test" terraform -chdir="$dir" test
	else
		echo "($m has no tests)"
	fi

	local ex
	# shellcheck disable=SC2016 # $1 is expanded by the inner bash, on purpose
	for ex in $(examples "$m"); do
		step "$m: example $ex" bash -c 'terraform -chdir="$1" init -backend=false -input=false >/dev/null && terraform -chdir="$1" validate' _ "$ex"
	done

	if [ -f "$dir/tests/lint_validations.py" ]; then
		step "$m: lint_validations self-test" python3 "$dir/tests/lint_validations.py" --self-test
		step "$m: eager-operator lint" python3 "$dir/tests/lint_validations.py" "$dir"
		step "$m: lint_validations matches ami-builder" diff -q modules/ami-builder/tests/lint_validations.py "$dir/tests/lint_validations.py"
	fi

	if command -v tflint >/dev/null; then
		# A module's own config wins; otherwise the root one.
		local cfg="$PWD/.tflint.hcl"
		if [ -f "$dir/.tflint.hcl" ]; then cfg="$PWD/$dir/.tflint.hcl"; fi
		# shellcheck disable=SC2016
		step "$m: tflint" bash -c 'tflint --chdir="$1" --config="$2" --init >/dev/null && tflint --chdir="$1" --config="$2"' _ "$dir" "$cfg"
	else
		echo "(tflint not installed: skipped; CI runs it)"
	fi

	if command -v trivy >/dev/null; then
		step "$m: trivy" trivy config --quiet --severity HIGH,CRITICAL --exit-code 1 --ignorefile .trivyignore "$dir"
	else
		echo "(trivy not installed: skipped; CI runs it on changed modules)"
	fi

	# Module-specific gates live in CI as <module>-gates jobs; name them so they are not forgotten.
	if grep -qE "^  ${m}-gates:" .github/workflows/terraform-ci.yaml 2>/dev/null; then
		echo "note: CI also runs the '${m}-gates' job; its steps are in .github/workflows/terraform-ci.yaml"
	fi
}

check() {
	[ $# -gt 0 ] || die "check needs at least one module (try: make check, which uses the changed ones)"
	local m
	for m in "$@"; do check_one "$m"; done
	echo
	if [ ${#failures[@]} -gt 0 ]; then
		printf 'FAILED (%d):\n' "${#failures[@]}"
		printf '  - %s\n' "${failures[@]}"
		exit 1
	fi
	echo "all checks passed for: $*"
}

# A tag <module>-vX.Y.Z publishes to the registry; this is what CI's release
# job verifies, runnable before tagging.
release_check() {
	local m="${1:-}" v="${2:-}"
	[ -n "$m" ] && [ -n "$v" ] || die "usage: release-check MODULE VERSION (e.g. aurora 2.0.0)"
	[[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || die "VERSION must be semver without a leading v: $v"
	[ -d "modules/$m" ] || die "no module modules/$m"
	local cl="modules/$m/CHANGELOG.md" tag="$m-v$v"
	[ -f "$cl" ] || die "$cl is missing"
	grep -qE "^## \[$v\] - [0-9]{4}-[0-9]{2}-[0-9]{2}" "$cl" ||
		die "$cl needs a dated heading '## [$v] - YYYY-MM-DD' (an 'unreleased' heading is not a release)"
	if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then die "tag $tag already exists"; fi
	if [ -n "$(git status --porcelain -- "modules/$m")" ]; then die "modules/$m has uncommitted changes"; fi
	echo "ready: git tag -a $tag -m \"$m v$v\"   (pushing the tag is the release; do it deliberately)"
}

cmd="${1:-}"; shift || true
case "$cmd" in
	list) list ;;
	changed) changed "$@" ;;
	examples) examples "${1:?module}" ;;
	check) check "$@" ;;
	release-check) release_check "$@" ;;
	*) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
