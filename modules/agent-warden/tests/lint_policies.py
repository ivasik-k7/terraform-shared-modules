#!/usr/bin/env python3
"""Offline IAM lint for the rendered agent-warden policy documents.

Runs parliament (https://github.com/duo-labs/parliament) over the JSON files
rendered by tests/render - catches malformed condition operators, unknown
action prefixes, and mistyped resource ARNs without any AWS credentials.
This is exactly the bug class terraform validate/test cannot see.

Usage: lint_policies.py <policy.json> [...]
Exits non-zero on any finding.
"""
import json
import sys

from parliament import analyze_policy_string


def normalize(node):
    # IAM treats ["x"] and "x" identically in condition values; parliament
    # crashes on single-element arrays under some operators, so collapse them.
    if isinstance(node, dict):
        return {k: normalize(v) for k, v in node.items()}
    if isinstance(node, list) and len(node) == 1 and isinstance(node[0], str):
        return node[0]
    if isinstance(node, list):
        return [normalize(v) for v in node]
    return node


def main(paths):
    failed = False
    for path in paths:
        with open(path) as f:
            doc = json.load(f)
        findings = analyze_policy_string(json.dumps(normalize(doc))).findings
        for finding in findings:
            print(f"FINDING {path}: {finding}")
            failed = True
        if not findings:
            print(f"OK      {path}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
