#!/usr/bin/env python3
"""The four aws_ecs_service resources in services.tf must be the same service.

    python3 tests/service_parity.py [module_dir]
    python3 tests/service_parity.py --self-test

this, autoscaled, static_ignored and autoscaled_ignored exist only because
lifecycle.ignore_changes cannot be conditional. Everything between the
BEGIN SERVICE BODY and END SERVICE BODY markers must be identical, and each
resource must have exactly the lifecycle that justifies it (EXPECTED below)
and nothing else outside the markers but its for_each. An argument added to one
body and not the other is a service that behaves differently once it starts
autoscaling - found in production, not in a plan.

Fails towards false positives: any whitespace difference inside the bodies
counts. Standard library only.
"""

import pathlib
import re
import shutil
import sys
import tempfile

BEGIN = "# BEGIN SERVICE BODY"
END = "# END SERVICE BODY"


def resource(text: str, name: str) -> str:
    m = re.search(rf'^resource "aws_ecs_service" "{name}" \{{', text, re.M)
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


# Each resource: its for_each source, and the ignore_changes that justifies it.
EXPECTED = {
    "this": ("static", []),
    "autoscaled": ("autoscaled", ["desired_count"]),
    "static_ignored": ("static_ignored", ["task_definition"]),
    "autoscaled_ignored": ("autoscaled_ignored", ["desired_count", "task_definition"]),
}


def check(mod: pathlib.Path) -> list[str]:
    text = (mod / "services.tf").read_text(encoding="utf-8")
    found = []
    declared = set(re.findall(r'^resource "aws_ecs_service" "([a-z_]+)"', text, re.M))
    if declared != set(EXPECTED):
        return [f"services.tf must declare exactly aws_ecs_service.{{{', '.join(sorted(EXPECTED))}}}; it declares {sorted(declared)}"]
    bodies = {}
    for name, (source, ignored) in EXPECTED.items():
        block = resource(text, name)
        b = body(block)
        if b is None:
            found.append(f"aws_ecs_service.{name} needs exactly one BEGIN SERVICE BODY / END SERVICE BODY pair")
            continue
        if re.search(r"^\s*lifecycle\s*\{", b, re.M):
            found.append(f"the shared body of aws_ecs_service.{name} must not contain a lifecycle block")
        bodies[name] = b
        outside = re.sub(r"\s+", " ", block.replace(b, "").replace(END, "")).strip()
        expected = f"for_each = local.{source}" + (f" lifecycle {{ ignore_changes = [{', '.join(ignored)}] }}" if ignored else "")
        if outside != expected:
            found.append(f"aws_ecs_service.{name} may hold nothing outside the body but: {expected}")
    reference = bodies.get("this")
    for name, b in bodies.items():
        if reference is None or b == reference:
            continue
        for n, (x, y) in enumerate(zip(reference.splitlines(), b.splitlines()), 1):
            if x != y:
                found.append(f"aws_ecs_service.{name} differs from .this at body line {n}:\n    this:  {x.strip()}\n    {name}: {y.strip()}")
                break
        else:
            found.append(f"aws_ecs_service.{name} and .this differ in length")
    return found


def self_test(mod: pathlib.Path) -> int:
    cases = [
        ("an argument added to one body", lambda t: t.replace("  force_delete                       = each.value.force_delete\n", "  force_delete                       = true\n", 1)),
        ("a lost ignore_changes", lambda t: t.replace("ignore_changes = [desired_count]", "ignore_changes = []", 1)),
        ("a pipeline-owned service that Terraform redeploys", lambda t: t.replace("ignore_changes = [task_definition]", "ignore_changes = []", 1)),
        ("a lifecycle on the static service", lambda t: t.replace('resource "aws_ecs_service" "this" {\n', 'resource "aws_ecs_service" "this" {\n  lifecycle {\n    ignore_changes = [tags]\n  }\n', 1)),
        ("a lifecycle block inside every shared body", lambda t: t.replace("  # END SERVICE BODY\n", "  lifecycle {\n    ignore_changes = [tags]\n  }\n  # END SERVICE BODY\n")),
        ("a missing marker", lambda t: t.replace(BEGIN, "# BEGIN", 1)),
        ("an argument outside the markers", lambda t: t.replace("  for_each = local.autoscaled\n", "  for_each = local.autoscaled\n  triggers = { redeploy = timestamp() }\n", 1)),
    ]
    failed = 0
    for label, mutate in cases:
        with tempfile.TemporaryDirectory() as tmp:
            copy = pathlib.Path(tmp) / "m"
            shutil.copytree(mod, copy, ignore=shutil.ignore_patterns(".terraform", ".git"))
            target = copy / "services.tf"
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
    print(f"SELF-TEST OK: {len(cases)} defects detected, services.tf clean")
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
    print("OK: the four aws_ecs_service resources share one body")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
