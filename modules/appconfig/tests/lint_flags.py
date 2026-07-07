#!/usr/bin/env python3
"""Offline lint for rendered AWS.AppConfig.FeatureFlags documents.

Takes the JSON produced by `terraform output -json feature_flags_json` (a map
of instance key -> document string) and checks what AppConfig would reject at
version-create time - plus semantic rules terraform cannot express: value/
constraint agreement, enum membership, numeric bounds, regex patterns,
required coverage. stdlib only.

Usage: lint_flags.py <terraform-output.json>
Exits non-zero on any finding.
"""
import json
import re
import sys

VALID_TYPES = {"string", "number", "boolean"}


def lint_document(key, raw, findings):
    def bad(msg):
        findings.append(f"{key}: {msg}")

    try:
        doc = json.loads(raw)
    except ValueError as e:
        bad(f"not valid JSON: {e}")
        return

    if doc.get("version") != "1":
        bad(f'version must be "1", got {doc.get("version")!r}')
    flags = doc.get("flags")
    values = doc.get("values")
    if not isinstance(flags, dict) or not isinstance(values, dict):
        bad("flags/values must both be objects")
        return
    if set(flags) != set(values):
        bad(f"flags/values key mismatch: {sorted(set(flags) ^ set(values))}")

    for fk, flag in flags.items():
        if flag.get("name") != fk:
            bad(f"{fk}: name must equal the flag key")
        attrs = flag.get("attributes", {})
        for ak, a in attrs.items():
            c = a.get("constraints", {})
            t = c.get("type")
            if t not in VALID_TYPES:
                bad(f"{fk}.{ak}: constraint type {t!r} invalid")
                continue
            if "enum" in c and t != "string":
                bad(f"{fk}.{ak}: enum only applies to string attributes")
            if "pattern" in c:
                if t != "string":
                    bad(f"{fk}.{ak}: pattern only applies to string attributes")
                else:
                    try:
                        re.compile(c["pattern"])
                    except re.error as e:
                        bad(f"{fk}.{ak}: pattern does not compile: {e}")
            for bound in ("minimum", "maximum"):
                if bound in c and t != "number":
                    bad(f"{fk}.{ak}: {bound} only applies to number attributes")

        val = values.get(fk, {})
        if not isinstance(val.get("enabled"), bool):
            bad(f"{fk}: values.enabled must be a boolean")
        for ak, v in val.items():
            if ak == "enabled":
                continue
            if ak not in attrs:
                bad(f"{fk}: value for undeclared attribute {ak!r}")
                continue
            c = attrs[ak].get("constraints", {})
            t = c.get("type")
            if t == "number" and not isinstance(v, (int, float)):
                bad(f"{fk}.{ak}: value {v!r} is not a number")
            elif t == "boolean" and not isinstance(v, bool):
                bad(f"{fk}.{ak}: value {v!r} is not a boolean")
            elif t == "string" and not isinstance(v, str):
                bad(f"{fk}.{ak}: value {v!r} is not a string")
            if "enum" in c and v not in c["enum"]:
                bad(f"{fk}.{ak}: value {v!r} not in enum {c['enum']}")
            if "pattern" in c and isinstance(v, str) and not re.search(c["pattern"], v):
                bad(f"{fk}.{ak}: value {v!r} does not match pattern {c['pattern']!r}")
            if "minimum" in c and isinstance(v, (int, float)) and v < c["minimum"]:
                bad(f"{fk}.{ak}: value {v} below minimum {c['minimum']}")
            if "maximum" in c and isinstance(v, (int, float)) and v > c["maximum"]:
                bad(f"{fk}.{ak}: value {v} above maximum {c['maximum']}")

        # required attributes must be present in values
        for ak, a in attrs.items():
            if a.get("constraints", {}).get("required") and ak not in val:
                bad(f"{fk}: required attribute {ak!r} has no value")


def main(path):
    with open(path) as f:
        docs = json.load(f)
    findings = []
    for key, raw in sorted(docs.items()):
        lint_document(key, raw, findings)
    for f in findings:
        print(f"FINDING {f}")
    if not findings:
        print(f"OK      {len(docs)} document(s) clean")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
