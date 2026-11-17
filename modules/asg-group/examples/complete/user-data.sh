#!/bin/bash
# Configuration comes from Parameter Store at boot, never from user data.
set -euo pipefail
dnf install -y amazon-cloudwatch-agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c ssm:/orders/cloudwatch-agent
