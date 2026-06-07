# Cost Optimization Summary — Quick Reference

## What Changed

### Infrastructure Changes
- ✅ Reduced from 3 to 2 environments (removed dev)
- ✅ **No NAT Gateway** (ECS tasks use public IPs - saves $64/month)
- ✅ Fargate Spot for staging (70% cheaper)
- ✅ Smaller ECS tasks (256-512 vCPU vs 512-1024)
- ✅ Minimum 1 task per service (was 2)
- ✅ Reduced log retention (7-30 days)

### Cost Impact
| Metric | Before | After | Savings |
|--------|--------|-------|---------|
| **Monthly** | $364 | $60 | $304 (84%) |
| **5 Months** | $1,820 | $300 | $1,520 (84%) |

---

## How to Apply Changes

### 1. Apply Terraform Updates
```bash
# Staging
cd terraform/envs/staging
terraform init -backend-config=backend.hcl
terraform apply

# Production
cd ../prod
terraform init -backend-config=backend.hcl
terraform apply
```

### 2. Verify Deployment
```bash
# Check services are healthy
aws ecs describe-services \
  --cluster food-app-staging-cluster \
  --services food-app-staging-service \
  --region ap-south-1 \
  --query 'services[0].[desiredCount,runningCount]'

aws ecs describe-services \
  --cluster food-app-prod-cluster \
  --services food-app-prod-service \
  --region ap-south-1 \
  --query 'services[0].[desiredCount,runningCount]'
```

---



## Monthly Budget Plan

| Month | Strategy | Est. Cost |
|-------|----------|-----------|
| 1-2 | Run both environments full-time | $120 |
| 3-4 | Stop staging when not in use | $78 |
| 5 | Run prod only, stop off-hours | $60 |
| **Total** | | **~$336** |

---

## Emergency Cost Reduction

If you need to cut costs immediately:

```bash
# Option 1: Stop staging completely
aws ecs update-service \
  --cluster food-app-staging-cluster \
  --service food-app-staging-service \
  --desired-count 0 \
  --region ap-south-1

# Saves ~$20/month (drops to $40/month)
```

```bash
# Option 2: Stop everything
aws ecs update-service \
  --cluster food-app-staging-cluster \
  --service food-app-staging-service \
  --desired-count 0 \
  --region ap-south-1

aws ecs update-service \
  --cluster food-app-prod-cluster \
  --service food-app-prod-service \
  --desired-count 0 \
  --region ap-south-1

# Saves ~$42/month (drops to $18/month - ALB + ECR only)
```

---

## What to Monitor

### Weekly Checks
```bash
# Check current costs
aws ce get-cost-and-usage \
  --time-period Start=$(date -d "7 days ago" +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity DAILY \
  --metrics BlendedCost \
  --region us-east-1

# Check running tasks
aws ecs describe-services \
  --cluster food-app-prod-cluster \
  --services food-app-prod-service \
  --region ap-south-1 \
  --query 'services[0].[desiredCount,runningCount]'
```

### Set Up Billing Alarm
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name food-app-budget-alert \
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

## Trade-offs Accepted

1. **No NAT Gateway**: ECS tasks have public IPs (still secured by security groups)
2. **Fargate Spot (staging)**: Rare interruptions possible
3. **1 Task Minimum**: Brief downtime during deployments
4. **Smaller Tasks**: Slower under heavy load (auto-scales up)

All acceptable for a learning/demo project running 5 months.

---

## Files Modified

```
terraform/envs/staging/terraform.tfvars  ← Reduced resources
terraform/envs/prod/terraform.tfvars     ← Reduced resources
terraform/modules/networking/main.tf     ← NAT Gateway removed
terraform/modules/compute/main.tf        ← Public IPs + Fargate Spot
```

## New Files Added

```
docs/cost-optimization.md        ← Detailed optimization guide
docs/cost-summary.md             ← This file
docs/alternative-architectures.md← Architecture comparison
docs/migration-guide.md          ← NAT removal migration guide
```

---

## Need Help?

See [cost-optimization.md](cost-optimization.md) for:
- Detailed cost breakdown
- Further optimization options
- Troubleshooting
- Recovery procedures
