#!/bin/bash
# Usage: health-check.sh <env> <region> <project>
set -e

ENV=$1
REGION=$2
PROJECT=$3
CLUSTER="${PROJECT}-${ENV}-cluster"
SERVICE="${PROJECT}-${ENV}-service"
TIMEOUT=300   # 5 minutes
INTERVAL=15
ELAPSED=0

echo "Health check: $SERVICE in $CLUSTER"

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

  echo "[${ELAPSED}s] running=${RUNNING} desired=${DESIRED} pending=${PENDING}"

  if [ "$RUNNING" -eq "$DESIRED" ] && [ "$PENDING" -eq 0 ]; then
    echo "Health check passed."
    exit 0
  fi

  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))
done

echo "Health check FAILED after ${TIMEOUT}s — triggering rollback"
exit 1
