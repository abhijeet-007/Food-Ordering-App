# Rollback Testing Guide

## Current State
- **Staging:** `food-app-staging:18` ✅
- **Production:** `food-app-prod:9` ✅

## Test Scenarios

### Scenario 1: Health Check Failure (Recommended)

Simulate a deployment that breaks the health endpoint.

#### Step 1: Break the Health Endpoint

Edit `nginx.conf`:

```nginx
# Change this:
location /health {
    access_log  off;
    return 200  '{"status":"ok"}';
    add_header  Content-Type application/json;
}

# To this (returns 500 error):
location /health {
    access_log  off;
    return 500  '{"status":"error"}';
    add_header  Content-Type application/json;
}
```

#### Step 2: Commit and Push

```bash
git add nginx.conf
git commit -m "test: break health endpoint for rollback testing"
git push origin main  # Triggers full pipeline with prod deployment
```

#### Step 3: Monitor Pipeline

Watch GitHub Actions:
1. ✅ Lint passes
2. ✅ Test passes
3. ✅ Build succeeds
4. ✅ Deploy to staging
5. ❌ **Health check staging FAILS** (targets unhealthy)
6. ⏸️ Pipeline stops (no prod deployment)

#### Step 4: Check Staging

```bash
# Check deployment status
aws ecs describe-services \
  --cluster food-app-staging-cluster \
  --services food-app-staging-service \
  --region ap-south-1 \
  --query 'services[0].deployments[*].{Status:status,TaskDef:taskDefinition,Desired:desiredCount,Running:runningCount}'

# Check target health (should be unhealthy)
TG_ARN=$(aws elbv2 describe-target-groups \
  --region ap-south-1 \
  --query 'TargetGroups[?contains(TargetGroupName, `food-app-staging`)].TargetGroupArn' \
  --output text)

aws elbv2 describe-target-health \
  --target-group-arn $TG_ARN \
  --region ap-south-1
```

Expected: Targets show `unhealthy` with reason `Target.FailedHealthChecks`

#### Step 5: ECS Circuit Breaker (Automatic)

ECS deployment circuit breaker will detect failures and automatically rollback to revision 18.

Watch in console:
- ECS → Services → Deployments tab
- You'll see rollback happen automatically

#### Step 6: Fix and Redeploy

```bash
# Revert the change
git revert HEAD
git push origin main
```

---

### Scenario 2: Production Rollback Test

Test production-specific rollback with manual approval.

#### Step 1: Make a Breaking Change

Same as Scenario 1, but this time we'll push to staging first to verify it's broken:

```bash
git add nginx.conf
git commit -m "test: prod rollback test"
git push origin staging  # Only staging
```

#### Step 2: Verify Staging Fails

Wait for staging health check to fail. This confirms the break works.

#### Step 3: Manually Approve for Production

If you still want to test prod rollback:
1. Push to main branch
2. Pipeline will fail at staging
3. Fix won't reach production (protection working!)

**OR** bypass staging (not recommended in real scenarios):

Skip health check temporarily by commenting out in pipeline.yml:

```yaml
# - name: Health check staging
#   run: bash scripts/health-check.sh staging ${{ env.AWS_REGION }} ${{ env.PROJECT }}
```

Push to main, approve production deployment, then watch it fail and rollback.

#### Step 4: Monitor Production Rollback

```bash
# Watch in real-time
watch -n 5 'aws ecs describe-services \
  --cluster food-app-prod-cluster \
  --services food-app-prod-service \
  --region ap-south-1 \
  --query "services[0].deployments[*].{Status:status,TaskDef:taskDefinition,Running:runningCount}"'
```

Expected flow:
1. New deployment starts (revision 10)
2. Health checks fail after 5 minutes
3. Pipeline detects failure
4. Executes rollback script
5. Returns to revision 9

---

### Scenario 3: Manual Rollback Test

Test manual rollback without pipeline.

#### Step 1: Note Current Versions

```bash
# Production current version
aws ecs describe-services \
  --cluster food-app-prod-cluster \
  --services food-app-prod-service \
  --region ap-south-1 \
  --query 'services[0].taskDefinition' \
  --output text

# Output: arn:aws:ecs:ap-south-1:ACCOUNT:task-definition/food-app-prod:9
```

#### Step 2: List All Revisions

```bash
aws ecs list-task-definitions \
  --family-prefix food-app-prod \
  --region ap-south-1 \
  --sort DESC
```

Output shows revisions: 9, 8, 7, 6...

#### Step 3: Manually Rollback to Previous Version

```bash
# Rollback to revision 8
bash scripts/rollback.sh \
  food-app-prod-cluster \
  food-app-prod-service \
  arn:aws:ecs:ap-south-1:<ACCOUNT_ID>:task-definition/food-app-prod:8 \
  ap-south-1
```

#### Step 4: Verify Rollback

```bash
# Check current version (should be 8 now)
aws ecs describe-services \
  --cluster food-app-prod-cluster \
  --services food-app-prod-service \
  --region ap-south-1 \
  --query 'services[0].taskDefinition'

# Check deployment status
aws ecs describe-services \
  --cluster food-app-prod-cluster \
  --services food-app-prod-service \
  --region ap-south-1 \
  --query 'services[0].deployments[*].{Status:status,TaskDef:taskDefinition,Desired:desiredCount,Running:runningCount}' \
  --output table
```

#### Step 5: Roll Forward Again

```bash
# Go back to revision 9
bash scripts/rollback.sh \
  food-app-prod-cluster \
  food-app-prod-service \
  arn:aws:ecs:ap-south-1:<ACCOUNT_ID>:task-definition/food-app-prod:9 \
  ap-south-1
```

---

### Scenario 4: Application Crash Test

Make the container crash on startup.

#### Step 1: Break Container Entrypoint

Edit `Dockerfile`:

```dockerfile
# Add before CMD
RUN echo "exit 1" > /docker-entrypoint.sh && chmod +x /docker-entrypoint.sh

CMD ["/docker-entrypoint.sh"]
```

This causes immediate container crash.

#### Step 2: Deploy

```bash
git add Dockerfile
git commit -m "test: container crash for rollback"
git push origin main
```

#### Step 3: Watch ECS

Container will crash immediately:
- Task starts
- Container exits with code 1
- ECS tries to restart
- Circuit breaker detects failure
- Automatic rollback

---

## Monitoring During Tests

### GitHub Actions
- Navigate to Actions tab
- Watch each step execute
- Check logs for "Health check FAILED"
- Verify "Rollback on failure" step executes

### AWS Console
**ECS:**
1. Go to ECS → Clusters → food-app-prod-cluster
2. Click service → Deployments and events tab
3. Watch deployment status change
4. See rollback deployment appear

**Target Groups:**
1. Go to EC2 → Target Groups
2. Select food-app-prod-tg
3. Click Targets tab
4. Watch health status (healthy → unhealthy → healthy after rollback)

**CloudWatch Logs:**
1. Go to CloudWatch → Log Groups
2. Select /ecs/food-app-prod
3. Watch real-time logs

### CLI Monitoring

```bash
# Real-time service status
watch -n 3 'aws ecs describe-services \
  --cluster food-app-prod-cluster \
  --services food-app-prod-service \
  --region ap-south-1 \
  --query "services[0].{Running:runningCount,Desired:desiredCount,Status:status,TaskDef:taskDefinition}"'

# Real-time target health
watch -n 3 'aws elbv2 describe-target-health \
  --target-group-arn <TG_ARN> \
  --region ap-south-1 \
  --query "TargetHealthDescriptions[0].TargetHealth.{State:State,Reason:Reason}"'
```

---

## Expected Timeline

### Automatic Rollback (via Pipeline)
- **0:00** - Deployment starts
- **0:30** - New tasks starting
- **1:00** - Tasks running, registering with ALB
- **1:30** - ALB performing health checks
- **2:00** - Health checks failing (unhealthy)
- **5:00** - Pipeline health check script fails
- **5:05** - Rollback script executes
- **6:00** - Old tasks redeployed
- **7:00** - Back to healthy state

### ECS Circuit Breaker Rollback
- **0:00** - Deployment starts
- **0:30** - New tasks fail to start or crash
- **1:00** - ECS detects failures
- **1:30** - Circuit breaker triggers
- **2:00** - Automatic rollback begins
- **3:00** - Previous version restored

---

## Verification Checklist

After each rollback test:

- [ ] Service is running and stable
- [ ] Task definition reverted to previous version
- [ ] All targets are healthy in ALB
- [ ] Application accessible via ALB URL
- [ ] CloudWatch logs show successful startup
- [ ] No failed tasks in ECS
- [ ] Deployment marked as successful in GitHub Actions (after fix)

---

## Recommended Test Order

1. **Start with Scenario 3** (Manual Rollback) - Low risk, manual control
2. **Then Scenario 1** (Health Check Failure) - Tests staging protection
3. **Then Scenario 2** (Production Rollback) - Full pipeline test
4. **Optional: Scenario 4** (Container Crash) - Most realistic failure

---

## Rollback Script Verification

Before testing, verify your rollback script works:

```bash
# Test rollback script syntax
bash -n scripts/rollback.sh

# View script contents
cat scripts/rollback.sh
```

Expected script should:
1. Accept cluster, service, task definition ARN, region
2. Update service with previous task definition
3. Wait for deployment to stabilize
4. Verify rollback success

---

## Cleanup After Testing

```bash
# Revert all test changes
git log --oneline -5  # Find test commits
git revert <commit-sha>
git push origin main

# Or reset to clean state
git reset --hard origin/main
git push origin main --force
```

---

## Common Issues

### Issue: Rollback doesn't trigger
**Cause:** Health check timeout too short
**Fix:** Pipeline health check waits 5 minutes - ensure this is enough

### Issue: Circuit breaker doesn't work
**Cause:** Not enabled or misconfigured
**Fix:** Check `deployment_circuit_breaker` in Terraform

### Issue: Manual rollback fails
**Cause:** Wrong task definition ARN format
**Fix:** Use full ARN with revision number

---

## Success Criteria

Your rollback mechanism is working if:
✅ Failed deployments don't reach production
✅ Staging failures block production deployment
✅ Unhealthy targets trigger automatic rollback
✅ Manual rollback completes within 3-5 minutes
✅ Application returns to working state after rollback
✅ No manual intervention required for automatic rollback
