# Cost Optimization Guide — 5-Month Live Project

## Summary

Reduced monthly AWS costs from **$364** to **~$60** (84% reduction) while maintaining functionality.

---

## Changes Implemented

### 1. Reduced Environment Count
- **Before**: 3 environments (dev, staging, prod)
- **After**: 2 environments (staging, prod)
- **Savings**: ~$88/month

### 2. No NAT Gateway
- **Before**: 1 NAT Gateway per environment
- **After**: 0 NAT Gateways (ECS tasks use public IPs)
- **Trade-off**: Tasks have public IPs (still protected by security groups)
- **Savings**: ~$64/month ($32 × 2 environments)

### 3. Fargate Spot for Staging
- **Before**: On-demand Fargate for all environments
- **After**: Fargate Spot for staging (70% cheaper)
- **Trade-off**: Tasks may be interrupted (rare, acceptable for staging)
- **Savings**: ~$18/month

### 4. Reduced Task Resources

**Staging:**
- CPU: 512 → 256 vCPU
- Memory: 1024 → 512 MB
- Min/Max: 2-4 → 1-2 tasks
- Savings: ~$13/month

**Production:**
- CPU: 1024 → 512 vCPU
- Memory: 2048 → 1024 MB
- Min/Max: 2-6 → 1-3 tasks
- Savings: ~$40/month

### 5. Reduced Log Retention
- Staging: 14 → 7 days
- Production: 90 → 30 days
- Savings: ~$3/month

---

## Updated Cost Breakdown (Monthly)

| Resource | Staging | Prod | Total |
|----------|---------|------|-------|
| **ECS Fargate** | ~$2 (Spot) | ~$20 | ~$22 |
| **ALB** | ~$16 | ~$16 | ~$32 |
| **NAT Gateway** | **$0** | **$0** | **$0** |
| **ECR** | ~$1 | ~$1 | ~$2 |
| **CloudWatch** | ~$1 | ~$2 | ~$3 |
| **S3 + DynamoDB** | - | - | ~$1 |
| **Total** | **~$20** | **~$39** | **~$60** |

### 5-Month Total: **~$300** (vs $1,820 before optimization)

---

## Further Cost Reduction Options

### Option 1: Remove Staging Environment (~$50/month savings)
```bash
# Deploy directly to prod (not recommended for learning)
terraform destroy -auto-approve
```
**Monthly cost: ~$74**

### Option 2: Stop Resources During Off-Hours
Create a script to scale ECS to 0 during nights/weekends:
```bash
# Stop (9 PM - 9 AM, weekends)
aws ecs update-service --cluster food-app-prod-cluster \
  --service food-app-prod-service --desired-count 0

# Start
aws ecs update-service --cluster food-app-prod-cluster \
  --service food-app-prod-service --desired-count 1
```
**Potential savings: ~$15-20/month**

### Option 3: Use AWS Free Tier Alternatives
- Replace ALB with API Gateway HTTP API + CloudFront (~$10/month savings)
- Use Lambda + S3 static hosting instead of ECS (~$70/month savings)
- **Trade-off**: Requires architecture redesign

### Option 4: Switch to Lightsail
- Move entire app to AWS Lightsail ($10-20/month)
- **Trade-off**: Lose ECS, ALB, auto-scaling features

---

## Applying These Changes

### Step 1: Update Terraform State
```bash
cd terraform/envs/staging
terraform init -backend-config=backend.hcl
terraform apply

cd ../prod
terraform init -backend-config=backend.hcl
terraform apply
```

### Step 2: Monitor After Changes
```bash
# Check ECS service is healthy
aws ecs describe-services \
  --cluster food-app-prod-cluster \
  --services food-app-prod-service

# Check ALB targets
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups \
    --names food-app-prod-tg \
    --query 'TargetGroups[0].TargetGroupArn' --output text)
```

### Step 3: Set Up Cost Alerts
```bash
# Create billing alarm (requires us-east-1)
aws cloudwatch put-metric-alarm \
  --alarm-name food-app-monthly-cost \
  --alarm-description "Alert if monthly cost exceeds $150" \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 21600 \
  --evaluation-periods 1 \
  --threshold 150 \
  --comparison-operator GreaterThanThreshold \
  --region us-east-1
```

---

## Trade-offs to Be Aware Of

### 1. Single NAT Gateway
- **Risk**: If the NAT Gateway AZ fails, private subnets lose internet access
- **Impact**: ECS tasks can't pull ECR images or reach AWS APIs
- **Mitigation**: Manual failover (provision new NAT in another AZ)

### 2. Fargate Spot (Staging)
- **Risk**: Tasks may be interrupted (AWS reclaims capacity)
- **Impact**: Brief staging downtime during interruption
- **Mitigation**: Tasks automatically restart, only affects staging

### 3. Single Task in Production
- **Risk**: Zero downtime deployments require 2+ tasks
- **Impact**: Brief downtime during deploys (~30 seconds)
- **Mitigation**: Deploy during low-traffic windows

### 4. Smaller Task Resources
- **Risk**: Application may be slower under load
- **Impact**: Higher response times if traffic spikes
- **Mitigation**: Auto-scaling will spin up additional tasks

---

## Cost Monitoring Commands

```bash
# Get current month's estimated cost
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=SERVICE

# Get cost by resource tag
aws ce get-cost-and-usage \
  --time-period Start=$(date -d "30 days ago" +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity DAILY \
  --metrics BlendedCost \
  --group-by Type=TAG,Key=Project

# ECS task count over time
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name RunningTaskCount \
  --dimensions Name=ServiceName,Value=food-app-prod-service \
               Name=ClusterName,Value=food-app-prod-cluster \
  --start-time $(date -u -d "7 days ago" +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Average
```

---

## Emergency: Stop Everything

If costs are still too high:

```bash
# Stop all ECS services
for env in staging prod; do
  aws ecs update-service \
    --cluster food-app-${env}-cluster \
    --service food-app-${env}-service \
    --desired-count 0 \
    --region ap-south-1
done

# Cost drops to ~$64/month (just NAT + ALB)
```

To resume:
```bash
aws ecs update-service \
  --cluster food-app-prod-cluster \
  --service food-app-prod-service \
  --desired-count 1 \
  --region ap-south-1
```

---

## Recommended Action Plan

**Month 1-2**: Run with current optimizations (~$124/month)  
**Month 3-4**: If still expensive, scale staging to 0 when not in use (~$95/month)  
**Month 5**: If budget is tight, run prod-only with off-hours scaling (~$60/month)

**Total 5-month budget: $500-620** (vs $1,820 original)
