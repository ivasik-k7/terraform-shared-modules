#!/usr/bin/env python3
"""Keeps the module's code, README and examples in step.

    python3 tests/check_consistency.py [module_dir]
    python3 tests/check_consistency.py --self-test

Rules (each one a drift that has shipped in a real module):

  checks      every `check "x"` block is in the acknowledged_checks
              validation list and in the README "Advisory checks" table,
              and nothing is listed that does not exist.
  variables   every variable has a description, a type and nullable = false
              (a variable with no default is required, and may omit it).
  outputs     every output has a description.
  examples    every argument an example passes to the module is a variable,
              and every module.<name>.<output> it reads is an output.
  contracts   every output the README lists under "Contract outputs" exists.

It errs towards false positives: a finding you disagree with is cheaper than
drift nobody saw. Standard library only.
"""

import pathlib
import re
import shutil
import sys
import tempfile

findings: list[str] = []


def finding(rule: str, message: str) -> None:
    findings.append(f"  {rule:<10} {message}")


def read(path: pathlib.Path) -> str:
    return path.read_text(encoding="utf-8") if path.exists() else ""


def strip_comments(hcl: str) -> str:
    out = []
    for line in hcl.splitlines():
        in_string = False
        for i, ch in enumerate(line):
            if ch == '"' and (i == 0 or line[i - 1] != "\\"):
                in_string = not in_string
            if not in_string and (ch == "#" or line[i : i + 2] == "//"):
                line = line[:i]
                break
        out.append(line)
    return "\n".join(out)


def blocks(hcl: str, kind: str) -> dict[str, str]:
    """{name: body} for every top-level `kind "name" { ... }` block."""
    result = {}
    for m in re.finditer(rf'^{kind} "([A-Za-z0-9_-]+)"\s*\{{', hcl, re.M):
        depth, i = 0, m.end() - 1
        while i < len(hcl):
            if hcl[i] == "{":
                depth += 1
            elif hcl[i] == "}":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        result[m.group(1)] = hcl[m.end() : i]
    return result


def section(text: str, heading: str) -> str:
    m = re.search(rf"^#+ {re.escape(heading)}\s*$(.*?)(?=^#+ |\Z)", text, re.M | re.S)
    return m.group(1) if m else ""


def check(mod: pathlib.Path) -> None:
    tf = {p.name: strip_comments(read(p)) for p in sorted(mod.glob("*.tf"))}
    everything = "\n".join(tf.values())
    readme = read(mod / "README.md")

    variables = blocks(tf.get("variables.tf", ""), "variable")
    outputs = blocks(tf.get("outputs.tf", ""), "output")
    checks = set(re.findall(r'^check "([a-z0-9_]+)"', everything, re.M))

    # checks
    ack = variables.get("acknowledged_checks", "")
    allowed = set(re.findall(r'"([a-z0-9_]+)"', ack.split("validation", 1)[1])) if "validation" in ack else set()
    documented = set(re.findall(r"^\| `([a-z0-9_]+)` \|", section(readme, "Advisory checks"), re.M))
    for name, where in ((allowed, "the acknowledged_checks validation"), (documented, 'README "Advisory checks"')):
        for c in sorted(checks - name):
            finding("checks", f"check {c} is missing from {where}")
        for c in sorted(name - checks):
            finding("checks", f"{where} lists {c}, which is not a check")

    # variables
    for name, body in variables.items():
        if not re.search(r"^\s*description\s*=", body, re.M):
            finding("variables", f"variable {name} has no description")
        if not re.search(r"^\s*type\s*=", body, re.M):
            finding("variables", f"variable {name} has no type")
        has_default = re.search(r"^\s*default\s*=", body, re.M)
        if not re.search(r"^\s*nullable\s*=\s*false", body, re.M) and has_default:
            finding("variables", f"variable {name} has a default but not nullable = false")

    # outputs
    for name, body in outputs.items():
        if not re.search(r"^\s*description\s*=", body, re.M):
            finding("outputs", f"output {name} has no description")

    # examples
    for path in sorted(mod.glob("examples/*/*.tf")):
        text = strip_comments(read(path))
        rel = path.relative_to(mod)
        for call_name, body in blocks(text, "module").items():
            if not re.search(r'^\s*source\s*=\s*"\.\./\.\."', body, re.M):
                continue
            # Top-level arguments of the module block only.
            depth = 0
            for line in body.splitlines():
                if depth == 0:
                    m = re.match(r"^\s*([a-z_][a-z0-9_]*)\s*=", line)
                    if m and m.group(1) not in ("source", "version", "providers", "depends_on", "count", "for_each") and m.group(1) not in variables:
                        finding("examples", f"{rel} passes {m.group(1)}, which is not a variable")
                depth += line.count("{") + line.count("[") - line.count("}") - line.count("]")
            for out in re.findall(rf"module\.{call_name}\.([a-z0-9_]+)", text):
                if out not in outputs:
                    finding("examples", f"{rel} reads module.{call_name}.{out}, which is not an output")

    # contracts
    for out in re.findall(r"^\| `([a-z0-9_]+)` \|", section(readme, "Contract outputs"), re.M):
        if out not in outputs:
            finding("contracts", f'README "Contract outputs" lists {out}, which is not an output')


def self_test(mod: pathlib.Path) -> int:
    """Reintroduce each defect in a copy and confirm it is reported."""
    cases = [
        ("checks.tf", 'check "logs_use_a_customer_key"', 'check "renamed_check"', "checks"),
        ("variables.tf", '  description = "Days to keep log events.', '  # description removed:"', "variables"),
        ("variables.tf", "  nullable    = false\n\n  validation {\n    condition     = contains([0,", "\n  validation {\n    condition     = contains([0,", "variables"),
        ("outputs.tf", '  description = "Log group ARN,', '  # "', "outputs"),
        ("examples/basic/main.tf", "  name                = ", "  no_such_input = 1\n  name                = ", "examples"),
        ("examples/complete/main.tf", "module.logs.governance", "module.logs.no_such_output", "examples"),
        ("README.md", "| `governance` |", "| `no_such_output` |", "contracts"),
    ]
    failed = 0
    global findings
    for rel, old, new, rule in cases:
        with tempfile.TemporaryDirectory() as tmp:
            copy = pathlib.Path(tmp) / "m"
            shutil.copytree(mod, copy, ignore=shutil.ignore_patterns(".terraform", ".git"))
            target = copy / rel
            text = read(target)
            if old not in text:
                print(f"  SKIP  {rel}: anchor not found ({old[:40]!r}) - update the self-test")
                failed += 1
                continue
            target.write_text(text.replace(old, new, 1), encoding="utf-8")
            findings = []
            check(copy)
            if not any(f.strip().startswith(rule) for f in findings):
                print(f"  FAIL  {rel}: the {rule} defect was not detected")
                failed += 1
    findings = []
    check(mod)
    if findings:
        print("  FAIL  the shipped module is not clean:")
        print("\n".join(findings))
        failed += 1
    if failed:
        print(f"SELF-TEST FAILED: {failed} case(s)")
        return 1
    print(f"SELF-TEST OK: {len(cases)} defects detected, module clean")
    return 0


def main(argv: list[str]) -> int:
    args = [a for a in argv if not a.startswith("--")]
    mod = pathlib.Path(args[0] if args else pathlib.Path(__file__).resolve().parent.parent)
    if "--self-test" in argv:
        return self_test(mod)
    check(mod)
    if findings:
        print(f"FAIL: {len(findings)} finding(s)")
        print("\n".join(findings))
        return 1
    print("OK: checks, variables, outputs, examples and README contracts are consistent")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
