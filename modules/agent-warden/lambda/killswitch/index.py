"""Emergency auto-containment for the AI agent role.

Invoked from SNS when the AI's monthly budget breaches its final threshold.
Attaches a deny-all inline policy to the role so the identity is instantly
neutered without waiting for a human. NOTE: this policy is out-of-band from
Terraform and a plain `terraform apply` will NOT remove it. To stand down:
codify with `kill_switch = true`, then delete the emergency policy explicitly
(`aws iam delete-role-policy --role-name <role> --policy-name <name>`).
"""
import json
import os

import boto3

iam = boto3.client("iam")

ROLE_NAME = os.environ["TARGET_ROLE"]
POLICY_NAME = os.environ["EMERGENCY_POLICY_NAME"]

DENY_ALL = {
    "Version": "2012-10-17",
    "Statement": [{"Sid": "EmergencyDenyAll", "Effect": "Deny", "Action": "*", "Resource": "*"}],
}


def handler(event, _context):
    iam.put_role_policy(
        RoleName=ROLE_NAME,
        PolicyName=POLICY_NAME,
        PolicyDocument=json.dumps(DENY_ALL),
    )
    print(
        f"Emergency deny-all attached to {ROLE_NAME}. Codify with kill_switch=true; "
        f"stand down with: aws iam delete-role-policy --role-name {ROLE_NAME} --policy-name {POLICY_NAME}"
    )
    return {"contained": ROLE_NAME}
