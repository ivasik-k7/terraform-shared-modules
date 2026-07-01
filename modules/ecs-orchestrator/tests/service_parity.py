#!/usr/bin/env python3
"""Guard against drift between the two aws_ecs_service resources.

`aws_ecs_service.autoscaled` and `aws_ecs_service.static` must have IDENTICAL
bodies except for:
  - the resource label (autoscaled / static)
  - the for_each source (services_autoscaled / services_static)
  - the trailing lifecycle { ignore_changes = [desired_count] } block (autoscaled only)

Terraform can't make `lifecycle` conditional, so the duplication is forced. This
script fails CI if anything ELSE diverges between the two, so a field added to one
copy but not the other is caught immediately.
"""
import re
import sys
import pathlib

SERVICES = pathlib.Path(__file__).resolve().parent.parent / "services.tf"


def extract_body(src: str, label: str) -> str:
    m = re.search(r'resource "aws_ecs_service" "%s" \{' % re.escape(label), src)
    if not m:
        sys.exit(f"could not find aws_ecs_service.{label} in services.tf")
    i = m.end()
    depth = 1
    j = i
    while depth > 0 and j < len(src):
        if src[j] == "{":
            depth += 1
        elif src[j] == "}":
            depth -= 1
        j += 1
    return src[i : j - 1]


def remove_block(text: str, name: str) -> str:
    m = re.search(r"\n\s*%s\s*\{" % re.escape(name), text)
    if not m:
        return text
    i = m.end()
    depth = 1
    j = i
    while depth > 0 and j < len(text):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
        j += 1
    return text[: m.start()] + text[j:]


def normalize(body: str) -> str:
    body = re.sub(r"\n\s*for_each\s*=.*", "", body, count=1)  # differs by design
    body = remove_block(body, "lifecycle")  # autoscaled-only
    return "\n".join(l.rstrip() for l in body.splitlines() if l.strip())


def main() -> int:
    src = SERVICES.read_text()
    a = normalize(extract_body(src, "autoscaled"))
    b = normalize(extract_body(src, "static"))
    if a == b:
        print("OK: aws_ecs_service.autoscaled and .static bodies are in parity.")
        return 0

    import difflib

    print("DRIFT: aws_ecs_service.autoscaled and .static bodies differ.\n")
    for line in difflib.unified_diff(
        a.splitlines(), b.splitlines(), "autoscaled", "static", lineterm=""
    ):
        print(line)
    return 1


if __name__ == "__main__":
    sys.exit(main())
