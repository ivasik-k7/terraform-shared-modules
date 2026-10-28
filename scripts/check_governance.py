#!/usr/bin/env python3
"""Repository-wide module conventions, ratcheted by a baseline.

  python3 scripts/check_governance.py                  # check against the baseline
  python3 scripts/check_governance.py --self-test      # prove each rule fires
  python3 scripts/check_governance.py --write-baseline # record today's debt
  python3 scripts/check_governance.py --explain        # list the rules

Existing debt lives in .github/governance-baseline.json. A violation that is
not in the baseline fails, and so does a baseline entry that no longer
violates: the file only shrinks. New modules therefore start compliant.

Stdlib only. The HCL reader is a small lexer that understands strings,
interpolation, heredocs and comments well enough to find top-level
attributes of variable and output blocks. It fails towards reporting a
violation (a false positive) rather than missing one.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASELINE = ROOT / ".github" / "governance-baseline.json"
CI_WORKFLOW = ROOT / ".github" / "workflows" / "terraform-ci.yaml"
CANONICAL_LINTER = Path("modules/ami-builder/tests/lint_validations.py")
TERRAFORM_FLOOR = (1, 9, 0)

RULES = {
    "G001": "versions.tf declares required_version",
    "G002": f"required_version floor is at least {'.'.join(map(str, TERRAFORM_FLOOR))} (CI tests that floor)",
    "G003": "hashicorp/aws constraint has an upper bound (< N.0.0)",
    "G004": "README.md exists",
    "G005": "CHANGELOG.md exists",
    "G006": "tests/*.tftest.hcl exist",
    "G007": "every variable has type and description",
    "G008": "every output has a description",
    "G009": "a module with tests is in the CI validate matrix",
    "G010": "copies of lint_validations.py match modules/ami-builder",
    "G011": "no document links to this repository by absolute URL",
    "G012": "a module does not configure a provider",
}


@dataclass(frozen=True, order=True)
class Violation:
    rule: str
    subject: str  # module name, or a repo-relative path for G010/G011
    detail: str = ""

    @property
    def key(self) -> str:
        return f"{self.rule}:{self.subject}"


# --- HCL lexing -------------------------------------------------------------


def strip_hcl(text: str) -> str:
    """Blank out comments, string and heredoc contents in place. The result
    has the same length as the input, so offsets and line numbers map back."""
    out: list[str] = []
    i, n = 0, len(text)

    def skip_string(i: int) -> int:
        # i points just after the opening quote.
        while i < n:
            c = text[i]
            if c == "\\":
                i += 2
                continue
            if c == '"':
                return i + 1
            if text.startswith("${", i) or text.startswith("%{", i):
                i = skip_interp(i + 2)
                continue
            i += 1
        return n

    def skip_interp(i: int) -> int:
        depth = 1
        while i < n and depth:
            c = text[i]
            if c == '"':
                i = skip_string(i + 1)
                continue
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
            i += 1
        return i

    def blank(a: int, b: int) -> str:
        return "".join(ch if ch == "\n" else " " for ch in text[a:b])

    while i < n:
        c = text[i]
        if c == "#" or text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            out.append(blank(i, j))
            i = j
            continue
        if text.startswith("/*", i):
            j = text.find("*/", i + 2)
            end = n if j < 0 else j + 2
            out.append(blank(i, end))
            i = end
            continue
        if c == '"':
            j = skip_string(i + 1)
            out.append('"' + blank(i + 1, j - 1) + '"')
            i = j
            continue
        m = re.match(r"<<-?([A-Za-z_][A-Za-z0-9_]*)[ \t]*\n", text[i:])
        if m:
            tag = m.group(1)
            end_re = re.compile(r"^[ \t]*" + re.escape(tag) + r"[ \t]*$", re.M)
            em = end_re.search(text, i + m.end())
            end = n if em is None else em.end()
            out.append(blank(i, end))
            i = end
            continue
        out.append(c)
        i += 1
    return "".join(out)


BLOCK_RE = re.compile(r'^(variable|output|provider)\s+"[ ]*"\s*\{', re.M)


def blocks(stripped: str, original: str):
    """Yield (kind, name, body_at_depth_1, line) for variable/output/provider
    blocks. Names are read from the original text at the same offset."""
    for m in BLOCK_RE.finditer(stripped):
        kind = m.group(1)
        name_m = re.match(r'\w+\s+"([^"]*)"', original[m.start():])
        name = name_m.group(1) if name_m else "?"
        depth, i = 1, m.end()
        top: list[str] = []
        while i < len(stripped) and depth:
            c = stripped[i]
            if c in "{[(":
                depth += 1
            elif c in "}])":
                depth -= 1
            elif depth == 1:
                top.append(c)
            if depth == 1 and c in "}])":
                top.append("\n")
            i += 1
        yield kind, name, "".join(top), stripped.count("\n", 0, m.start()) + 1


def has_attr(body: str, attr: str) -> bool:
    return re.search(rf"^\s*{attr}\s*=", body, re.M) is not None


# --- facts about a module -----------------------------------------------------


def module_dirs(root: Path) -> list[Path]:
    base = root / "modules"
    if not base.is_dir():
        return []
    return sorted(p for p in base.iterdir() if p.is_dir() and any(p.glob("*.tf")))


def module_tf_files(mod: Path) -> list[Path]:
    return sorted(mod.glob("*.tf"))


def parse_floor(constraint: str) -> tuple[int, ...] | None:
    m = re.search(r">=?\s*v?(\d+)\.(\d+)(?:\.(\d+))?", constraint)
    if not m:
        m = re.search(r"~>\s*v?(\d+)\.(\d+)(?:\.(\d+))?", constraint)
    if not m:
        return None
    return tuple(int(g or 0) for g in m.groups())


def ci_matrix_modules(workflow: Path) -> set[str] | None:
    if not workflow.is_file():
        return None
    text = workflow.read_text(encoding="utf-8")
    m = re.search(r"^\s*module:\s*\[([^\]]*)\]", text, re.M)
    if not m:
        return None
    return {s.strip().strip("'\"") for s in m.group(1).split(",") if s.strip()}


def repo_url_patterns(root: Path) -> list[re.Pattern]:
    """Absolute URLs of this repository, derived at runtime so the owner and
    name are never written into a tracked file."""
    try:
        url = subprocess.run(
            ["git", "-C", str(root), "remote", "get-url", "origin"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return []
    m = re.search(r"[:/]([^/:]+)/([^/]+?)(?:\.git)?$", url)
    if not m:
        return []
    owner, name = map(re.escape, m.groups())
    return [re.compile(rf"github\.com[:/]{owner}/{name}(?![\w-])", re.I)]


# --- the rules ---------------------------------------------------------------


def check(root: Path) -> list[Violation]:
    found: list[Violation] = []
    matrix = ci_matrix_modules(root / CI_WORKFLOW.relative_to(ROOT))

    for mod in module_dirs(root):
        name = mod.name
        versions = mod / "versions.tf"
        vtext = versions.read_text(encoding="utf-8") if versions.is_file() else ""

        rv = re.search(r'required_version\s*=\s*"([^"]+)"', vtext)
        if not rv:
            found.append(Violation("G001", name))
        else:
            floor = parse_floor(rv.group(1))
            if floor is None or floor < TERRAFORM_FLOOR:
                found.append(Violation("G002", name, rv.group(1)))

        aws = re.search(r'source\s*=\s*"hashicorp/aws"[^}]*?version\s*=\s*"([^"]+)"', vtext, re.S)
        if not aws:
            aws = re.search(r'version\s*=\s*"([^"]+)"[^}]*?source\s*=\s*"hashicorp/aws"', vtext, re.S)
        if aws and "<" not in aws.group(1) and "~>" not in aws.group(1):
            found.append(Violation("G003", name, aws.group(1)))

        if not (mod / "README.md").is_file():
            found.append(Violation("G004", name))
        if not (mod / "CHANGELOG.md").is_file():
            found.append(Violation("G005", name))
        has_tests = any((mod / "tests").glob("*.tftest.hcl"))
        if not has_tests:
            found.append(Violation("G006", name))
        if has_tests and matrix is not None and name not in matrix:
            found.append(Violation("G009", name))

        missing_vars, missing_outs, providers = [], [], []
        for tf in module_tf_files(mod):
            original = tf.read_text(encoding="utf-8", errors="replace")
            for kind, bname, body, line in blocks(strip_hcl(original), original):
                if kind == "variable":
                    gaps = [a for a in ("type", "description") if not has_attr(body, a)]
                    if gaps:
                        missing_vars.append(f"{bname} ({'/'.join(gaps)}) {tf.name}:{line}")
                elif kind == "output" and not has_attr(body, "description"):
                    missing_outs.append(f"{bname} {tf.name}:{line}")
                elif kind == "provider":
                    providers.append(f"{bname} {tf.name}:{line}")
        if missing_vars:
            found.append(Violation("G007", name, "; ".join(missing_vars[:5]) + (" …" if len(missing_vars) > 5 else "")))
        if missing_outs:
            found.append(Violation("G008", name, "; ".join(missing_outs[:5]) + (" …" if len(missing_outs) > 5 else "")))
        if providers:
            found.append(Violation("G012", name, "; ".join(providers)))

    canonical = root / CANONICAL_LINTER
    if canonical.is_file():
        want = canonical.read_bytes()
        for copy in sorted(root.glob("modules/**/tests/lint_validations.py")) + sorted(
            root.glob("templates/*/tests/lint_validations.py")
        ):
            if ".terraform" in copy.parts or copy == canonical:
                continue
            if copy.read_bytes() != want:
                found.append(Violation("G010", str(copy.relative_to(root))))

    patterns = repo_url_patterns(root)
    if patterns:
        for doc in sorted(root.rglob("*.md")):
            rel = doc.relative_to(root)
            if any(p in (".git", ".terraform", "node_modules") for p in rel.parts):
                continue
            text = doc.read_text(encoding="utf-8", errors="replace")
            if any(p.search(text) for p in patterns):
                found.append(Violation("G011", str(rel)))

    return sorted(set(found))


# --- baseline ----------------------------------------------------------------


def load_baseline(path: Path) -> set[str]:
    if not path.is_file():
        return set()
    data = json.loads(path.read_text(encoding="utf-8"))
    return {f"{rule}:{s}" for rule, subjects in data.get("accepted", {}).items() for s in subjects}


def write_baseline(path: Path, violations: list[Violation]) -> None:
    accepted: dict[str, list[str]] = {}
    for v in violations:
        accepted.setdefault(v.rule, []).append(v.subject)
    doc = {
        "_comment": (
            "Debt that existed when the governance check was introduced. "
            "Remove an entry when you fix it; the check fails on stale entries. "
            "Regenerate only with: python3 scripts/check_governance.py --write-baseline"
        ),
        "accepted": {k: sorted(set(v)) for k, v in sorted(accepted.items())},
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")


def report(violations: list[Violation], baseline: set[str]) -> int:
    current = {v.key for v in violations}
    new = [v for v in violations if v.key not in baseline]
    stale, absent = [], []
    for key in sorted(baseline - current):
        subject = key.split(":", 1)[1]
        # A subject that is not on disk was not fixed: it is deleted, or not
        # committed yet in this checkout. Only a fix should fail the ratchet.
        exists = (ROOT / subject).exists() if "/" in subject else (ROOT / "modules" / subject).is_dir()
        (stale if exists else absent).append(key)
    for v in new:
        print(f"::error::{v.rule} {v.subject}: {RULES[v.rule]}" + (f" — {v.detail}" if v.detail else ""))
    for key in stale:
        rule, subject = key.split(":", 1)
        print(f"::error::{rule} {subject}: fixed, so remove it from {BASELINE.relative_to(ROOT)}")
    for key in absent:
        print(f"::notice::{key} is in the baseline but not in this checkout")
    accepted = len(current & baseline)
    print(f"governance: {len(new)} new, {len(stale)} stale baseline entries, {accepted} accepted debt")
    return 1 if new or stale else 0


# --- self-test -----------------------------------------------------------------

GOOD_VERSIONS = '''terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.90.0, < 7.0.0"
    }
  }
}
'''

GOOD_VARIABLES = '''variable "name" {
  type        = string
  description = "Name; braces in a string } do not end the block"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z{}]+$", var.name))
    error_message = "description = is not an attribute here."
  }
}

variable "policy" {
  type        = string
  default     = <<-EOT
    { "type": "unbalanced {" }
  EOT
  description = "Set after a heredoc."
}

# variable "commented" {}
'''

GOOD_OUTPUTS = '''output "arn" {
  description = "The ARN."
  value       = "${var.name}-${jsonencode({ a = "}" })}"
}
'''


def _write_module(root: Path, name: str, files: dict[str, str]) -> Path:
    mod = root / "modules" / name
    (mod / "tests").mkdir(parents=True, exist_ok=True)
    for rel, body in files.items():
        p = mod / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(body, encoding="utf-8")
    return mod


def _good_files() -> dict[str, str]:
    return {
        "versions.tf": GOOD_VERSIONS,
        "variables.tf": GOOD_VARIABLES,
        "outputs.tf": GOOD_OUTPUTS,
        "README.md": "# good\n",
        "CHANGELOG.md": "# Changelog\n",
        "tests/unit.tftest.hcl": "run \"x\" {}\n",
    }


def self_test() -> int:
    cases: dict[str, tuple[str, dict[str, str | None]]] = {
        "G001": ("no required_version", {"versions.tf": "terraform {}\n"}),
        "G002": ("floor below 1.9", {"versions.tf": GOOD_VERSIONS.replace(">= 1.9.0", ">= 1.5.0")}),
        "G003": ("unbounded aws", {"versions.tf": GOOD_VERSIONS.replace('">= 5.90.0, < 7.0.0"', '">= 5.0"')}),
        "G004": ("no README", {"README.md": None}),
        "G005": ("no CHANGELOG", {"CHANGELOG.md": None}),
        "G006": ("no tests", {"tests/unit.tftest.hcl": None}),
        "G007": ("variable without description", {"variables.tf": GOOD_VARIABLES + 'variable "bare" {\n  type = string\n}\n'}),
        "G008": ("output without description", {"outputs.tf": GOOD_OUTPUTS + 'output "bare" {\n  value = 1\n}\n'}),
        "G012": ("module configures a provider", {"providers.tf": 'provider "aws" {\n  region = "eu-west-1"\n}\n'}),
    }
    failures = 0
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        _write_module(root, "good", _good_files())
        wf = root / CI_WORKFLOW.relative_to(ROOT)
        wf.parent.mkdir(parents=True)
        # Every module with tests is listed except g009; g006 has no tests.
        wf.write_text("    module: [good, g001, g002, g003, g004, g005, g007, g008, g010, g012, ami-builder]\n")
        for rule, (label, change) in cases.items():
            files = _good_files()
            for k, v in change.items():
                if v is None:
                    files.pop(k, None)
                else:
                    files[k] = v
            _write_module(root, rule.lower(), files)
        # G009: tests, but not in the matrix.
        _write_module(root, "g009", _good_files())
        # G010: a drifted linter copy.
        (root / CANONICAL_LINTER).parent.mkdir(parents=True, exist_ok=True)
        (root / CANONICAL_LINTER).write_text("canonical\n")
        _write_module(root, "g010", {**_good_files(), "tests/lint_validations.py": "drifted\n"})
        _write_module(root, "ami-builder", {**_good_files(), "tests/lint_validations.py": "canonical\n"})

        got = {v.key for v in check(root)}

        expect = {f"{rule}:{rule.lower()}" for rule in cases} | {
            "G009:g009",
            "G010:modules/g010/tests/lint_validations.py",
        }
        # G006 module has no tests, so it is legitimately absent from the matrix.
        for key in sorted(expect):
            ok = key in got
            failures += not ok
            print(f"  {'ok ' if ok else 'MISS'} {key}")
        noise = {k for k in got if k.endswith(":good") or k.endswith(":ami-builder")}
        for key in sorted(noise):
            print(f"  FALSE POSITIVE {key}")
        failures += len(noise)
        unexpected = got - expect - noise
        for key in sorted(unexpected):
            print(f"  UNEXPECTED {key}")
        failures += len(unexpected)

    # G011 is checked against a synthetic remote rather than this clone's.
    pats = [re.compile(r"github\.com[:/]acme/widgets(?![\w-])", re.I)]
    hit = any(p.search("see https://github.com/acme/widgets/blob/main/x") for p in pats)
    miss = any(p.search("see ../widgets and github.com/acme/widgets-two") for p in pats)
    print(f"  {'ok ' if hit and not miss else 'MISS'} G011 pattern")
    failures += not (hit and not miss)

    print("self-test:", "FAILED" if failures else "passed")
    return 1 if failures else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--write-baseline", action="store_true")
    ap.add_argument("--explain", action="store_true")
    ap.add_argument("--all", action="store_true", help="print accepted debt too")
    args = ap.parse_args()

    if args.explain:
        for rule, text in RULES.items():
            print(f"{rule}  {text}")
        return 0
    if args.self_test:
        return self_test()

    violations = check(ROOT)
    if args.write_baseline:
        write_baseline(BASELINE, violations)
        print(f"wrote {len(violations)} entries to {BASELINE.relative_to(ROOT)}")
        return 0
    if args.all:
        for v in violations:
            print(f"{v.rule} {v.subject}" + (f" — {v.detail}" if v.detail else ""))
    return report(violations, load_baseline(BASELINE))


if __name__ == "__main__":
    sys.exit(main())
