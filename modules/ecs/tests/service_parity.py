#!/usr/bin/env python3
"""The two aws_ecs_service resources in services.tf must be the same service.

    python3 tests/service_parity.py [module_dir]
    python3 tests/service_parity.py --self-test

aws_ecs_service.this and aws_ecs_service.autoscaled exist only because
lifecycle.ignore_changes cannot be conditional. Everything between the
BEGIN SERVICE BODY and END SERVICE BODY markers must be identical, and each
resource must have exactly the lifecycle that justifies it: none on `this`,
ignore_changes = [desired_count] on `autoscaled`, and nothing else outside
the markers but each one's for_each. An argument added to one
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


def check(mod: pathlib.Path) -> list[str]:
    text = (mod / "services.tf").read_text(encoding="utf-8")
    found = []
    static, scaled = resource(text, "this"), resource(text, "autoscaled")
    if not static or not scaled:
        return ["services.tf must declare aws_ecs_service.this and aws_ecs_service.autoscaled"]
    a, b = body(static), body(scaled)
    if a is None or b is None:
        return ["each aws_ecs_service needs exactly one BEGIN SERVICE BODY / END SERVICE BODY pair"]
    if a != b:
        la, lb = a.splitlines(), b.splitlines()
        for n, (x, y) in enumerate(zip(la, lb), 1):
            if x != y:
                found.append(f"bodies differ at body line {n}:\n    this:       {x.strip()}\n    autoscaled: {y.strip()}")
                break
        else:
            found.append(f"bodies differ in length ({len(la)} and {len(lb)} lines)")
    squash = lambda s: re.sub(r"\s+", " ", s.replace(END, "")).strip()
    if squash(static.replace(a, "")) != "for_each = local.static":
        found.append("aws_ecs_service.this may hold nothing outside the body but for_each = local.static")
    if squash(scaled.replace(b, "")) != "for_each = local.autoscaled lifecycle { ignore_changes = [desired_count] }":
        found.append("aws_ecs_service.autoscaled may hold nothing outside the body but for_each = local.autoscaled and lifecycle { ignore_changes = [desired_count] }")
    if "lifecycle" in a:
        found.append("the shared body must not contain a lifecycle block")
    return found


def self_test(mod: pathlib.Path) -> int:
    cases = [
        ("an argument added to one body", lambda t: t.replace("  force_delete                       = each.value.force_delete\n", "  force_delete                       = true\n", 1)),
        ("a lost ignore_changes", lambda t: t.replace("ignore_changes = [desired_count]", "ignore_changes = []")),
        ("a lifecycle on the static service", lambda t: t.replace('resource "aws_ecs_service" "this" {\n', 'resource "aws_ecs_service" "this" {\n  lifecycle {\n    ignore_changes = [tags]\n  }\n', 1)),
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
    print("OK: aws_ecs_service.this and aws_ecs_service.autoscaled share one body")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
