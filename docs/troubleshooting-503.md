# Troubleshooting 503 Service Unavailable

## Quick Diagnosis

503 error means the ALB cannot reach healthy ECS tasks. Let's diagnose step by step.

---

## Step 1: Check ECS Service Status

```bash
aws ecs describe-services \
  --cluster food-app-staging-cluster \
  --services food-app-staging-service \
  --region ap-south-1 \
  --query 'services[0].[desiredCount,runningCount,pendingCount,deployments[0].status]' \
  --output table
```

**What to look for:**
- `desiredCount`: Should be > 0
- `runningCount`: Should equal desiredCount
- `pendingCount`: Should be 0
- If runningCount is 0, tasks aren't starting

---

## Step 2: Check Task Status

```bash
# List recent tasks
aws ecs list-tasks \
  --cluster food-app-staging-cluster \
  --service-name food-app-staging-service \
  --region ap-south-1

# If no tasks, check stopped tasks
aws ecs list-tasks \
  --cluster food-app-staging-cluster \
  --desired-status STOPPED \
  --region ap-south-1
```

---

## Step 3: Check Why Tasks Are Failing

```bash
# Get the most recent task ARN
TASK_ARN=$(aws ecs list-tasks \
  --cluster food-app-staging-cluster \
  --service-name food-app-staging-service \
  --desired-status STOPPED \
  --region ap-south-1 \
  --query 'taskArns[0]' \
  --output text)

# Get detailed failure reason
aws ecs describe-tasks \
  --cluster food-app-staging-cluster \
  --tasks $TASK_ARN \
  --region ap-south-1 \
  --query 'tasks[0].[lastStatus,stopCode,stoppedReason,containers[0].reason]' \
  --output table
```

---

## Common Issues & Fixes

### Issue 1: "CannotPullContainerError: pull image manifest"

**Cause:** No image in ECR or wrong tag

**Check ECR:**
```bash
aws ecr describe-images \
  --repository-name food-app-staging \
  --region ap-south-1 \
  --query 'imageDetails[*].imageTags' \
  --output table
```

**Fix Option A: Build and push image**
```bash
# Get ECR login
aws ecr get-login-password --region ap-south-1 | \
  docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com

# Build and push
cd /path/to/infra-as-code-pipeline
docker build -t food-app-staging .
docker tag food-app-staging:latest <ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com/food-app-staging:latest
docker push <ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com/food-app-staging:latest
```

**Fix Option B: Update task to use existing tag**
```bash
# Check what tags exist
aws ecr list-images \
  --repository-name food-app-staging \
  --region ap-south-1

# Update terraform.tfvars with existing tag
# Or force new deployment
aws ecs update-service \
  --cluster food-app-staging-cluster \
  --service food-app-staging-service \
  --force-new-deployment \
  --region ap-south-1
```

---

### Issue 2: "ResourceInitializationError: unable to pull secrets"

**Cause:** ECS execution role can't access secrets

**Fix:**
```bash
# Check if execution role has SSM permissions
aws iam get-role-policy \
  --role-name food-app-staging-ecs-execution-role \
  --policy-name ssm-access \
  --region ap-south-1
```

---

### Issue 3: Tasks starting but failing health checks

**Cause:** Security group blocking ALB → ECS communication

**Check security groups:**
```bash
# Get ECS security group
ECS_SG=$(aws ecs describe-services \
  --cluster food-app-staging-cluster \
  --services food-app-staging-service \
  --region ap-south-1 \
  --query 'services[0].networkConfiguration.awsvpcConfiguration.securityGroups[0]' \
  --output text)

# Get ALB security group
ALB_SG=$(aws elbv2 describe-load-balancers \
  --names food-app-staging-alb \
  --region ap-south-1 \
  --query 'LoadBalancers[0].SecurityGroups[0]' \
  --output text)

# Check ECS security group rules
aws ec2 describe-security-groups \
  --group-ids $ECS_SG \
  --region ap-south-1 \
  --query 'SecurityGroups[0].IpPermissions'
```

**Fix: Ensure ECS SG allows port 80 from ALB SG**
```bash
aws ec2 authorize-security-group-ingress \
  --group-id $ECS_SG \
  --protocol tcp \
  --port 80 \
  --source-group $ALB_SG \
  --region ap-south-1
```

---

### Issue 4: "Cannot reach internet" (ECR pull fails)

**Cause:** After NAT removal, tasks need public IPs and proper routes

**Check task has public IP:**
```bash
TASK_ARN=$(aws ecs list-tasks \
  --cluster food-app-staging-cluster \
  --service-name food-app-staging-service \
  --region ap-south-1 \
  --query 'taskArns[0]' \
  --output text)

aws ecs describe-tasks \
  --cluster food-app-staging-cluster \
  --tasks $TASK_ARN \
  --region ap-south-1 \
  --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`]'
```

**Fix: Ensure service is configured correctly**
```bash
# Verify assign_public_ip is true in Terraform
cd terraform/envs/staging
grep -A5 "network_configuration" main.tf
# Should show: assign_public_ip = true

# Re-apply Terraform
terraform apply
```

---

### Issue 5: Desired count is 0

**Quick Fix:**
```bash
aws ecs update-service \
  --cluster food-app-staging-cluster \
  --service food-app-staging-service \
  --desired-count 1 \
  --region ap-south-1
```

---

## Step 4: Check ALB Target Health

```bash
# Get target group ARN
TG_ARN=$(aws elbv2 describe-target-groups \
  --names food-app-staging-tg \
  --region ap-south-1 \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

# Check target health
aws elbv2 describe-target-health \
  --target-group-arn $TG_ARN \
  --region ap-south-1
```

**Possible states:**
- `initial`: Still registering (wait 30s)
- `healthy`: Good! But 503 means no healthy targets
- `unhealthy`: Health checks failing
- `draining`: Task is stopping
- `unavailable`: No targets registered

---

## Step 5: Check CloudWatch Logs

```bash
# Stream logs in real-time
aws logs tail /ecs/food-app/staging --follow --region ap-south-1

# Or check recent logs
aws logs tail /ecs/food-app/staging --since 10m --region ap-south-1
```

**Look for:**
- Container startup errors
- Application crashes
- Port binding issues

---

## Quick Fix: Force New Deployment

If tasks were running before migration:

```bash
# Scale down
aws ecs update-service \
  --cluster food-app-staging-cluster \
  --service food-app-staging-service \
  --desired-count 0 \
  --region ap-south-1

# Wait 30 seconds
sleep 30

# Scale back up with force deployment
aws ecs update-service \
  --cluster food-app-staging-cluster \
  --service food-app-staging-service \
  --desired-count 1 \
  --force-new-deployment \
  --region ap-south-1

# Monitor
watch -n 5 'aws ecs describe-services \
  --cluster food-app-staging-cluster \
  --services food-app-staging-service \
  --region ap-south-1 \
  --query "services[0].[desiredCount,runningCount,pendingCount]"'
```

---

## Complete Diagnostic Report

Run this to get a full picture:

```bash
#!/bin/bash
echo "=== ECS Service Status ==="
aws ecs describe-services \
  --cluster food-app-staging-cluster \
  --services food-app-staging-service \
  --region ap-south-1 \
  --query 'services[0].[desiredCount,runningCount,pendingCount,deployments[0]]'

echo ""
echo "=== Recent Events ==="
aws ecs describe-services \
  --cluster food-app-staging-cluster \
  --services food-app-staging-service \
  --region ap-south-1 \
  --query 'services[0].events[:5]'

echo ""
echo "=== Task Status ==="
TASK_ARN=$(aws ecs list-tasks \
  --cluster food-app-staging-cluster \
  --desired-status STOPPED \
  --region ap-south-1 \
  --query 'taskArns[0]' \
  --output text)

if [ "$TASK_ARN" != "None" ]; then
  aws ecs describe-tasks \
    --cluster food-app-staging-cluster \
    --tasks $TASK_ARN \
    --region ap-south-1 \
    --query 'tasks[0].[lastStatus,stoppedReason,containers[0].reason]'
fi

echo ""
echo "=== ALB Target Health ==="
TG_ARN=$(aws elbv2 describe-target-groups \
  --names food-app-staging-tg \
  --region ap-south-1 \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

aws elbv2 describe-target-health \
  --target-group-arn $TG_ARN \
  --region ap-south-1

echo ""
echo "=== ECR Images ==="
aws ecr describe-images \
  --repository-name food-app-staging \
  --region ap-south-1 \
  --query 'imageDetails[*].[imageTags,imagePushedAt]' \
  --max-items 5
```

---

## Most Likely Issue After Migration

**If this happened right after applying Terraform changes:**

The issue is probably that **no Docker image exists in ECR yet**, or the image tag in the task definition doesn't match.

**Solution:**

1. **Check if ECR repository has images:**
```bash
aws ecr describe-images \
  --repository-name food-app-staging \
  --region ap-south-1
```

2. **If empty, push an image:**
```bash
# Get your AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Login to ECR
aws ecr get-login-password --region ap-south-1 | \
  docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.ap-south-1.amazonaws.com

# Build and push
docker build -t food-app-staging .
docker tag food-app-staging:latest ${ACCOUNT_ID}.dkr.ecr.ap-south-1.amazonaws.com/food-app-staging:latest
docker push ${ACCOUNT_ID}.dkr.ecr.ap-south-1.amazonaws.com/food-app-staging:latest
```

3. **Update ECS service:**
```bash
aws ecs update-service \
  --cluster food-app-staging-cluster \
  --service food-app-staging-service \
  --force-new-deployment \
  --region ap-south-1
```

---

## Still Having Issues?

Share the output of these commands:

```bash
# 1. Service status
aws ecs describe-services \
  --cluster food-app-staging-cluster \
  --services food-app-staging-service \
  --region ap-south-1 \
  --query 'services[0].events[:3]'

# 2. Task failure reason
aws ecs list-tasks \
  --cluster food-app-staging-cluster \
  --desired-status STOPPED \
  --region ap-south-1

# 3. CloudWatch logs
aws logs tail /ecs/food-app/staging --since 5m --region ap-south-1
```
