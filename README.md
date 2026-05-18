# infra-as-code-pipeline

Fully functional AWS ECS deployment pipeline for `food-app`.

---

## Architecture Overview

```
Internet
   │
   ▼
[ALB] ── public subnets (2 AZs)
   │
   ▼
[ECS Fargate Service] ── private subnets (2 AZs)
   │                         │
   │                    [CloudWatch Logs]
   │
[ECR Repository]
   │
[S3 Remote State + DynamoDB Lock]
```

### AWS Resources per Environment

| Resource            | Dev        | Staging    | Prod       |
|---------------------|------------|------------|------------|
| VPC CIDR            | 10.0.0.0/16| 10.1.0.0/16| 10.2.0.0/16|
| ECS Task CPU        | 256        | 512        | 1024       |
| ECS Task Memory     | 512 MB     | 1024 MB    | 2048 MB    |
| Min Tasks           | 1          | 2          | 2          |
| Max Tasks           | 2          | 4          | 6          |
| Log Retention       | 7 days     | 14 days    | 90 days    |

---

## Pipeline Flow

```
PR opened
   │
   ├─► lint (terraform fmt + validate + tflint + hadolint)
   │
   └─► test (docker build + run tests)

Push to main / staging
   │
   ├─► lint → test → build & push to ECR
   │
   ├─► deploy → staging
   │       └─► health check (5 min window)
   │               └─► FAIL → pipeline stops, no prod deploy
   │
   ├─► [MANUAL APPROVAL] ← required for prod
   │
   └─► deploy → production
           └─► health check (5 min window)
                   └─► FAIL → auto rollback to previous task definition
```

---

## Repository Structure

```
infra-as-code-pipeline/
├── .github/
│   └── workflows/
│       └── pipeline.yml          # Full CI/CD pipeline
├── terraform/
│   ├── backend/
│   │   └── bootstrap.sh          # One-time S3 + DynamoDB setup
│   ├── modules/
│   │   ├── networking/           # VPC, subnets, IGW, NAT, route tables
│   │   ├── security/             # Security groups, IAM roles
│   │   ├── compute/              # ECR, ECS, ALB, auto-scaling
│   │   └── monitoring/           # CloudWatch log groups + alarms
│   └── envs/
│       ├── dev/                  # Dev workspace
│       ├── staging/              # Staging workspace
│       └── prod/                 # Production workspace
├── scripts/
│   ├── health-check.sh           # 5-min health check poller
│   └── rollback.sh               # ECS rollback to previous task def
└── docs/
    └── runbook.md                # Failure runbook
```

---

## Quick Start

### 1. Bootstrap remote state (run once)

```bash
cd terraform/backend
chmod +x bootstrap.sh
./bootstrap.sh us-east-1 food-app
```

Update `backend.hcl` in each env with the bucket name printed.

### 2. Configure GitHub Secrets

| Secret               | Description                              |
|----------------------|------------------------------------------|
| `AWS_ROLE_ARN`       | IAM role ARN for staging deployments     |
| `AWS_ROLE_ARN_PROD`  | IAM role ARN for production deployments  |

### 3. Configure GitHub Environments

Create these environments in GitHub → Settings → Environments:
- `staging` — no approval required
- `production-approval` — require 1 reviewer
- `production` — no additional gates

### 4. Deploy manually (first time)

```bash
cd terraform/envs/staging
terraform init -backend-config=backend.hcl
terraform apply -var-file=terraform.tfvars
```

### 5. Push code to trigger pipeline

```bash
git push origin main   # triggers full pipeline with prod approval
git push origin staging # triggers staging deploy only
```

---

## Rollback

Rollback is automatic if the health check fails within 5 minutes of a production deploy.

Manual rollback:

```bash
# Find previous task definition
aws ecs describe-services \
  --cluster food-app-prod-cluster \
  --services food-app-prod-service \
  --query 'services[0].taskDefinition'

# Roll back
bash scripts/rollback.sh \
  food-app-prod-cluster \
  food-app-prod-service \
  arn:aws:ecs:us-east-1:<account>:task-definition/food-app-prod:<PREV_REVISION> \
  us-east-1
```

---

## Estimated Monthly AWS Costs

> Estimates based on us-east-1, on-demand pricing.

| Resource                    | Dev      | Staging  | Prod      |
|-----------------------------|----------|----------|-----------|
| ECS Fargate (tasks)         | ~$5      | ~$25     | ~$80      |
| ALB                         | ~$16     | ~$16     | ~$16      |
| NAT Gateway (2 AZs)         | ~$65     | ~$65     | ~$65      |
| ECR storage (10 images)     | ~$1      | ~$1      | ~$1       |
| CloudWatch Logs             | ~$1      | ~$2      | ~$5       |
| **Total (approx)**          | **~$88** | **~$109**| **~$167** |

> Use [AWS Pricing Calculator](https://calculator.aws) for precise estimates.

---

## Secrets Management

- All secrets stored in **GitHub Secrets** (AWS credentials) or **AWS Parameter Store**
- Parameter Store path: `/<project>/<env>/<secret-name>`
- ECS task execution role has SSM read access scoped to `/<project>/<env>/*`
- No secrets ever committed to code

---

## Auto-scaling

ECS services scale between `min_capacity` and `max_capacity` based on:
- CPU utilization target: **70%**
- Memory utilization target: **70%**
- Scale-out cooldown: 60s
- Scale-in cooldown: 300s
