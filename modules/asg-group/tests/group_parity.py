#!/usr/bin/env python3
"""The two aws_autoscaling_group resources in main.tf must be the same group.

    python3 tests/group_parity.py [module_dir]
    python3 tests/group_parity.py --self-test

aws_autoscaling_group.this (something else owns the instance count) and
.static (Terraform does) exist only because lifecycle.ignore_changes cannot be
conditional. Everything between the BEGIN GROUP BODY and END GROUP BODY
markers must be identical, and outside them each resource may hold only its
count and its lifecycle (EXPECTED below). An argument added to one body and
not the other is a group that behaves differently once a caller flips
ignore_desired_capacity_changes - found in production, not in a plan.

Fails towards false positives: any whitespace difference inside the bodies
counts. Standard library only.
"""

import pathlib
import re
import shutil
import sys
import tempfile

BEGIN = "# BEGIN GROUP BODY"
END = "# END GROUP BODY"

EXPECTED = {
    "this": "count = local.create ? (var.ignore_desired_capacity_changes ? 1 : 0) : 0 lifecycle { create_before_destroy = true ignore_changes = [desired_capacity] }",
    "static": "count = local.create ? (var.ignore_desired_capacity_changes ? 0 : 1) : 0 lifecycle { create_before_destroy = true }",
}


def resource(text: str, name: str) -> str:
    m = re.search(rf'^resource "aws_autoscaling_group" "{name}" \{{', text, re.M)
    if not m:
        return ""
    depth, i = 0, m.end() - 1
    while i < len(text):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[m.end() : i]
        i += 1
    return ""


def body(block: str) -> str | None:
    if block.count(BEGIN) != 1 or block.count(END) != 1:
        return None
    return block[block.index(BEGIN) : block.index(END)]


def check(mod: pathlib.Path) -> list[str]:
    text = (mod / "main.tf").read_text(encoding="utf-8")
    declared = set(re.findall(r'^resource "aws_autoscaling_group" "([a-z_]+)"', text, re.M))
    if declared != set(EXPECTED):
        return [f"main.tf must declare exactly aws_autoscaling_group.{{{', '.join(sorted(EXPECTED))}}}; it declares {sorted(declared)}"]
    found, bodies = [], {}
    for name, expected in EXPECTED.items():
        block = resource(text, name)
        b = body(block)
        if b is None:
            found.append(f"aws_autoscaling_group.{name} needs exactly one BEGIN/END GROUP BODY pair")
            continue
        if re.search(r"^\s*lifecycle\s*\{", b, re.M):
            found.append(f"the body of aws_autoscaling_group.{name} must not contain a lifecycle block")
        bodies[name] = b
        outside = re.sub(r"\s+", " ", block.replace(b, "").replace(END, "")).strip()
        if outside != expected:
            found.append(f"aws_autoscaling_group.{name} may hold nothing outside the body but: {expected}")
    if len(bodies) == 2 and bodies["this"] != bodies["static"]:
        for n, (x, y) in enumerate(zip(bodies["this"].splitlines(), bodies["static"].splitlines()), 1):
            if x != y:
                found.append(f"the bodies differ at body line {n}:\n    this:   {x.strip()}\n    static: {y.strip()}")
                break
        else:
            found.append("the bodies differ in length")
    return found


def self_test(mod: pathlib.Path) -> int:
    cases = [
        ("an argument added to one body", lambda t: t.replace("  protect_from_scale_in = var.protect_from_scale_in\n", "  protect_from_scale_in = true\n", 1)),
        ("a lost ignore_changes", lambda t: t.replace("ignore_changes        = [desired_capacity]", "ignore_changes        = []", 1)),
        ("an argument outside the markers", lambda t: t.replace("  count = local.create ? (var.ignore_desired_capacity_changes ? 0 : 1) : 0\n", "  count = local.create ? (var.ignore_desired_capacity_changes ? 0 : 1) : 0\n  force_delete = true\n", 1)),
        ("a missing marker", lambda t: t.replace(BEGIN, "# BEGIN", 1)),
    ]
    failed = 0
    for label, mutate in cases:
        with tempfile.TemporaryDirectory() as tmp:
            copy = pathlib.Path(tmp) / "m"
            shutil.copytree(mod, copy, ignore=shutil.ignore_patterns(".terraform", ".git"))
            target = copy / "main.tf"
            original = target.read_text(encoding="utf-8")
            mutated = mutate(original)
            if mutated == original:
                print(f"  SKIP  {label}: the mutation did not apply - update the self-test")
                failed += 1
                continue
            target.write_text(mutated, encoding="utf-8")
            if not check(copy):
                print(f"  FAIL  {label} was not detected")
                failed += 1
    clean = check(mod)
    if clean:
        print("  FAIL  the shipped module is not clean:\n  " + "\n  ".join(clean))
        failed += 1
    if failed:
        print(f"SELF-TEST FAILED: {failed} case(s)")
        return 1
    print(f"SELF-TEST OK: {len(cases)} defects detected, main.tf clean")
    return 0


def main(argv: list[str]) -> int:
    args = [a for a in argv if not a.startswith("--")]
    mod = pathlib.Path(args[0] if args else pathlib.Path(__file__).resolve().parent.parent)
    if "--self-test" in argv:
        return self_test(mod)
    found = check(mod)
    if found:
        print("FAIL:\n  " + "\n  ".join(found))
        return 1
    print("OK: aws_autoscaling_group.this and .static share one body")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
