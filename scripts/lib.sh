#!/bin/bash
# Shared helpers for the SonarQube ECS lifecycle orchestration (Slice 08).
#
# These run on your workstation (NOT the host). They drive `terraform` and the
# AWS CLI and reach the ECS host over SSM SendCommand to execute the host-side
# scripts (backup-and-verify.sh, restore.sh, teardown-guard.sh).
set -euo pipefail

# --- Configuration (all overridable via environment) ------------------------
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_PROFILE="${AWS_PROFILE:-jra-platform-terraform}"
CLUSTER="${CLUSTER:-jra-sonarqube}"
SERVICE="${SERVICE:-jra-sonarqube}"
ASG="${ASG:-jra-sonarqube-asg}"
BUCKET="${BUCKET:-jra-sonarqube-dumps}"
LOG_GROUP="${LOG_GROUP:-/ecs/jra-sonarqube}"
DRAIN_HOOK="${DRAIN_HOOK:-ecs-managed-draining-termination-hook}"

AWS=(aws --region "$AWS_REGION" --profile "$AWS_PROFILE")

log()  { printf '==> %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# --- Host discovery ---------------------------------------------------------

# The in-service instance ID of the ECS host ASG, or "" when scaled to 0.
host_instance_id() {
  local id
  id="$("${AWS[@]}" autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG" \
    --query "AutoScalingGroups[0].Instances[?LifecycleState=='InService'].InstanceId | [0]" \
    --output text 2>/dev/null || true)"
  if [ -z "$id" ] || [ "$id" = "None" ]; then
    echo ""
  else
    echo "$id"
  fi
}

# Wait until the ASG has an in-service instance that SSM can reach.
# Prints the instance id on success.
wait_for_host() {
  local timeout="${1:-900}"
  local id="" waited=0
  while [ "$waited" -lt "$timeout" ]; do
    id="$(host_instance_id)"
    if [ -n "$id" ]; then
      wait_ssm_online "$id"
      echo "$id"
      return 0
    fi
    sleep 10
    waited=$((waited + 10))
  done
  fail "no in-service host after ${timeout}s (ECS managed scaling is slow; see runbook)"
}

wait_ssm_online() {
  local id="$1" status="" waited=0
  while [ "$waited" -lt 300 ]; do
    status="$("${AWS[@]}" ssm describe-instance-information \
      --filters "Key=InstanceIds,Values=$id" \
      --query 'InstanceInformationList[0].PingStatus' \
      --output text 2>/dev/null || true)"
    [ "$status" = "Online" ] && return 0
    sleep 10
    waited=$((waited + 10))
  done
  fail "instance $id never became SSM-managed (Online)"
}

# --- SSM plumbing -----------------------------------------------------------

# Send a shell command to an instance; prints the command id.
ssm_send() {
  local id="$1" cmd="$2"
  "${AWS[@]}" ssm send-command \
    --instance-ids "$id" \
    --document-name "AWS-RunShellScript" \
    --comment "jra-sonarqube orchestration" \
    --parameters "commands=[\"$cmd\"]" \
    --output text --query 'Command.CommandId'
}

# Wait for an SSM command to finish. On success prints stdout and returns 0;
# on failure prints stdout+stderr and returns 1.
ssm_wait() {
  local cmd_id="$1" id="$2" status="" waited=0
  while [ "$waited" -lt 1800 ]; do
    status="$("${AWS[@]}" ssm get-command-invocation \
      --command-id "$cmd_id" --instance-id "$id" \
      --query 'Status' --output text 2>/dev/null || true)"
    case "$status" in
      Success)
        "${AWS[@]}" ssm get-command-invocation --command-id "$cmd_id" --instance-id "$id" \
          --query 'StandardOutputContent' --output text 2>/dev/null || true
        return 0
        ;;
      Failed|Cancelled|TimedOut)
        "${AWS[@]}" ssm get-command-invocation --command-id "$cmd_id" --instance-id "$id" \
          --query 'StandardOutputContent' --output text 2>/dev/null || true
        "${AWS[@]}" ssm get-command-invocation --command-id "$cmd_id" --instance-id "$id" \
          --query 'StandardErrorContent' --output text >&2 2>/dev/null || true
        return 1
        ;;
    esac
    sleep 5
    waited=$((waited + 5))
  done
  warn "SSM command $cmd_id timed out after 1800s"
  return 1
}

# Run a local host-side script (restore/backup/teardown) on the host via SSM.
# The script is base64-transported, decoded to /tmp, and executed as root.
run_on_host() {
  local script="$1"; shift
  local id name b64 cmd cmd_id attempt
  id="$(host_instance_id)"
  [ -z "$id" ] && fail "no in-service host to run $(basename "$script") on"
  wait_ssm_online "$id"

  name="$(basename "$script")"
  b64="$(base64 < "$script" | tr -d '\n')"
  cmd="echo '$b64' | base64 -d > /tmp/${name} && chmod +x /tmp/${name} && /tmp/${name} $*"

  log "Running ${name} on ${id}"
  # Retry on transient AccessDenied (IAM inline-policy propagation can lag a few
  # seconds after a terraform apply that touches the role).
  cmd_id=""
  for attempt in 1 2 3 4 5; do
    if cmd_id="$(ssm_send "$id" "$cmd" 2>/dev/null)"; then
      [ -n "$cmd_id" ] && [ "$cmd_id" != "None" ] && break
    fi
    warn "SSM send-command failed (attempt ${attempt}/5); retrying after IAM-propagation delay..."
    sleep 20
  done
  [ -n "$cmd_id" ] && [ "$cmd_id" != "None" ] || fail "SSM send-command failed after 5 attempts"
  ssm_wait "$cmd_id" "$id" || fail "host-side script ${name} failed"
}

# --- ECS task helpers -------------------------------------------------------

# ARN of the newest RUNNING task for the service, or "".
task_arn() {
  local arn
  arn="$("${AWS[@]}" ecs list-tasks --cluster "$CLUSTER" --service-name "$SERVICE" \
    --desired-status RUNNING --query 'taskArns[0]' --output text 2>/dev/null || true)"
  if [ -z "$arn" ] || [ "$arn" = "None" ]; then echo ""; else echo "$arn"; fi
}

# Private IP of the SonarQube task (awsvpc ENI), or "".
task_ip() {
  local arn
  arn="$(task_arn)"
  [ -z "$arn" ] && { echo ""; return 0; }
  "${AWS[@]}" ecs describe-tasks --cluster "$CLUSTER" --tasks "$arn" \
    --query 'tasks[0].containers[0].networkInterfaces[0].privateIpv4Address' \
    --output text 2>/dev/null || true
}

# Fetch the SonarQube admin password from Secrets Manager (best-effort; "" if unavailable).
sonar_admin_password() {
  local raw
  raw="$("${AWS[@]}" secretsmanager get-secret-value --secret-id sonarqube/admin \
    --query 'SecretString' --output text 2>/dev/null || true)"
  [ -z "$raw" ] && { echo ""; return 0; }
  case "$raw" in
    *'"password"'*)
      printf '%s' "$raw" | sed -n 's/.*"password"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
      ;;
    *) printf '%s' "$raw" ;;
  esac
}

# curl a SonarQube API path from the host (which can reach the task ENI).
# Usage: sonar_api <task-ip> <path> [auth_base64]
sonar_api() {
  local ip="$1" path="$2" auth="${3:-}"
  local id cmd cid out
  id="$(host_instance_id)"; [ -z "$id" ] && return 1
  if [ -n "$auth" ]; then
    cmd="curl -fsS -H 'Authorization: Basic ${auth}' http://${ip}:9000${path} 2>/dev/null || true"
  else
    cmd="curl -fsS http://${ip}:9000${path} 2>/dev/null || true"
  fi
  cid="$(ssm_send "$id" "$cmd")"
  out="$(ssm_wait "$cid" "$id" 2>/dev/null || true)"
  printf '%s' "$out"
}

# Return 0 if SonarQube reports "UP" on the given task IP.
sonar_up() {
  local ip="$1" body
  body="$(sonar_api "$ip" "/api/system/status")"
  printf '%s' "$body" | grep -q '"status":"UP"'
}

