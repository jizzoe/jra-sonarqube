#!/bin/bash
# Slice 08 - status / health / logs for the SonarQube ECS singleton.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib.sh"

usage() { echo "usage: $0 [status|health|logs [sonarqube|postgres]]" >&2; exit 2; }

do_status() {
  local id="" arn="" ip="" meta="" eip_out=""
  id="$(host_instance_id)"
  arn="$(task_arn)"
  ip="$(task_ip)"

  echo "Cluster : ${CLUSTER}"
  echo "Service : ${SERVICE}"
  echo "ASG     : ${ASG}"
  echo "Host    : ${id:-<none (cold-off)>}"
  echo "Task    : ${arn:-<none>}"
  [ -n "$ip" ] && [ "$ip" != "None" ] && echo "Task IP : ${ip}"
  if [ -n "$id" ]; then
    eip_out="$(find_eip "$id")"
    [ -n "$eip_out" ] && echo "EIP     : $(echo "$eip_out" | awk '{print $3}') (https://${DOMAIN})"
  fi

  echo "--- service ---"
  "${AWS[@]}" ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
    --query 'services[0].{desiredCount:desiredCount,runningCount:runningCount,pendingCount:pendingCount}' \
    --output json 2>/dev/null || echo "  (unavailable)"

  echo "--- backup (latest verified dump) ---"
  meta="$("${AWS[@]}" s3 cp "s3://${BUCKET}/metadata/latest.txt" - 2>/dev/null || true)"
  echo "  ${meta:-<none>}"

  echo "--- health ---"
  if [ -z "$id" ]; then
    echo "  SonarQube: cold-off (no host)"
  elif [ -n "$ip" ] && [ "$ip" != "None" ] && sonar_up "$ip"; then
    echo "  SonarQube: UP (${ip}:9000)"
  else
    echo "  SonarQube: DOWN / booting"
  fi
}

do_health() {
  local id="" ip=""
  id="$(host_instance_id)"
  ip="$(task_ip)"
  if [ -z "$id" ]; then
    echo "SonarQube: cold-off (no host)"; exit 1
  fi
  if [ -n "$ip" ] && [ "$ip" != "None" ] && sonar_up "$ip"; then
    echo "SonarQube: UP (${ip}:9000)"; exit 0
  fi
  echo "SonarQube: DOWN / booting (${ip:-no task IP})"; exit 1
}

do_logs() {
  local prefix="${1:-sonarqube}" stream=""
  stream="$("${AWS[@]}" logs describe-log-streams \
    --log-group-name "$LOG_GROUP" \
    --order-by LastEventTime --descending \
    --query "logStreams[?starts_with(logStreamName, '${prefix}/')] | [0].logStreamName" \
    --output text 2>/dev/null || true)"
  if [ -z "$stream" ] || [ "$stream" = "None" ]; then
    warn "no log stream for prefix '${prefix}' in ${LOG_GROUP}"
    exit 0
  fi
  echo "==> ${LOG_GROUP} / ${stream}"
  "${AWS[@]}" logs get-log-events \
    --log-group-name "$LOG_GROUP" --log-stream-name "$stream" \
    --query 'events[].message' --output text 2>/dev/null || true
}

case "${1:-status}" in
  status) do_status ;;
  health) do_health ;;
  logs)   do_logs "${2:-sonarqube}" ;;
  *)      usage ;;
esac
