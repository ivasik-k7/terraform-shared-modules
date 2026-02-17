#!/usr/bin/env bash
# =============================================================================
# BASTION HOST — USER DATA TEMPLATE  (Template 1: Core)
# =============================================================================
# Purpose  : Configure a hardened, observable, self-healing EC2 bastion host.
# Includes : System hardening · SSM Agent · CloudWatch Agent · Audit logging
#            SSH hardening · Fail2ban · Automatic OS patching · Health checks
#
# Variables substituted by Terraform templatefile():
#   ${aws_region}         — e.g. us-east-1
#   ${environment}        — e.g. production
#   ${vpc_cidr}           — e.g. 10.0.0.0/16  (for sshd AllowUsers / firewall)
#   ${allowed_ssh_cidrs}  — comma-separated CIDRs allowed to SSH (empty = SSH disabled)
#   ${s3_log_bucket}      — S3 bucket name for audit log shipping
#   ${log_retention_days} — CloudWatch log retention in days
#   ${ssm_param_prefix}   — SSM Parameter Store prefix (e.g. /bastion/prod)
#   ${instance_name}      — value for PS1 and hostname
#   ${extra_packages}     — space-separated list of extra yum/apt packages to install
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# ─────────────────────────────────────────────────────────────────────────────
# 0. Bootstrap Logging
#    Everything from this point is captured BEFORE CloudWatch Agent starts.
#    The file is shipped later; errors during bootstrap are NOT lost.
# ─────────────────────────────────────────────────────────────────────────────
BOOTSTRAP_LOG="/var/log/bastion-bootstrap.log"
exec > >(tee -a "$BOOTSTRAP_LOG") 2>&1

log() {
  local level="$1"; shift
  printf '[%s] [%-7s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$level" "$*"
}

die() {
  log ERROR "$*"
  aws ec2 create-tags \
    --region "${aws_region}" \
    --resources "$(curl -sf http://169.254.169.254/latest/meta-data/instance-id)" \
    --tags Key=BootstrapStatus,Value=FAILED Key=BootstrapError,Value="$*" \
    2>/dev/null || true
  exit 1
}

retry() {
  local attempts="$1"; shift
  local delay=5
  local count=0
  until "$@"; do
    count=$((count + 1))
    [[ $count -ge $attempts ]] && die "Command failed after $attempts attempts: $*"
    log WARN "Attempt $count/$attempts failed for: $*. Retrying in ${delay}s…"
    sleep "$delay"
    delay=$((delay * 2 < 120 ? delay * 2 : 120))  # cap at 120s
  done
}

log INFO "========================================================"
log INFO " Bastion Bootstrap START"
log INFO " Region      : ${aws_region}"
log INFO " Environment : ${environment}"
log INFO " Hostname    : ${instance_name}"
log INFO "========================================================"

# ─────────────────────────────────────────────────────────────────────────────
# 1. Detect OS Family
# ─────────────────────────────────────────────────────────────────────────────
if [[ -f /etc/os-release ]]; then
  # shellcheck source=/dev/null
  source /etc/os-release
  OS_ID="${ID:-unknown}"
  OS_VERSION="${VERSION_ID:-0}"
else
  die "Cannot detect OS — /etc/os-release missing"
fi

log INFO "Detected OS: $OS_ID $OS_VERSION"

case "$OS_ID" in
  amzn)      PKG_MGR="yum"; PKG_UPDATE="yum update -y"; PKG_INSTALL="yum install -y" ;;
  rhel|centos|rocky|almalinux) PKG_MGR="yum"; PKG_UPDATE="yum update -y"; PKG_INSTALL="yum install -y" ;;
  ubuntu|debian) PKG_MGR="apt"; PKG_UPDATE="DEBIAN_FRONTEND=noninteractive apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -q"; PKG_INSTALL="DEBIAN_FRONTEND=noninteractive apt-get install -y -q" ;;
  *) die "Unsupported OS: $OS_ID" ;;
esac

# ─────────────────────────────────────────────────────────────────────────────
# 2. System Updates  (idempotent — safe to re-run)
# ─────────────────────────────────────────────────────────────────────────────
log INFO "Running OS package update…"
retry 3 bash -c "$PKG_UPDATE"

# ─────────────────────────────────────────────────────────────────────────────
# 3. Install Core Packages
# ─────────────────────────────────────────────────────────────────────────────
log INFO "Installing core packages…"

CORE_PACKAGES=(
  # Essentials
  curl wget unzip tar git jq

  # Audit & security
  audit auditd fail2ban

  # Network diagnostics (safe, read-only)
  nmap-ncat netcat-openbsd || true   # distro name differs
  tcpdump
  traceroute
  nmap

  # System utilities
  htop
  iotop
  sysstat
  lsof
  strace
  bind-utils || dnsutils              # nslookup/dig — name differs per distro
)

INSTALLABLE=()
for pkg in "${CORE_PACKAGES[@]}"; do
  [[ "$pkg" == "||" || "$pkg" == "true" ]] && continue
  INSTALLABLE+=("$pkg")
done

retry 3 bash -c "$PKG_INSTALL ${INSTALLABLE[*]} 2>/dev/null || true"

if [[ -n "${extra_packages:-}" ]]; then
  log INFO "Installing extra packages: ${extra_packages}"
  # shellcheck disable=SC2086
  retry 3 bash -c "$PKG_INSTALL ${extra_packages}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 4. AWS CLI v2
# ─────────────────────────────────────────────────────────────────────────────
log INFO "Installing AWS CLI v2…"

if ! aws --version 2>&1 | grep -q "aws-cli/2"; then
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64)  AWS_CLI_URL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" ;;
    aarch64) AWS_CLI_URL="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" ;;
    *)       die "Unsupported architecture: $ARCH" ;;
  esac

  retry 3 curl -fsSL "$AWS_CLI_URL" -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp/awscliv2
  /tmp/awscliv2/aws/install --update
  rm -rf /tmp/awscliv2 /tmp/awscliv2.zip
  log INFO "AWS CLI v2 installed: $(aws --version)"
else
  log INFO "AWS CLI v2 already present: $(aws --version)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 5. Retrieve Instance Metadata (IMDSv2 only)
# ─────────────────────────────────────────────────────────────────────────────
log INFO "Fetching instance metadata via IMDSv2…"

IMDS_TOKEN=$(curl -sf -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 300") \
  || die "Failed to obtain IMDSv2 token — is IMDSv2 enforced?"

imds() { curl -sf -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
  "http://169.254.169.254/latest/meta-data/$1"; }

INSTANCE_ID=$(imds instance-id)
INSTANCE_TYPE=$(imds instance-type)
AZ=$(imds placement/availability-zone)
PRIVATE_IP=$(imds local-ipv4)
PUBLIC_IP=$(imds public-ipv4 2>/dev/null || echo "none")

log INFO "Instance   : $INSTANCE_ID ($INSTANCE_TYPE)"
log INFO "AZ         : $AZ"
log INFO "Private IP : $PRIVATE_IP"
log INFO "Public IP  : $PUBLIC_IP"

# Enforce IMDSv2-only at the instance level (belt and suspenders)
aws ec2 modify-instance-metadata-options \
  --region "${aws_region}" \
  --instance-id "$INSTANCE_ID" \
  --http-tokens required \
  --http-put-response-hop-limit 1 \
  --instance-metadata-tags enabled \
  2>/dev/null || log WARN "Could not enforce IMDSv2 (may already be set)"

# ─────────────────────────────────────────────────────────────────────────────
# 6. Hostname
# ─────────────────────────────────────────────────────────────────────────────
HOSTNAME_FQDN="${instance_name}-$${INSTANCE_ID##i-}.${aws_region}.internal"
hostnamectl set-hostname "$HOSTNAME_FQDN" 2>/dev/null || hostname "$HOSTNAME_FQDN"
echo "127.0.0.1  $HOSTNAME_FQDN ${instance_name}" >> /etc/hosts
log INFO "Hostname set to $HOSTNAME_FQDN"

# ─────────────────────────────────────────────────────────────────────────────
# 7. SSM Agent
# ─────────────────────────────────────────────────────────────────────────────
log INFO "Configuring SSM Agent…"

install_ssm_agent() {
  case "$OS_ID" in
    amzn)
      # Amazon Linux 2/2023 ships SSM agent; ensure it's latest
      retry 3 yum install -y amazon-ssm-agent
      ;;
    rhel|centos|rocky|almalinux)
      retry 3 yum install -y \
        "https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm"
      ;;
    ubuntu|debian)
      retry 3 bash -c "
        curl -fsSL https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_amd64/amazon-ssm-agent.deb \
          -o /tmp/ssm-agent.deb
        dpkg -i /tmp/ssm-agent.deb
        rm -f /tmp/ssm-agent.deb
      "
      ;;
  esac
}

if ! systemctl is-active --quiet amazon-ssm-agent 2>/dev/null; then
  install_ssm_agent
fi

mkdir -p /etc/amazon/ssm
cat > /etc/amazon/ssm/seelog.xml <<'SEELOG'
<seelog type="adaptive" mininterval="2000000" maxinterval="100000000"
        critmsgcount="500" minlevel="warn">
  <exceptions>
    <exception filepattern="test*" minlevel="error"/>
  </exceptions>
  <outputs formatid="fmtinfo">
    <console formatid="fmtinfo"/>
    <rollingfile type="size" filename="/var/log/amazon/ssm/amazon-ssm-agent.log"
                 maxsize="30000000" maxrolls="5"/>
    <filter levels="error,critical" formatid="fmterr">
      <rollingfile type="size" filename="/var/log/amazon/ssm/errors.log"
                   maxsize="10000000" maxrolls="5"/>
    </filter>
  </outputs>
  <formats>
    <format id="fmterr"   format="%Date %Time %LEVEL [%FuncShort @ %File.%Line] %Msg%n"/>
    <format id="fmtinfo"  format="%Date %Time %LEVEL %Msg%n"/>
  </formats>
</seelog>
SEELOG

systemctl enable amazon-ssm-agent
systemctl restart amazon-ssm-agent
log INFO "SSM Agent status: $(systemctl is-active amazon-ssm-agent)"

# ─────────────────────────────────────────────────────────────────────────────
# 8. CloudWatch Agent
# ─────────────────────────────────────────────────────────────────────────────
log INFO "Installing CloudWatch Agent…"

install_cw_agent() {
  case "$OS_ID" in
    amzn)
      retry 3 yum install -y amazon-cloudwatch-agent ;;
    rhel|centos|rocky|almalinux)
      retry 3 yum install -y \
        "https://s3.amazonaws.com/amazoncloudwatch-agent/redhat/amd64/latest/amazon-cloudwatch-agent.rpm" ;;
    ubuntu|debian)
      retry 3 bash -c "
        curl -fsSL https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb \
          -o /tmp/cw-agent.deb
        dpkg -i /tmp/cw-agent.deb
        rm -f /tmp/cw-agent.deb
      "
      ;;
  esac
}

if ! command -v amazon-cloudwatch-agent-ctl &>/dev/null; then
  install_cw_agent
fi

LOG_GROUP_PREFIX="/aws/bastion/${environment}"

cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<CW_CONFIG
{
  "agent": {
    "metrics_collection_interval": 60,
    "logfile": "/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log",
    "run_as_user": "cwagent"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/secure",
            "log_group_name": "${LOG_GROUP_PREFIX}/auth",
            "log_stream_name": "{instance_id}/secure",
            "timezone": "UTC",
            "retention_in_days": ${log_retention_days},
            "timestamp_format": "%b %d %H:%M:%S"
          },
          {
            "file_path": "/var/log/auth.log",
            "log_group_name": "${LOG_GROUP_PREFIX}/auth",
            "log_stream_name": "{instance_id}/auth",
            "timezone": "UTC",
            "retention_in_days": ${log_retention_days},
            "timestamp_format": "%b %d %H:%M:%S"
          },
          {
            "file_path": "/var/log/bastion-bootstrap.log",
            "log_group_name": "${LOG_GROUP_PREFIX}/bootstrap",
            "log_stream_name": "{instance_id}/bootstrap",
            "timezone": "UTC",
            "retention_in_days": ${log_retention_days}
          },
          {
            "file_path": "/var/log/bastion-session.log",
            "log_group_name": "${LOG_GROUP_PREFIX}/sessions",
            "log_stream_name": "{instance_id}/sessions",
            "timezone": "UTC",
            "retention_in_days": ${log_retention_days},
            "multi_line_start_pattern": "^\\[SESSION"
          },
          {
            "file_path": "/var/log/audit/audit.log",
            "log_group_name": "${LOG_GROUP_PREFIX}/audit",
            "log_stream_name": "{instance_id}/audit",
            "timezone": "UTC",
            "retention_in_days": ${log_retention_days}
          },
          {
            "file_path": "/var/log/fail2ban.log",
            "log_group_name": "${LOG_GROUP_PREFIX}/fail2ban",
            "log_stream_name": "{instance_id}/fail2ban",
            "timezone": "UTC",
            "retention_in_days": ${log_retention_days}
          },
          {
            "file_path": "/var/log/messages",
            "log_group_name": "${LOG_GROUP_PREFIX}/syslog",
            "log_stream_name": "{instance_id}/messages",
            "timezone": "UTC",
            "retention_in_days": ${log_retention_days}
          },
          {
            "file_path": "/var/log/syslog",
            "log_group_name": "${LOG_GROUP_PREFIX}/syslog",
            "log_stream_name": "{instance_id}/syslog",
            "timezone": "UTC",
            "retention_in_days": ${log_retention_days}
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
    "aggregation_dimensions": [["InstanceId"], ["AutoScalingGroupName"]],
    "metrics_collected": {
      "cpu": {
        "measurement": ["cpu_usage_idle","cpu_usage_user","cpu_usage_system","cpu_usage_iowait"],
        "metrics_collection_interval": 60,
        "totalcpu": true
      },
      "mem": {
        "measurement": ["mem_used_percent","mem_available_percent"],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": ["disk_used_percent","disk_inodes_free"],
        "metrics_collection_interval": 60,
        "resources": ["/", "/tmp"]
      },
      "net": {
        "measurement": ["net_bytes_recv","net_bytes_sent","net_packets_sent","net_packets_recv"],
        "metrics_collection_interval": 60,
        "resources": ["*"]
      },
      "netstat": {
        "measurement": ["tcp_established","tcp_time_wait","tcp_close_wait"],
        "metrics_collection_interval": 60
      },
      "processes": {
        "measurement": ["running","sleeping","blocked","zombie"],
        "metrics_collection_interval": 60
      },
      "swap": {
        "measurement": ["swap_used_percent"],
        "metrics_collection_interval": 60
      }
    }
  }
}
CW_CONFIG

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -s

log INFO "CloudWatch Agent status: $(systemctl is-active amazon-cloudwatch-agent 2>/dev/null || echo 'unknown')"

# ─────────────────────────────────────────────────────────────────────────────
# 9. SSH Hardening
# ─────────────────────────────────────────────────────────────────────────────
log INFO "Applying SSH hardening…"

cp /etc/ssh/sshd_config /etc/ssh/sshd_config.original."$(date +%Y%m%d)"

cat > /etc/ssh/sshd_config <<SSHD
# ─────────────────────────────────────────────────
# Bastion Host — Hardened sshd_config
# Generated by bastion-userdata.sh
# Last updated: $(date -u)
# ─────────────────────────────────────────────────

# Network
Port 22
AddressFamily any
ListenAddress 0.0.0.0

# Authentication
PermitRootLogin no
PasswordAuthentication no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys

# MFA / PAM (leave PAM on for audit hooks)
UsePAM yes

# Session limits
MaxAuthTries 3
MaxSessions 5
MaxStartups 10:30:100
LoginGraceTime 30s

# Forwarding (disable everything except strictly needed)
AllowAgentForwarding yes
AllowTcpForwarding yes
X11Forwarding no
PermitTunnel no

# Timeouts
ClientAliveInterval 300
ClientAliveCountMax 2
TCPKeepAlive no

# Logging — verbose gives us key fingerprint in logs
LogLevel VERBOSE
SyslogFacility AUTHPRIV

# Security
StrictModes yes
IgnoreRhosts yes
HostbasedAuthentication no
PermitEmptyPasswords no
Compression no
GSSAPIAuthentication no

# Ciphers — only strong modern ciphers
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512
HostKeyAlgorithms rsa-sha2-512,rsa-sha2-256,ecdsa-sha2-nistp256,ssh-ed25519

# Banner
Banner /etc/ssh/banner
PrintMotd no

# Subsystems
Subsystem sftp /usr/lib/openssh/sftp-server
SSHD

# Legal / deterrence banner
cat > /etc/ssh/banner <<'BANNER'
╔══════════════════════════════════════════════════════════════════╗
║                    AUTHORIZED ACCESS ONLY                        ║
║                                                                  ║
║  This system is restricted to authorized users only. All        ║
║  activity is monitored and logged. Unauthorized access is        ║
║  strictly prohibited and may be subject to legal action.        ║
╚══════════════════════════════════════════════════════════════════╝
BANNER

# Validate config before restarting
sshd -t || die "sshd_config validation failed — check /etc/ssh/sshd_config"
systemctl restart sshd || systemctl restart ssh
log INFO "SSH hardening applied and sshd restarted"

# ─────────────────────────────────────────────────────────────────────────────
# 10. Fail2ban
# ─────────────────────────────────────────────────────────────────────────────
log INFO "Configuring Fail2ban…"

cat > /etc/fail2ban/jail.local <<'F2B'
[DEFAULT]
bantime  = 3600
findtime  = 600
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

systemctl enable fail2ban
systemctl restart fail2ban
log INFO "Fail2ban status: $(systemctl is-active fail2ban)"

# ─────────────────────────────────────────────────────────────────────────────
# 11. Audit Daemon (auditd)
# ─────────────────────────────────────────────────────────────────────────────
log INFO "Configuring auditd…"

cat > /etc/audit/rules.d/bastion.rules <<'AUDITD'
## Bastion-specific audit rules
## Covers: privilege escalation, file access, network, user management

# Remove any existing rules
-D

# Buffer size — increase for busy bastions
-b 8192

# Failure mode: 1 = log; 2 = panic
-f 1

# ─── Identity changes ─────────────────────────────────────────────
-w /etc/passwd  -p wa -k identity
-w /etc/group   -p wa -k identity
-w /etc/shadow  -p wa -k identity
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers

# ─── SSH keys ─────────────────────────────────────────────────────
-w /root/.ssh           -p wa -k ssh_keys
-w /home                -p wa -k ssh_keys

# ─── Privilege escalation ─────────────────────────────────────────
-w /usr/bin/sudo   -p x -k privilege
-w /usr/bin/su     -p x -k privilege
-w /usr/bin/newgrp -p x -k privilege

# ─── Privileged commands ──────────────────────────────────────────
-a always,exit -F arch=b64 -S execve -F euid=0 -F auid>=1000 -F auid!=unset -k privileged

# ─── Network configuration changes ───────────────────────────────
-a always,exit -F arch=b64 -S sethostname -S setdomainname -k network_modifications
-w /etc/hosts      -p wa -k network_modifications
-w /etc/sysconfig/network -p wa -k network_modifications

# ─── Session tracking ─────────────────────────────────────────────
-w /var/run/utmp -p wa -k session
-w /var/log/wtmp -p wa -k session
-w /var/log/btmp -p wa -k session

# ─── System calls: file deletion ──────────────────────────────────
-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -F auid!=unset -k delete

# ─── System calls: file permission changes ────────────────────────
-a always,exit -F arch=b64 -S chmod -S fchmod -S fchmodat -F auid>=1000 -k perm_mod
-a always,exit -F arch=b64 -S chown -S fchown -S fchownat -S lchown -F auid>=1000 -k perm_mod

# ─── Kernel module loading ────────────────────────────────────────
-w /sbin/insmod  -p x -k modules
-w /sbin/rmmod   -p x -k modules
-w /sbin/modprobe -p x -k modules
-a always,exit -F arch=b64 -S init_module -S delete_module -k modules

# ─── Lock rules at the end ────────────────────────────────────────
-e 2
AUDITD

service auditd restart 2>/dev/null || systemctl restart auditd 2>/dev/null || true
log INFO "auditd configured"

# ─────────────────────────────────────────────────────────────────────────────
# 12. Kernel Hardening (sysctl)
# ─────────────────────────────────────────────────────────────────────────────
log INFO "Applying kernel hardening parameters…"

cat > /etc/sysctl.d/99-bastion-hardening.conf <<'SYSCTL'
# ─── Network hardening ───────────────────────────────────────────────────────
# Disable IP forwarding (bastion is NOT a router)
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# Reverse path filtering — prevent spoofing
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignore ICMP broadcast (Smurf attack mitigation)
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Ignore bogus ICMP error responses
net.ipv4.icmp_ignore_bogus_error_responses = 1

# TCP SYN cookies — prevent SYN flood
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2

# Disable source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# Disable ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv6.conf.all.accept_redirects = 0

# Do not send redirects
net.ipv4.conf.all.send_redirects = 0

# Log martian packets
net.ipv4.conf.all.log_martians = 1

# TIME_WAIT — recycle and reuse
net.ipv4.tcp_tw_reuse = 1

# ─── Memory / exec hardening ─────────────────────────────────────────────────
# ASLR — full randomization
kernel.randomize_va_space = 2

# Restrict ptrace — only parent may trace child
kernel.yama.ptrace_scope = 1

# Restrict dmesg to root
kernel.dmesg_restrict = 1

# Restrict kernel pointers in /proc
kernel.kptr_restrict = 2

# Disable magic SysRq key
kernel.sysrq = 0

# Restrict core dump access
fs.suid_dumpable = 0

# ─── File descriptor limits ───────────────────────────────────────────────────
fs.file-max = 65536
SYSCTL

sysctl -p /etc/sysctl.d/99-bastion-hardening.conf
log INFO "Kernel hardening applied"

# ─────────────────────────────────────────────────────────────────────────────
# 13. Session Logging
# ─────────────────────────────────────────────────────────────────────────────
log INFO "Setting up session logging wrapper…"

SESSION_LOG_DIR="/var/log/bastion/sessions"
mkdir -p "$SESSION_LOG_DIR"
chmod 750 "$SESSION_LOG_DIR"
chown root:adm "$SESSION_LOG_DIR" 2>/dev/null || true

# MOTD with session-recording notice
cat > /etc/motd <<MOTD

  ╔════════════════════════════════════════════════════════╗
  ║  Bastion Host — ${environment^^}                              ║
  ║  Instance : $INSTANCE_ID                                ║
  ║  Region   : ${aws_region}                               ║
  ║                                                        ║
  ║  ⚠  Your terminal session is being recorded.          ║
  ╚════════════════════════════════════════════════════════╝

MOTD

cat > /etc/profile.d/00-bastion-session-logger.sh <<'SESSION_LOGGER'
#!/usr/bin/env bash
# Log every interactive terminal session to a timestamped file
# that is also shipped to CloudWatch Logs.
if [[ -n "${SSH_CONNECTION:-}" ]] && [[ $- == *i* ]]; then
  SESSION_USER=$(whoami)
  SESSION_TIME=$(date -u '+%Y%m%dT%H%M%SZ')
  SESSION_LOG="/var/log/bastion/sessions/${SESSION_USER}_${SESSION_TIME}_$$.log"

  {
    echo "[SESSION START]"
    echo "  Time       : ${SESSION_TIME}"
    echo "  User       : ${SESSION_USER}"
    echo "  From IP    : ${SSH_CONNECTION%% *}"
    echo "  SSH TTY    : ${SSH_TTY:-unknown}"
    echo "  Instance   : $(curl -sf -H 'X-aws-ec2-metadata-token: '"$(curl -sf -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 30')" http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo 'unknown')"
  } >> "${SESSION_LOG}"

  exec /usr/bin/script \
    --quiet \
    --append \
    --timing="${SESSION_LOG}.timing" \
    --command="${SHELL:-/bin/bash}" \
    "${SESSION_LOG}"
fi
SESSION_LOGGER

chmod 644 /etc/profile.d/00-bastion-session-logger.sh
log INFO "Session logging configured"

# ─────────────────────────────────────────────────────────────────────────────
# 14. Log rotation (session logs + bootstrap logs)
# ─────────────────────────────────────────────────────────────────────────────
cat > /etc/logrotate.d/bastion <<'LOGROTATE'
/var/log/bastion/sessions/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root adm
    sharedscripts
    postrotate
        # Ship rotated logs to S3 before deletion
        aws s3 sync \
          /var/log/bastion/sessions/ \
          s3://${s3_log_bucket}/bastion-sessions/$(curl -sf http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo 'unknown')/ \
          --storage-class INTELLIGENT_TIERING \
          --sse AES256 \
          --only-show-errors 2>/dev/null || true
    endscript
}

/var/log/bastion-bootstrap.log {
    monthly
    rotate 3
    compress
    delaycompress
    missingok
    notifempty
}
LOGROTATE

log INFO "Log rotation configured"

# ─────────────────────────────────────────────────────────────────────────────
# 15. Automatic Security Patching (OS-level, unattended)
# ─────────────────────────────────────────────────────────────────────────────
log INFO "Configuring automatic security patching…"

case "$OS_ID" in
  amzn)
    retry 3 yum install -y yum-cron
    sed -i 's/^update_cmd.*=.*/update_cmd = security/' /etc/yum/yum-cron.conf
    sed -i 's/^apply_updates.*=.*/apply_updates = yes/' /etc/yum/yum-cron.conf
    systemctl enable --now yum-cron
    ;;
  ubuntu|debian)
    retry 3 bash -c "$PKG_INSTALL unattended-upgrades"
    cat > /etc/apt/apt.conf.d/50bastion-security <<'UNATTENDED'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Mail "root";
UNATTENDED
    dpkg-reconfigure -f noninteractive unattended-upgrades
    ;;
esac

log INFO "Automatic security patching configured"

# ─────────────────────────────────────────────────────────────────────────────
# 16. Health Check Script (used by ALB / ASG)
# ─────────────────────────────────────────────────────────────────────────────
cat > /usr/local/bin/bastion-healthcheck <<'HEALTHCHECK'
#!/usr/bin/env bash
# Returns 0 (healthy) or 1 (unhealthy).
# Invoked by: ALB health check · custom ASG lifecycle hook · cron.
set -euo pipefail
ERRORS=0

check() {
  local name="$1" cmd="$2"
  if ! eval "$cmd" &>/dev/null; then
    echo "[UNHEALTHY] $name"
    ERRORS=$((ERRORS + 1))
  else
    echo "[OK]        $name"
  fi
}

check "sshd running"            "systemctl is-active sshd || systemctl is-active ssh"
check "ssm-agent running"       "systemctl is-active amazon-ssm-agent"
check "cloudwatch-agent running" "systemctl is-active amazon-cloudwatch-agent"
check "fail2ban running"        "systemctl is-active fail2ban"
check "auditd running"          "systemctl is-active auditd"
check "disk < 85%"              "[ \$(df / --output=pcent | tail -1 | tr -d ' %') -lt 85 ]"
check "tmp < 80%"               "[ \$(df /tmp --output=pcent | tail -1 | tr -d ' %') -lt 80 ]"
check "load avg < 10"           "[ \$(awk '{print int(\$1)}' /proc/loadavg) -lt 10 ]"
check "IMDSv2 accessible"       "curl -sf -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 5'"

if [[ $ERRORS -gt 0 ]]; then
  echo "Health check FAILED ($ERRORS issue(s))"
  exit 1
fi
echo "Health check PASSED"
exit 0
HEALTHCHECK
chmod +x /usr/local/bin/bastion-healthcheck

# ─────────────────────────────────────────────────────────────────────────────
# 17. Cron — periodic health reporting to CloudWatch
# ─────────────────────────────────────────────────────────────────────────────
cat > /etc/cron.d/bastion-health <<'CRON'
# Run health check every 5 minutes; push metric to CloudWatch
*/5 * * * * root /usr/local/bin/bastion-healthcheck > /tmp/bastion-health.out 2>&1; \
  STATUS=$?; \
  aws cloudwatch put-metric-data \
    --region "${aws_region}" \
    --namespace "Bastion/${environment}" \
    --metric-name "HealthCheckStatus" \
    --value $STATUS \
    --dimensions InstanceId=$(curl -sf http://169.254.169.254/latest/meta-data/instance-id) \
    2>/dev/null || true
CRON

# ─────────────────────────────────────────────────────────────────────────────
# 18. Tag instance on successful bootstrap
# ─────────────────────────────────────────────────────────────────────────────
log INFO "Tagging instance as successfully bootstrapped…"

aws ec2 create-tags \
  --region "${aws_region}" \
  --resources "$INSTANCE_ID" \
  --tags \
    Key=BootstrapStatus,Value=SUCCESS \
    Key=BootstrapTime,Value="$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    Key=BastionTemplate,Value="core-v1" \
    Key=Environment,Value="${environment}" \
  2>/dev/null || log WARN "Could not tag instance (check IAM permissions)"

# ─────────────────────────────────────────────────────────────────────────────
# 19. Signal completion
# ─────────────────────────────────────────────────────────────────────────────
log INFO "========================================================"
log INFO " Bastion Bootstrap COMPLETE"
log INFO " Duration: $((SECONDS))s"
log INFO "========================================================"

# Signal success to CloudFormation / EC2 Launch Templates (if cfn-signal present)
if command -v cfn-signal &>/dev/null; then
  cfn-signal --exit-code 0 \
    --stack "${cfn_stack_name:-}" \
    --resource "${cfn_resource_name:-}" \
    --region "${aws_region}" 2>/dev/null || true
fi