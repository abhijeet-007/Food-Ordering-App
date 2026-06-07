# infra-as-code-pipeline

Zero-touch AWS deployment pipeline with automated rollback for containerized applications.

---

## Project Summary

This project implements a fully automated CI/CD pipeline for deploying containerized applications to AWS ECS. It eliminates manual deployments by automatically testing, building, and deploying code changes through staging to production environments with built-in health monitoring and automatic rollback capabilities.

**What makes it special:**
- Push code once, deployment happens automatically across environments
- Failed deployments roll back automatically within 5 minutes
- Cost-optimized architecture saves 84% compared to typical AWS setups
- Production-grade security with no hardcoded credentials
- Complete infrastructure as code for reproducibility

---

## Tools & Technologies

### Infrastructure & Deployment
- **Terraform** - Infrastructure as Code for provisioning all AWS resources with modular, reusable components
- **AWS ECS Fargate** - Serverless container orchestration without managing EC2 instances
- **Application Load Balancer (ALB)** - Distributes traffic across containers in multiple availability zones
- **Amazon ECR** - Private Docker container registry for storing application images

### CI/CD Pipeline
- **GitHub Actions** - Automated workflow execution for build, test, and deployment
- **Docker** - Containerization platform for packaging applications with dependencies
- **GitHub OIDC** - Secure authentication to AWS without long-lived access keys

### Monitoring & Operations
- **CloudWatch Logs** - Centralized logging for container output and debugging
- **CloudWatch Alarms** - Automated alerts for service health issues
- **Health Check Scripts** - Custom validation scripts to verify deployment success

### State Management
- **Amazon S3** - Remote storage for Terraform state files
- **DynamoDB** - State locking to prevent concurrent Terraform operations

### Networking & Security
- **VPC (Virtual Private Cloud)** - Isolated network for resources
- **Security Groups** - Firewall rules controlling traffic between components
- **IAM Roles** - Least-privilege permissions for services and pipelines

---

## What This Does

🚀 **Automatic deployment** - Push code to GitHub, everything else is automated  
✅ **Health monitoring** - Validates deployments within 5 minutes  
🔄 **Auto rollback** - Failed deployments automatically revert to previous version  
💰 **Cost optimized** - $60/month for staging + production environments  
🔒 **Secure** - No hardcoded secrets, OIDC authentication, least privilege IAM  

---

## Architecture

```
Internet
   ↓
Application Load Balancer (ALB)
   ↓
ECS Fargate Tasks (2 availability zones)
   ↓
CloudWatch Logs
```

**Tech Stack:**
- **Infrastructure:** Terraform (modular design)
- **Containers:** Docker + AWS ECS Fargate
- **CI/CD:** GitHub Actions with OIDC
- **Networking:** VPC, Public Subnets, Security Groups
- **Storage:** Amazon ECR for images, S3 for state
- **Monitoring:** CloudWatch Logs + Alarms

**Cost Optimizations:**
- ❌ No NAT Gateway (saves $64/month)
- ✅ ECS in public subnets with security groups
- ✅ Fargate Spot for staging (70% cheaper)
- ✅ Right-sized tasks and minimal log retention

---

## How It Works

```
You: git push origin main
  ↓
GitHub Actions Pipeline:
  1. Lint & Test code
  2. Build Docker image
  3. Push to AWS ECR
  4. Deploy to Staging → Health Check (5 min)
  5. Wait for Manual Approval ✋
  6. Deploy to Production → Health Check (5 min)
     • Success? ✅ Done!
     • Failed? 🔄 Auto rollback to previous version
```

**Key Features:**
- ✅ Zero manual deployments
- ✅ Two-layer protection: Staging validates before production
- ✅ ECS circuit breaker + pipeline health checks
- ✅ Manual approval gate for production
- ✅ Automatic rollback on failures

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

### 1️⃣ Setup AWS Backend (one-time)

```bash
cd terraform/backend
./bootstrap.sh ap-south-1 food-app
```

This creates S3 bucket and DynamoDB table for Terraform state.

### 2️⃣ Configure GitHub

**Add Secrets:** (Settings → Secrets and variables → Actions)
- `AWS_ROLE_ARN` - IAM role for staging
- `AWS_ROLE_ARN_PROD` - IAM role for production

**Add Environments:** (Settings → Environments)
- `staging` - No approval needed
- `production-approval` - Require 1 reviewer
- `production` - No additional gates

### 3️⃣ Deploy Infrastructure

```bash
cd terraform/envs/staging
terraform init -backend-config=backend.hcl
terraform apply

# Repeat for production
cd ../prod
terraform init -backend-config=backend.hcl
terraform apply
```

### 4️⃣ Push Code & Watch It Deploy!

```bash
git add .
git commit -m "Initial deployment"
git push origin main
```

GitHub Actions automatically deploys to staging, waits for approval, then deploys to production.

**Access your app:**
- Staging: `http://food-app-staging-alb-*.ap-south-1.elb.amazonaws.com`
- Production: `http://food-app-prod-alb-*.ap-south-1.elb.amazonaws.com`

---

## Rollback

**Automatic:** Happens automatically if health checks fail within 5 minutes.

**Manual:**
```bash
# List previous versions
aws ecs list-task-definitions --family-prefix food-app-prod --region ap-south-1

# Rollback to specific version
bash scripts/rollback.sh \
  food-app-prod-cluster \
  food-app-prod-service \
  arn:aws:ecs:ap-south-1:ACCOUNT:task-definition/food-app-prod:8 \
  ap-south-1
```

---

## Monthly Costs

| Environment | Cost/Month |
|-------------|------------|
| Staging     | ~$20       |
| Production  | ~$39       |
| **Total**   | **~$60**   |

**5-Month Project Total: ~$300**

**What you're paying for:**
- ECS Fargate containers (Spot for staging, On-Demand for prod)
- Application Load Balancers (2)
- ECR image storage (~10 images)
- CloudWatch logs
- Data transfer (minimal)

**What you're NOT paying for:**
- ❌ NAT Gateway ($64/month saved)
- ❌ Over-provisioned resources
- ❌ Unused dev environment

> 💡 See [docs/cost-optimization.md](docs/cost-optimization.md) for breakdown  
> 📊 Use [AWS Pricing Calculator](https://calculator.aws) for estimates

---

## Project Structure

```
infra-as-code-pipeline/
├── .github/workflows/
│   └── pipeline.yml          # CI/CD automation
├── terraform/
│   ├── modules/              # Reusable infrastructure modules
│   │   ├── networking/       # VPC, subnets, routing
│   │   ├── security/         # IAM, security groups
│   │   ├── compute/          # ECS, ECR, ALB
│   │   └── monitoring/       # CloudWatch
│   └── envs/                 # Environment configs
│       ├── staging/
│       └── prod/
├── scripts/
│   ├── health-check.sh       # Deployment validation
│   └── rollback.sh           # Emergency rollback
├── docs/                     # Troubleshooting guides
├── Dockerfile                # Container definition
└── nginx.conf                # Web server config
```

---

## Documentation

📘 **Troubleshooting:**
- [Common Issues Quick Reference](docs/issues-quick-reference.md)
- [ECR Login Timeout](docs/ecr-login-timeout.md)
- [State Checksum Mismatch](docs/state-checksum-mismatch.md)
- [503 Service Unavailable](docs/troubleshooting-503.md)

📗 **Guides:**
- [Rollback Testing](docs/rollback-testing.md)
- [Cost Optimization](docs/cost-optimization.md)
- [Remove Staging Environment](docs/remove-staging.md)

📙 **Reference:**
- [Architecture Details](docs/ARCHITECTURE.md)
- [Runbook](docs/runbook.md)

---

## Features

✅ **Zero-Touch Deployment** - Push code, pipeline handles everything  
✅ **Automated Testing** - Lint, validate, and test before deploy  
✅ **Health Monitoring** - 5-minute validation window with ALB target checks  
✅ **Automatic Rollback** - ECS circuit breaker + pipeline health checks  
✅ **Manual Approval** - Production requires explicit approval  
✅ **Cost Optimized** - 84% cheaper than typical setups  
✅ **Infrastructure as Code** - Terraform modules for everything  
✅ **Secure by Default** - OIDC auth, no hardcoded secrets, least privilege IAM  
✅ **Multi-Environment** - Separate staging and production  
✅ **Auto-Scaling** - CPU/Memory-based scaling with ECS  

---

## Tech Stack Summary

| Layer | Technology |
|-------|------------|
| **Infrastructure** | Terraform |
| **Containers** | Docker, ECS Fargate |
| **CI/CD** | GitHub Actions |
| **Cloud** | AWS (VPC, ALB, ECR, ECS, CloudWatch, S3, DynamoDB) |
| **Monitoring** | CloudWatch Logs + Alarms |
| **State Management** | S3 + DynamoDB Locking |
| **Authentication** | GitHub OIDC (no long-lived credentials) |
