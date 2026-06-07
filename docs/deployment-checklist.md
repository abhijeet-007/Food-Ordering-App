# Cost Optimization Deployment Checklist

## Pre-Deployment

- [ ] Review changes in [cost-summary.md](cost-summary.md)
- [ ] Understand trade-offs (single NAT, Fargate Spot, 1 task minimum)
- [ ] Backup current Terraform state (automatic via S3 versioning)
- [ ] Note current ALB URLs for testing post-deployment

---

## Deployment Steps

### Step 1: Verify Current State
```bash
# Check what's currently running
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

### Step 2: Apply Staging Changes
```bash
cd ../terraform/envs/staging
terraform init -backend-config=backend.hcl
terraform plan  # Review changes
terraform apply
```

**Expected changes:**
- NAT Gateway count: 2 → 1
- ECS task CPU: 512 → 256
- ECS task memory: 1024 → 512
- Desired count: 2 → 1
- Capacity provider: FARGATE → FARGATE_SPOT

### Step 3: Verify Staging
```bash
# Wait 2-3 minutes for deployment
aws ecs describe-services \
  --cluster food-app-staging-cluster \
  --services food-app-staging-service \
  --region ap-south-1 \
  --query 'services[0].[desiredCount,runningCount,status]'

# Test staging ALB
STAGING_URL=$(aws elbv2 describe-load-balancers \
  --names food-app-staging-alb \
  --region ap-south-1 \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

curl -I http://$STAGING_URL/health
# Should return: HTTP/1.1 200 OK
```

### Step 4: Apply Production Changes
```bash
cd ../prod
terraform init -backend-config=backend.hcl
terraform plan  # Review changes
terraform apply
```

**Expected changes:**
- NAT Gateway count: 2 → 1
- ECS task CPU: 1024 → 512
- ECS task memory: 2048 → 1024
- Desired count: 2 → 1
- Max capacity: 6 → 3

### Step 5: Verify Production
```bash
# Wait 2-3 minutes for deployment
aws ecs describe-services \
  --cluster food-app-prod-cluster \
  --services food-app-prod-service \
  --region ap-south-1 \
  --query 'services[0].[desiredCount,runningCount,status]'

# Test production ALB
PROD_URL=$(aws elbv2 describe-load-balancers \
  --names food-app-prod-alb \
  --region ap-south-1 \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

curl -I http://$PROD_URL/health
# Should return: HTTP/1.1 200 OK
```

---

## Post-Deployment

### Validation Checklist
- [ ] Staging: 1 task running
- [ ] Production: 1 task running
- [ ] Staging ALB health check passing
- [ ] Production ALB health check passing
- [ ] Application loads in browser (staging)
- [ ] Application loads in browser (production)
- [ ] Verify 1 NAT Gateway per environment

### Verify NAT Gateway Count
```bash
# Should show 1 NAT Gateway for staging
aws ec2 describe-nat-gateways \
  --filter "Name=tag:Name,Values=food-app-staging-nat-*" \
  --region ap-south-1 \
  --query 'NatGateways[?State==`available`].[NatGatewayId,Tags[?Key==`Name`].Value|[0]]' \
  --output table

# Should show 1 NAT Gateway for production
aws ec2 describe-nat-gateways \
  --filter "Name=tag:Name,Values=food-app-prod-nat-*" \
  --region ap-south-1 \
  --query 'NatGateways[?State==`available`].[NatGatewayId,Tags[?Key==`Name`].Value|[0]]' \
  --output table
```

### Verify Fargate Spot (Staging)
```bash
aws ecs describe-services \
  --cluster food-app-staging-cluster \
  --services food-app-staging-service \
  --region ap-south-1 \
  --query 'services[0].capacityProviderStrategy'

# Should show: [{"capacityProvider": "FARGATE_SPOT", "weight": 100}]
```

---

## Cost Monitoring Setup

### Set Up Monthly Budget Alert
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name food-app-monthly-budget \
  --alarm-description "Alert when monthly cost exceeds $150" \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 21600 \
  --evaluation-periods 1 \
  --threshold 150 \
  --comparison-operator GreaterThanThreshold \
  --region us-east-1
```

### Enable Cost Explorer (if not enabled)
```bash
# Via AWS Console:
# 1. Go to: https://console.aws.amazon.com/billing/home#/
# 2. Navigate to: Cost Management → Cost Explorer
# 3. Click "Enable Cost Explorer"
```

---

## Rollback Plan (If Issues)

### If Staging Has Issues
```bash
cd terraform/envs/staging

# Option 1: Revert to previous config
git checkout HEAD~1 terraform.tfvars
terraform apply

# Option 2: Scale up manually
aws ecs update-service \
  --cluster food-app-staging-cluster \
  --service food-app-staging-service \
  --desired-count 2 \
  --region ap-south-1
```

### If Production Has Issues
```bash
cd terraform/envs/prod

# Immediate fix: Scale up
aws ecs update-service \
  --cluster food-app-prod-cluster \
  --service food-app-prod-service \
  --desired-count 2 \
  --region ap-south-1

# Then revert Terraform if needed
git checkout HEAD~1 terraform.tfvars
terraform apply
```

---

## Expected Timeline

| Step | Duration | Notes |
|------|----------|-------|
| Terraform apply (staging) | 5-8 min | NAT Gateway creation takes time |
| Service stabilization (staging) | 2-3 min | Wait for new tasks |
| Terraform apply (prod) | 5-8 min | NAT Gateway creation takes time |
| Service stabilization (prod) | 2-3 min | Wait for new tasks |
| **Total** | **15-20 min** | |

---

## Success Criteria

✅ **All checks passed if:**
1. Both environments show 1/1 tasks running
2. Health checks return 200 OK
3. Applications load in browser
4. No CloudWatch alarms firing
5. Terraform state clean (no drift)

---

## Next Steps After Deployment

1. **Monitor for 24 hours**
   - Check CloudWatch metrics for CPU/Memory
   - Watch for any 5xx errors in ALB
   - Verify auto-scaling works under load

2. **Document current ALB URLs**
   ```bash
   echo "Staging: http://$(aws elbv2 describe-load-balancers --names food-app-staging-alb --region ap-south-1 --query 'LoadBalancers[0].DNSName' --output text)"
   echo "Production: http://$(aws elbv2 describe-load-balancers --names food-app-prod-alb --region ap-south-1 --query 'LoadBalancers[0].DNSName' --output text)"
   ```

3. **Weekly cost checks**
   ```bash
   aws ce get-cost-and-usage \
     --time-period Start=$(date -d "7 days ago" +%Y-%m-%d),End=$(date +%Y-%m-%d) \
     --granularity DAILY \
     --metrics BlendedCost \
     --region us-east-1
   ```

4. **Consider off-hours scaling** (Month 3+)
   - Set up EventBridge rules to scale to 0 at night
   - Scale up in the morning
   - Additional ~$15-20/month savings

---

## Contact & Support

If you encounter issues:
1. Check [runbook.md](runbook.md) for common issues
2. Review CloudWatch logs: `/ecs/food-app/{env}`
3. Check ECS service events in AWS Console

## Estimated Savings

- Monthly: **$240** (66% reduction)
- 5 Months: **$1,200**
