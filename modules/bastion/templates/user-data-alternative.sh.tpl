#!/usr/bin/env bash
# ==============================================================================
# BASTION HOST — TEMPLATE 1: CORE
# ==============================================================================
# Fully air-gapped / private-network compatible.
# Zero outbound internet required. Every dependency resolved through:
#   • S3 Gateway Endpoint   — AL2023 yum repos, CloudWatch agent RPM
#   • SSM VPC Endpoint      — SSM Agent, Session Manager, Parameter Store
#   • CloudWatch Endpoint   — metrics + log ingestion
#   • EC2 Endpoint          — instance metadata, tagging
#
# Designed for: Amazon Linux 2023 (AL2023)
#   AL2023 ships with: aws-cli v2, ssm-agent, cloud-init — nothing to download.
#
# Terraform templatefile() variables:
#   ${aws_region}            e.g. "us-east-1"
#   ${environment}           e.g. "production"
#   ${instance_name}         e.g. "bastion-prod"
#   ${s3_log_bucket}         S3 bucket for session log archival
#   ${ssm_prefix}            SSM Parameter Store prefix e.g. "/bastion/prod"
#   ${log_group_prefix}      CloudWatch log group prefix e.g. "/bastion/prod"
#   ${log_retention_days}    CloudWatch retention period in days
#   ${vpc_cidr}              VPC CIDR — used for SSH allow-rule default
#   ${extra_yum_packages}    Space-separated extra packages (must be in AL2023 repo)
# ==============================================================================

set -Eeuo pipefail
IFS=$'\n\t'

LOGFILE="/var/log/bastion-init.log"
exec > >(tee -a "$LOGFILE") 2>&1

ts()  { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
log() { printf '[%s] [%s] %s\n' "$(ts)" "$1" "$2"; }
inf() { log INFO  "$1"; }
wrn() { log WARN  "$1"; }
err() { log ERROR "$1"; }

die() {
  err "$1"
  # Tag the instance so ASG/health checks surface the failure immediately
  local iid
  iid=$(imds instance-id 2>/dev/null || echo "unknown")
  aws ec2 create-tags \
    --region "${aws_region}" \
    --resources "$iid" \
    --tags Key=InitStatus,Value=FAILED "Key=InitError,Value=$1" \
    2>/dev/null || true
  exit 1
}

retry() {
  local n="$1"; shift
  local try=0 wait=3
  until "$@"; do
    try=$((try + 1))
    [[ $try -ge $n ]] && die "Failed after $n attempts: $*"
    wrn "Attempt $try/$n failed — retrying in ${wait}s: $*"
    sleep "$wait"
    wait=$(( wait * 2 > 60 ? 60 : wait * 2 ))
  done
}

# ── IMDSv2 Helper ──────────────────────────────────────────────────────────────
# All metadata calls go through the EC2 VPC endpoint — no internet needed.
_TOKEN=""
imds_token() {
  if [[ -z "$_TOKEN" ]]; then
    _TOKEN=$(curl -sf --max-time 5 \
      -X PUT "http://169.254.169.254/latest/api/token" \
      -H "X-aws-ec2-metadata-token-ttl-seconds: 300") \
      || die "IMDSv2 token request failed. Is the EC2 endpoint reachable and IMDSv2 enabled?"
  fi
  echo "$_TOKEN"
}
imds() {
  curl -sf --max-time 5 \
    -H "X-aws-ec2-metadata-token: $(imds_token)" \
    "http://169.254.169.254/latest/meta-data/$1"
}

inf "════════════════════════════════════════"
inf " Bastion Init — Template 1 (Core)"
inf " Region : ${aws_region}"
inf " Env    : ${environment}"
inf "════════════════════════════════════════"

# ── 1. Verify Private Connectivity ────────────────────────────────────────────
# Quickly assert VPC endpoints are reachable before going further.
# Fail fast here rather than mysteriously later.
inf "Verifying VPC endpoint reachability…"

check_endpoint() {
  local name="$1" url="$2"
  if curl -sf --max-time 5 "$url" -o /dev/null; then
    inf "  ✓ $name reachable"
  else
    # Warn but don't die — some endpoints only answer specific requests
    wrn "  ⚠ $name probe returned non-2xx (may still be functional)"
  fi
}

# EC2 metadata (confirms EC2 VPC endpoint or falls back to link-local)
check_endpoint "EC2 IMDS" "http://169.254.169.254/latest/meta-data/instance-id" || true

# S3 (AL2023 yum repos use this — gateway endpoint, no auth needed)
check_endpoint "S3 (yum)" "https://amazonlinux-2-repos-${aws_region}.s3.${aws_region}.amazonaws.com" || true

# ── 2. Instance Metadata ───────────────────────────────────────────────────────
inf "Fetching instance metadata…"
INSTANCE_ID=$(imds instance-id)
INSTANCE_TYPE=$(imds instance-type)
AZ=$(imds placement/availability-zone)
PRIVATE_IP=$(imds local-ipv4)

inf "  Instance : $INSTANCE_ID ($INSTANCE_TYPE)"
inf "  AZ       : $AZ  |  IP: $PRIVATE_IP"

# Enforce IMDSv2-only at the resource level (the LT already sets it, but belt+suspenders)
aws ec2 modify-instance-metadata-options \
  --region "${aws_region}" \
  --instance-id "$INSTANCE_ID" \
  --http-tokens required \
  --http-put-response-hop-limit 1 \
  --instance-metadata-tags enabled \
  2>/dev/null && inf "  IMDSv2 enforced" || wrn "  IMDSv2 enforce call failed (already set?)"

# ── 3. Hostname ────────────────────────────────────────────────────────────────
SHORT_ID="${INSTANCE_ID##i-}"
HOSTNAME="${instance_name}-$${SHORT_ID:0:8}.${aws_region}.internal"
hostnamectl set-hostname "$HOSTNAME"
printf '127.0.0.1  %s\n' "$HOSTNAME" >> /etc/hosts
inf "Hostname set: $HOSTNAME"

# ── 4. System Packages ────────────────────────────────────────────────────────
# AL2023 yum resolves through the S3 Gateway endpoint — no internet needed.
inf "Updating packages…"
retry 3 dnf update -y --security --quiet

inf "Installing packages…"
# Core utilities available in AL2023 repos (all via S3 endpoint)
PKGS=(
  # Audit & security
  audit          # auditd
  fail2ban       # brute-force protection

  # System observability (no internet needed — all in AL2023 repo)
  htop
  sysstat        # iostat, sar
  lsof
  bind-utils     # dig, nslookup

  # Shell tools
  jq
  tmux
  tree
  rsync
)

# Append caller-supplied extras (must exist in AL2023 repos)
EXTRA="${extra_yum_packages:-}"
[[ -n "$EXTRA" ]] && read -ra EXTRA_ARR <<< "$EXTRA" || EXTRA_ARR=()

retry 3 dnf install -y --quiet "$${PKGS[@]}" "$${EXTRA_ARR[@]}"
inf "Packages installed"

# ── 5. SSM Agent ──────────────────────────────────────────────────────────────
# AL2023 ships with ssm-agent; just ensure it's the latest version via the
# AL2023 repo (served through S3 VPC endpoint).
inf "Configuring SSM Agent…"
retry 3 dnf install -y --quiet amazon-ssm-agent
systemctl enable --now amazon-ssm-agent

# Tune SSM agent log verbosity (only warnings/errors to keep logs clean)
mkdir -p /etc/amazon/ssm
cat > /etc/amazon/ssm/seelog.xml <<'XML'
<seelog type="adaptive" mininterval="2000000" maxinterval="100000000"
    critmsgcount="500" minlevel="warn">
  <outputs formatid="fmtinfo">
    <rollingfile type="size"
      filename="/var/log/amazon/ssm/amazon-ssm-agent.log"
      maxsize="20000000" maxrolls="3"/>
    <filter levels="error,critical" formatid="fmterr">
      <rollingfile type="size"
        filename="/var/log/amazon/ssm/errors.log"
        maxsize="10000000" maxrolls="3"/>
    </filter>
  </outputs>
  <formats>
    <format id="fmtinfo" format="%Date %Time %LEVEL %Msg%n"/>
    <format id="fmterr"  format="%Date %Time %LEVEL [%FuncShort @ %File.%Line] %Msg%n"/>
  </formats>
</seelog>
XML

systemctl restart amazon-ssm-agent
inf "SSM Agent: $(systemctl is-active amazon-ssm-agent)"

# ── 6. CloudWatch Agent ────────────────────────────────────────────────────────
# Pulled from AL2023 repo — delivered via S3 VPC Gateway endpoint.
inf "Installing CloudWatch Agent…"
retry 3 dnf install -y --quiet amazon-cloudwatch-agent

LOG_GROUP="${log_group_prefix}"

cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<JSON
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "cwagent"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/bastion-init.log",
            "log_group_name": "${LOG_GROUP}/init",
            "log_stream_name": "{instance_id}",
            "retention_in_days": ${log_retention_days},
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/secure",
            "log_group_name": "${LOG_GROUP}/secure",
            "log_stream_name": "{instance_id}",
            "retention_in_days": ${log_retention_days},
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/audit/audit.log",
            "log_group_name": "${LOG_GROUP}/audit",
            "log_stream_name": "{instance_id}",
            "retention_in_days": ${log_retention_days},
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/bastion/sessions/*.log",
            "log_group_name": "${LOG_GROUP}/sessions",
            "log_stream_name": "{instance_id}/{hostname}",
            "retention_in_days": ${log_retention_days},
            "timezone": "UTC",
            "multi_line_start_pattern": "^\\[SESSION"
          },
          {
            "file_path": "/var/log/fail2ban.log",
            "log_group_name": "${LOG_GROUP}/fail2ban",
            "log_stream_name": "{instance_id}",
            "retention_in_days": ${log_retention_days},
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/messages",
            "log_group_name": "${LOG_GROUP}/messages",
            "log_stream_name": "{instance_id}",
            "retention_in_days": ${log_retention_days},
            "timezone": "UTC"
          }
        ]
      }
    },
    "force_flush_interval": 15
  },
  "metrics": {
    "namespace": "Bastion/${environment}",
    "append_dimensions": {
      "InstanceId": "\${aws:InstanceId}",
      "InstanceType": "\${aws:InstanceType}",
      "AutoScalingGroupName": "\${aws:AutoScalingGroupName}"
    },
    "metrics_collected": {
      "cpu":  { "measurement": ["cpu_usage_idle","cpu_usage_user","cpu_usage_system","cpu_usage_iowait"], "totalcpu": true },
      "mem":  { "measurement": ["mem_used_percent","mem_available_percent"] },
      "disk": { "measurement": ["disk_used_percent"], "resources": ["/","/tmp"] },
      "net":  { "measurement": ["net_bytes_recv","net_bytes_sent"], "resources": ["*"] },
      "netstat": { "measurement": ["tcp_established","tcp_time_wait"] },
      "processes": { "measurement": ["running","sleeping","zombie"] }
    }
  }
}
JSON

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -s
inf "CloudWatch Agent: $(systemctl is-active amazon-cloudwatch-agent)"

# ── 7. SSH Hardening ───────────────────────────────────────────────────────────
inf "Hardening SSH…"
cp /etc/ssh/sshd_config "/etc/ssh/sshd_config.orig.$(date +%Y%m%d)"

cat > /etc/ssh/sshd_config <<SSHD
# Bastion — hardened sshd_config — $(ts)
Port 22
AddressFamily any

# Auth — keys only, no passwords, no root
PermitRootLogin no
PasswordAuthentication no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
UsePAM yes

# Limits
MaxAuthTries 3
MaxSessions 5
MaxStartups 10:30:60
LoginGraceTime 20s

# Forwarding
AllowAgentForwarding yes
AllowTcpForwarding yes
X11Forwarding no
PermitTunnel no

# Keep-alive / timeouts
ClientAliveInterval 240
ClientAliveCountMax 2
TCPKeepAlive no

# Logging
LogLevel VERBOSE
SyslogFacility AUTHPRIV

# Hardening
StrictModes yes
IgnoreRhosts yes
HostbasedAuthentication no
PermitEmptyPasswords no
Compression no
GSSAPIAuthentication no

# Modern ciphers only
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group18-sha512
HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256

Banner /etc/ssh/banner
PrintMotd no
Subsystem sftp /usr/lib/openssh/sftp-server
SSHD

cat > /etc/ssh/banner <<'BANNER'
╔══════════════════════════════════════════════════════════╗
║            AUTHORIZED ACCESS ONLY                        ║
║  All activity is monitored and logged.                  ║
║  Unauthorized access is prohibited.                     ║
╚══════════════════════════════════════════════════════════╝
BANNER

sshd -t || die "sshd_config validation failed"
systemctl restart sshd
inf "SSH hardened and restarted"

# ── 8. Fail2ban ────────────────────────────────────────────────────────────────
inf "Configuring fail2ban…"
cat > /etc/fail2ban/jail.local <<'F2B'
[DEFAULT]
bantime  = 3600
findtime = 300
maxretry = 3
backend  = systemd
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled  = true
port     = 22
filter   = sshd
logpath  = %(sshd_log)s
maxretry = 3
bantime  = 7200
findtime = 300
F2B

systemctl enable --now fail2ban
inf "fail2ban: $(systemctl is-active fail2ban)"

# ── 9. auditd ──────────────────────────────────────────────────────────────────
inf "Configuring auditd…"
cat > /etc/audit/rules.d/bastion.rules <<'AUDITD'
-D
-b 8192
-f 1

# Identity files
-w /etc/passwd   -p wa -k identity
-w /etc/shadow   -p wa -k identity
-w /etc/sudoers  -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers

# SSH keys
-w /root/.ssh    -p wa -k ssh_keys
-w /home         -p wa -k ssh_keys

# Privilege escalation
-w /usr/bin/sudo -p x -k privilege
-w /usr/bin/su   -p x -k privilege
-a always,exit -F arch=b64 -S execve -F euid=0 -F auid>=1000 -F auid!=unset -k privileged

# Session tracking
-w /var/run/utmp -p wa -k session
-w /var/log/wtmp -p wa -k session
-w /var/log/btmp -p wa -k session

# File deletion
-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -k delete

# Lock
-e 2
AUDITD

service auditd restart 2>/dev/null || systemctl restart auditd
inf "auditd configured"

# ── 10. Kernel Hardening ───────────────────────────────────────────────────────
inf "Applying sysctl hardening…"
cat > /etc/sysctl.d/99-bastion.conf <<'SYSCTL'
# Network
net.ipv4.ip_forward = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1

# Memory
kernel.randomize_va_space = 2
kernel.yama.ptrace_scope = 1
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.sysrq = 0
fs.suid_dumpable = 0
SYSCTL
sysctl -p /etc/sysctl.d/99-bastion.conf --quiet
inf "Kernel hardening applied"

# ── 11. Session Logging ────────────────────────────────────────────────────────
# Every interactive SSH session is recorded via `script`.
# Sessions are shipped to CloudWatch Logs by the CW agent above,
# and archived to S3 via log rotation (no internet — goes through S3 endpoint).
inf "Setting up session logging…"

SESSION_DIR="/var/log/bastion/sessions"
mkdir -p "$SESSION_DIR"
chmod 750 "$SESSION_DIR"

cat > /etc/profile.d/00-session-logger.sh <<'LOGGER'
#!/usr/bin/env bash
# Record every interactive SSH session.
if [[ -n "${SSH_CONNECTION:-}" && $- == *i* ]]; then
  _USER=$(id -un)
  _TS=$(date -u '+%Y%m%dT%H%M%SZ')
  _LOG="/var/log/bastion/sessions/${_USER}_${_TS}_$$.log"

  printf '[SESSION START]\n  Time : %s\n  User : %s\n  From : %s\n  TTY  : %s\n\n' \
    "$_TS" "$_USER" "${SSH_CONNECTION%% *}" "${SSH_TTY:-?}" >> "$_LOG"

  exec /usr/bin/script \
    --quiet \
    --append \
    --timing="${_LOG}.timing" \
    --command="${SHELL:-/bin/bash}" \
    "$_LOG"
fi
LOGGER
chmod 644 /etc/profile.d/00-session-logger.sh

# Log rotation + S3 archival (via S3 Gateway VPC endpoint — no internet)
cat > /etc/logrotate.d/bastion-sessions <<ROTATE
$SESSION_DIR/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root adm
    postrotate
        aws s3 sync \
          $SESSION_DIR/ \
          s3://${s3_log_bucket}/sessions/$INSTANCE_ID/ \
          --storage-class INTELLIGENT_TIERING \
          --sse AES256 \
          --only-show-errors \
          --region ${aws_region} 2>/dev/null || true
    endscript
}
ROTATE

# ── 12. MOTD ───────────────────────────────────────────────────────────────────
cat > /etc/motd <<MOTD

  ┌─────────────────────────────────────────────────┐
  │  Bastion · ${environment^^}
  │  Instance : $INSTANCE_ID
  │  Region   : ${aws_region} / $AZ
  │  ⚠  Session recording is active.
  └─────────────────────────────────────────────────┘

MOTD

# ── 13. Auto Security Patching ────────────────────────────────────────────────
# AL2023 uses dnf-automatic; repos served via S3 VPC endpoint.
inf "Configuring automatic security patching…"
retry 3 dnf install -y --quiet dnf-automatic

# Security-only patches, no auto-reboot
sed -i 's/^upgrade_type.*/upgrade_type = security/' /etc/dnf/automatic.conf
sed -i 's/^apply_updates.*/apply_updates = yes/'     /etc/dnf/automatic.conf
sed -i 's/^reboot.*/reboot = never/'                 /etc/dnf/automatic.conf

systemctl enable --now dnf-automatic-install.timer
inf "dnf-automatic configured (security patches, no auto-reboot)"

# ── 14. Health Check ──────────────────────────────────────────────────────────
cat > /usr/local/bin/bastion-health <<'HEALTH'
#!/usr/bin/env bash
# Returns 0 = healthy, 1 = unhealthy.
# Suitable for: ASG custom health check, cron, ALB target check.
set -euo pipefail
FAIL=0

ok()   { printf '  ✓ %-40s\n' "$1"; }
fail() { printf '  ✗ %-40s\n' "$1"; FAIL=$((FAIL+1)); }

check() {
  local label="$1" cmd="$2"
  eval "$cmd" &>/dev/null && ok "$label" || fail "$label"
}

echo "=== Bastion Health Check · $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="

check "sshd"                  "systemctl is-active sshd"
check "ssm-agent"             "systemctl is-active amazon-ssm-agent"
check "cloudwatch-agent"      "systemctl is-active amazon-cloudwatch-agent"
check "fail2ban"              "systemctl is-active fail2ban"
check "auditd"                "systemctl is-active auditd"
check "disk / < 85%"          "[ \$(df / --output=pcent|tail -1|tr -d ' %') -lt 85 ]"
check "disk /tmp < 80%"       "[ \$(df /tmp --output=pcent|tail -1|tr -d ' %') -lt 80 ]"
check "load < 10"             "[ \$(awk '{print int(\$1)}' /proc/loadavg) -lt 10 ]"
check "IMDSv2"                "curl -sf --max-time 3 -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 5'"
check "session logger active" "test -f /etc/profile.d/00-session-logger.sh"

echo ""
if [[ $FAIL -gt 0 ]]; then
  echo "UNHEALTHY — $FAIL check(s) failed"
  exit 1
fi
echo "HEALTHY"
exit 0
HEALTH
chmod +x /usr/local/bin/bastion-health

# Publish health metric to CloudWatch every 5 minutes (via CW VPC endpoint)
cat > /etc/cron.d/bastion-health <<CRON
*/5 * * * * root \
  STATUS=\$(/usr/local/bin/bastion-health > /dev/null 2>&1; echo \$?); \
  IID=\$(curl -sf -H "X-aws-ec2-metadata-token: \$(curl -sf -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 30')" http://169.254.169.254/latest/meta-data/instance-id); \
  aws cloudwatch put-metric-data \
    --region ${aws_region} \
    --namespace "Bastion/${environment}" \
    --metric-name HealthStatus \
    --value \$STATUS \
    --dimensions InstanceId=\$IID \
    2>/dev/null || true
CRON

# ── 15. Operator Shell UX ─────────────────────────────────────────────────────
cat > /etc/profile.d/10-bastion-ux.sh <<'UX'
#!/usr/bin/env bash

# Coloured prompt: red bracket shows this is a bastion
export PS1='\[\e[1;31m\][BASTION]\[\e[0m\] \[\e[0;32m\]\u@\h\[\e[0m\]:\[\e[0;34m\]\w\[\e[0m\]\$ '

# Auditable history
export HISTTIMEFORMAT="%Y-%m-%d %H:%M:%S  "
export HISTSIZE=100000
export HISTFILESIZE=100000
export HISTCONTROL=ignoredups:erasedups
shopt -s histappend
PROMPT_COMMAND="history -a${PROMPT_COMMAND:+; $PROMPT_COMMAND}"

# Safety
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
alias ll='ls -alFh --color=auto'
alias la='ls -Ah'

# AWS shortcuts
alias whoami-aws='aws sts get-caller-identity'
alias myip='curl -sf http://169.254.169.254/latest/meta-data/local-ipv4'

# Bastion shortcuts
alias health='/usr/local/bin/bastion-health'
alias sessions='ls -lt /var/log/bastion/sessions/ | head -20'
UX
chmod 644 /etc/profile.d/10-bastion-ux.sh

# ── 16. Final Tag ─────────────────────────────────────────────────────────────
inf "Tagging instance…"
aws ec2 create-tags \
  --region "${aws_region}" \
  --resources "$INSTANCE_ID" \
  --tags \
    Key=InitStatus,Value=SUCCESS \
    Key=InitTime,Value="$(ts)" \
    Key=BastionTemplate,Value=core-v1 \
    Key=Environment,Value="${environment}" \
  2>/dev/null && inf "Tagged successfully" || wrn "Tagging failed (check IAM)"

inf "════════════════════════════════════════"
inf " Init COMPLETE in $((SECONDS))s"
inf "════════════════════════════════════════"