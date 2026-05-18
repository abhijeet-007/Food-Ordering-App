#!/bin/bash
# Usage: rollback.sh <cluster> <service> <previous-task-def-arn> <region>
set -e

CLUSTER=$1
SERVICE=$2
PREV_TASK_DEF=$3
REGION=$4

echo "Rolling back $SERVICE to $PREV_TASK_DEF"

aws ecs update-service \
  --cluster "$CLUSTER" \
  --service "$SERVICE" \
  --task-definition "$PREV_TASK_DEF" \
  --region "$REGION" \
  --force-new-deployment

echo "Waiting for rollback to stabilize..."
aws ecs wait services-stable \
  --cluster "$CLUSTER" \
  --services "$SERVICE" \
  --region "$REGION"

echo "Rollback complete."
