#!/bin/bash
# Usage: health-check.sh <env> <region> <project>
set -e

ENV=$1
REGION=$2
PROJECT=$3
CLUSTER="${PROJECT}-${ENV}-cluster"
SERVICE="${PROJECT}-${ENV}-service"
TIMEOUT=300
INTERVAL=15
ELAPSED=0

echo "Health check: $SERVICE in $CLUSTER"

# Get target group ARN
TG_ARN=$(aws elbv2 describe-target-groups \
  --region "$REGION" \
  --query "TargetGroups[?contains(TargetGroupName, '${PROJECT}-${ENV}')].TargetGroupArn" \
  --output text)

echo "Target Group: $TG_ARN"

while [ $ELAPSED -lt $TIMEOUT ]; do
  RUNNING=$(aws ecs describe-services \
    --cluster "$CLUSTER" \
    --services "$SERVICE" \
    --region "$REGION" \
    --query 'services[0].runningCount' \
    --output text)

  DESIRED=$(aws ecs describe-services \
    --cluster "$CLUSTER" \
    --services "$SERVICE" \
    --region "$REGION" \
    --query 'services[0].desiredCount' \
    --output text)

  PENDING=$(aws ecs describe-services \
    --cluster "$CLUSTER" \
    --services "$SERVICE" \
    --region "$REGION" \
    --query 'services[0].pendingCount' \
    --output text)

  # Check ALB target health
  HEALTHY=$(aws elbv2 describe-target-health \
    --target-group-arn "$TG_ARN" \
    --region "$REGION" \
    --query "length(TargetHealthDescriptions[?TargetHealth.State=='healthy'])" \
    --output text)

  echo "[${ELAPSED}s] running=${RUNNING} desired=${DESIRED} pending=${PENDING} healthy=${HEALTHY}"

  # Skip check if desired is 0 (infra-only deploy)
  if [ "$DESIRED" -eq 0 ]; then
    echo "Desired count is 0 — skipping health check."
    exit 0
  fi

  # Success: All targets healthy and running
  if [ "$HEALTHY" -eq "$DESIRED" ] && [ "$RUNNING" -eq "$DESIRED" ] && [ "$PENDING" -eq 0 ]; then
    echo "Health check passed: All $HEALTHY/$DESIRED targets healthy."
    exit 0
  fi

  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))
done

echo "Health check FAILED after ${TIMEOUT}s"
echo "Final state: running=${RUNNING} desired=${DESIRED} healthy=${HEALTHY}"
exit 1
