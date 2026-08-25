#!/bin/bash
# Slice 08 - cold start: terraform apply -> restore -> reindex -> health gate.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
source "$DIR/lib.sh"

wait_for_task_running() {
  local arn="" last="" waited=0
  while [ "$waited" -lt 900 ]; do
    arn="$(task_arn)"
    if [ -n "$arn" ]; then
      last="$("${AWS[@]}" ecs describe-tasks --cluster "$CLUSTER" --tasks "$arn" \
        --query 'tasks[0].lastStatus' --output text 2>/dev/null || true)"
      [ "$last" = "RUNNING" ] && { log "Task RUNNING: ${arn}"; return 0; }
    fi
    sleep 10
    waited=$((waited + 10))
  done
  fail "task did not reach RUNNING within 900s"
}

wait_for_new_task() {
  local old="$1" arn="" waited=0
  while [ "$waited" -lt 900 ]; do
    arn="$(task_arn)"
    if [ -n "$arn" ] && [ "$arn" != "$old" ]; then
      log "New task RUNNING: ${arn}"
      return 0
    fi
    sleep 10
    waited=$((waited + 10))
  done
  warn "did not observe a new task ARN; proceeding to health gate"
}

wait_for_healthy() {
  local ip="" waited=0
  while [ "$waited" -lt 1500 ]; do
    ip="$(task_ip)"
    if [ -n "$ip" ] && [ "$ip" != "None" ] && sonar_up "$ip"; then
      log "SonarQube UP at ${ip}:9000"
      return 0
    fi
    sleep 20
    waited=$((waited + 20))
  done
  fail "SonarQube did not become healthy within 1500s"
}

log "Cold start: ${SERVICE} on ${CLUSTER}"

id="$(host_instance_id)"

if [ -n "$id" ]; then
  # A host is already up. If it was already restored this session, this is a
  # no-op; otherwise we resume the restore -> reindex -> health tail.
  marker="$("${AWS[@]}" s3 cp "s3://${BUCKET}/metadata/restored.txt" - 2>/dev/null || true)"
  if [ "$marker" = "$id" ]; then
    log "Host ${id} already restored and healthy (no-op)."
    log "To restart cleanly, run scripts/cold-stop.sh first."
    exit 0
  fi
  log "Host ${id} is up but not yet restored; resuming (restore -> reindex -> health)."
else
  log "1/8 terraform init (if needed) + apply"
  if [ ! -d "$ROOT/.terraform" ]; then
    (cd "$ROOT" && terraform init -input=false -no-color)
  fi
  (cd "$ROOT" && terraform apply -auto-approve -no-color)

  log "2/8 ensure host capacity (ECS managed scaling is slow; nudge ASG desired 1)"
  "${AWS[@]}" autoscaling update-auto-scaling-group \
    --auto-scaling-group-name "$ASG" --desired-capacity 1 >/dev/null

  id="$(wait_for_host 900)"
  log "Host up: ${id}"
fi

log "3/8 wait for the task to reach RUNNING"
wait_for_task_running

log "4/8 restore newest verified dump + clear Elasticsearch index"
run_on_host "$DIR/restore.sh"

log "5/8 force new deployment (SonarQube reindexes from the restored DB)"
old_arn="$(task_arn)"
"${AWS[@]}" ecs update-service --cluster "$CLUSTER" --service "$SERVICE" \
  --force-new-deployment >/dev/null
wait_for_new_task "$old_arn"

log "6/8 health gate (/api/system/status = UP)"
wait_for_healthy

printf '%s' "$id" | "${AWS[@]}" s3 cp - "s3://${BUCKET}/metadata/restored.txt" >/dev/null

log "7/8 allocate + associate Elastic IP"
eip_ip=""
existing_eip="$(find_eip "$id")"
if [ -n "$existing_eip" ]; then
  eip_ip="$(echo "$existing_eip" | awk '{print $3}')"
  log "Reusing Elastic IP ${eip_ip}"
else
  new_eip="$(allocate_eip)"
  associate_eip "$(echo "$new_eip" | awk '{print $1}')" "$id"
  eip_ip="$(echo "$new_eip" | awk '{print $2}')"
  log "Elastic IP ${eip_ip} associated with ${id}"
fi

log "8/8 upsert A record + start TLS proxy"
zone="$(hosted_zone_id)"
if [ -z "$zone" ] || [ "$zone" = "None" ]; then
  warn "hosted zone not found; skipping A record + TLS proxy"
else
  a_record_upsert "$DOMAIN" "$eip_ip" "$zone"
  final_ip="$(task_ip)"
  run_on_host "$DIR/proxy-start.sh" "$DOMAIN" "$final_ip" "$zone" "$BUCKET"
fi

log "Cold start complete. SonarQube UP; public at https://${DOMAIN} (${eip_ip:-no EIP})."
