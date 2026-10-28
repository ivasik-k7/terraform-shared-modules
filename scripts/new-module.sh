#!/usr/bin/env bash
# Scaffold modules/<name> from the module template. The template is a working
# module (a log group) that passes its own tests, so the new module starts
# green and each edit shows what it broke.
#
#   scripts/new-module.sh <name> [--dest DIR]
#
# Copies only the module layer: the template's repository files (.github,
# release-please, pre-commit) are the monorepo's job here.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

name="${1:-}"
dest_root="modules"
if [ "${2:-}" = "--dest" ]; then dest_root="${3:?--dest needs a directory}"; fi
template="${TEMPLATE:-templates/terraform-aws-module}"

[[ "$name" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]] || { echo "usage: $0 <name>   (lowercase, digits, hyphens)" >&2; exit 2; }
[ -d "$template" ] || { echo "template not found: $template" >&2; exit 2; }
dest="$dest_root/$name"
[ -e "$dest" ] && { echo "$dest already exists" >&2; exit 2; }

mkdir -p "$dest/tests" "$dest/examples"
for f in versions.tf variables.tf locals.tf data.tf main.tf outputs.tf checks.tf README.md COSTS.md CHANGELOG.md; do
	[ -f "$template/$f" ] && cp "$template/$f" "$dest/$f"
done
cp "$template"/tests/*.tftest.hcl "$dest/tests/"
cp "$template"/tests/*.py "$dest/tests/"
for ex in "$template"/examples/*/; do
	exn=$(basename "$ex")
	mkdir -p "$dest/examples/$exn"
	find "$ex" -maxdepth 1 -type f \( -name '*.tf' -o -name '*.md' \) -exec cp {} "$dest/examples/$exn/" \;
done

# The Module tag is the one identifier every resource carries.
sed -i "s/\"Module\"    = \"log-group\"/\"Module\"    = \"$name\"/" "$dest/locals.tf"
grep -q "\"Module\"    = \"$name\"" "$dest/locals.tf" || echo "warning: set module_tags.Module in $dest/locals.tf by hand" >&2
sed -i "s/Module = \"log-group\" })/Module = \"$name\" })/" "$dest/tests/unit.tftest.hcl"

# Versions are cut per module, starting from an unreleased 0.1.0.
cat >"$dest/CHANGELOG.md" <<EOF
# Changelog

All notable changes to this module. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Released as tags \`$name-vX.Y.Z\`.

## [0.1.0] - unreleased

### Added

- Initial module.
EOF

cat <<EOF
created $dest from $template

Still the template's log group. Next:
  1. Replace the resources; keep the create switch, the tag merge, acknowledged_checks,
     governance and verify_commands (see $template/TEMPLATE.md, section 2).
  2. Rewrite README.md and COSTS.md for this module; drop the template note.
  3. Update the anchors in tests/check_consistency.py (its self-test says which).
  4. Add '$name' to the validate matrix in .github/workflows/terraform-ci.yaml.
  5. make check MODULE=$name
EOF
