# Runbook — Common Failure Scenarios

## 1. ECS Tasks Failing to Start

**Symptoms:** `pendingCount` stays > 0, `runningCount` = 0

**Steps:**
```bash
# Check stopped task reason
aws ecs describe-tasks \
  --cluster food-app-prod-cluster \
  --tasks $(aws ecs list-tasks --cluster food-app-prod-cluster --desired-status STOPPED --query 'taskArns[0]' --output text) \
  --query 'tasks[0].stoppedReason'

# Check container logs
aws logs tail /ecs/food-app/prod --follow
```

**Common causes:**
- Image not found in ECR → verify image tag was pushed
- IAM execution role missing ECR pull permission → check `ecs_execution_role`
- Container health check failing → check `health_check_path` returns 200

---

## 2. Pipeline Fails at Terraform Apply

**Symptoms:** `Error: error creating ECS service`

**Steps:**
```bash
# Check Terraform state is not locked
aws dynamodb scan --table-name food-app-terraform-locks

# Force unlock if stuck (use lock ID from error message)
terraform force-unlock <LOCK_ID>
```

---

## 3. Health Check Timeout (Rollback Triggered)

**Symptoms:** Pipeline shows "Health check FAILED", rollback runs

**Steps:**
```bash
# Check ALB target health
aws elbv2 describe-target-health \
  --target-group-arn <TARGET_GROUP_ARN>

# Check ECS service events
aws ecs describe-services \
  --cluster food-app-prod-cluster \
  --services food-app-prod-service \
  --query 'services[0].events[:5]'
```

---

## 4. ECR Push Fails (Unauthorized)

**Symptoms:** `no basic auth credentials` in pipeline

**Steps:**
- Verify `AWS_ROLE_ARN` GitHub Secret is set correctly
- Verify the IAM role trust policy allows `sts:AssumeRoleWithWebIdentity` from GitHub Actions OIDC
- Re-run the pipeline after fixing

---

## 5. Terraform State Corruption

**Symptoms:** `Error: state data in S3 does not have the expected content`

**Steps:**
```bash
# List state versions in S3
aws s3api list-object-versions \
  --bucket food-app-terraform-state-<ACCOUNT_ID> \
  --prefix prod/terraform.tfstate

# Restore previous version
aws s3api get-object \
  --bucket food-app-terraform-state-<ACCOUNT_ID> \
  --key prod/terraform.tfstate \
  --version-id <VERSION_ID> \
  terraform.tfstate.backup
```

---

## 6. Auto-scaling Not Triggering

**Symptoms:** CPU > 80% but no new tasks

**Steps:**
```bash
# Check scaling policies
aws application-autoscaling describe-scaling-policies \
  --service-namespace ecs \
  --resource-id service/food-app-prod-cluster/food-app-prod-service

# Check CloudWatch alarms
aws cloudwatch describe-alarms \
  --alarm-name-prefix food-app-prod
```
