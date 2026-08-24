#!/bin/bash
# Slice 08 - cold stop: block scans -> drain CE -> backup -> verify -> destroy.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib.sh"

drain_ce() {
  local ip="" body="" pw="" auth="" pending="" inprog="" waited=0 found=""
  ip="$(task_ip)"
  if [ -z "$ip" ] || [ "$ip" = "None" ]; then
    warn "no running task; skipping in-flight analysis check"
    return 0
  fi
  # /api/ce/activity_status requires auth; find a credential that works.
  while read -r pw; do
    [ -z "$pw" ] && continue
    auth="$(printf 'admin:%s' "$pw" | base64 | tr -d '\n')"
    body="$(sonar_api "$ip" "/api/ce/activity_status" "$auth")"
    if printf '%s' "$body" | grep -q '"pending"'; then
      found="$auth"
      break
    fi
  done < <(sonar_admin_passwords)
  if [ -z "$found" ]; then
    warn "CE status unavailable (no working credential); skipping drain - ensure no scan is running"
    return 0
  fi
  while [ "$waited" -lt 1200 ]; do
    body="$(sonar_api "$ip" "/api/ce/activity_status" "$found")"
    if ! printf '%s' "$body" | grep -q '"pending"'; then
      warn "CE status became unavailable; proceeding"
      return 0
    fi
    pending="$(printf '%s' "$body" | sed -n 's/.*"pending":[[:space:]]*\([0-9]*\).*/\1/p')"
    inprog="$(printf '%s' "$body" | sed -n 's/.*"inProgress":[[:space:]]*\([0-9]*\).*/\1/p')"
    pending="${pending:-0}"
    inprog="${inprog:-0}"
    if [ "$pending" = "0" ] && [ "$inprog" = "0" ]; then
      log "CE queue drained (pending=0, inProgress=0)"
      return 0
    fi
    log "CE activity: pending=${pending} inProgress=${inprog}; waiting..."
    sleep 20
    waited=$((waited + 20))
  done
  warn "CE queue did not drain within 1200s; proceeding (pg_dump snapshot is consistent)"
}

wait_for_no_tasks() {
  local waited=0
  while [ "$waited" -lt 300 ]; do
    [ -z "$(task_arn)" ] && { log "No tasks running"; return 0; }
    sleep 10
    waited=$((waited + 10))
  done
  warn "tasks still present after 300s; continuing to host termination"
}

terminate_host() {
  local id="$1" state="" waited=0
  "${AWS[@]}" autoscaling update-auto-scaling-group \
    --auto-scaling-group-name "$ASG" --min-size 0 --desired-capacity 0 >/dev/null
  # ECS holds scale-down in Terminating:Wait via its draining lifecycle hook;
  # complete it as soon as it appears so the instance actually terminates.
  while [ "$waited" -lt 600 ]; do
    state="$("${AWS[@]}" autoscaling describe-auto-scaling-groups \
      --auto-scaling-group-names "$ASG" \
      --query "AutoScalingGroups[0].Instances[?InstanceId=='${id}'].LifecycleState | [0]" \
      --output text 2>/dev/null || true)"
    case "$state" in
      "Terminating:Wait")
        log "Completing draining hook ${DRAIN_HOOK} for ${id}"
        "${AWS[@]}" autoscaling complete-lifecycle-action \
          --auto-scaling-group-name "$ASG" \
          --lifecycle-hook-name "$DRAIN_HOOK" \
          --instance-id "$id" \
          --lifecycle-action-result CONTINUE >/dev/null 2>&1 || true
        ;;
      "Terminated"|"None"|"")
        return 0
        ;;
    esac
    sleep 10
    waited=$((waited + 10))
  done
  warn "host $id still not terminated after 600s"
}

wait_for_termination() {
  local id="$1" state="" waited=0
  while [ "$waited" -lt 600 ]; do
    state="$("${AWS[@]}" ec2 describe-instances --instance-ids "$id" \
      --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null || true)"
    case "$state" in
      "terminated") log "Instance ${id} terminated (EBS delete_on_termination)"; return 0;;
      "None"|"")   log "Instance ${id} no longer present"; return 0;;
    esac
    sleep 10
    waited=$((waited + 10))
  done
  warn "instance ${id} still in state '${state}' after 600s"
}

log "Cold stop: ${SERVICE} on ${CLUSTER}"

id="$(host_instance_id)"
if [ -z "$id" ]; then
  log "No in-service host; already cold-off."
  exit 0
fi
log "Host: ${id}"

log "1/6 block new scans + wait for in-flight analysis to drain"
drain_ce

log "2/6 backup & verify (pg_dump -> S3 + SHA-256)"
run_on_host "$DIR/backup-and-verify.sh"

log "3/6 teardown guard (require a verified dump before destroying)"
run_on_host "$DIR/teardown-guard.sh"

log "4/6 stop the task (service desired-count 0)"
"${AWS[@]}" ecs update-service --cluster "$CLUSTER" --service "$SERVICE" \
  --desired-count 0 >/dev/null
wait_for_no_tasks

log "5/6 terminate host (ASG desired 0) + complete ECS draining hook"
terminate_host "$id"

log "6/6 verify cold-off (instance terminated, EBS deleted)"
wait_for_termination "$id"

log "Cold stop complete. Recovery point: s3://${BUCKET}/metadata/latest.txt"
