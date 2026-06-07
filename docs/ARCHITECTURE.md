# Project Architecture Documentation

## Complete AWS ECS Deployment Pipeline for Food-App

---

## 1. High-Level Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                          GitHub Repository                           │
│                     (Source Code + IaC + CI/CD)                     │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                               │ Push/PR Triggers
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        GitHub Actions Pipeline                       │
│  ┌─────────┐   ┌──────┐   ┌───────┐   ┌─────────┐   ┌──────────┐ │
│  │  Lint   │ → │ Test │ → │ Build │ → │ Deploy  │ → │  Health  │ │
│  │ (TF+Docker)│ │(Docker)│ │ (ECR) │ → │ Staging │ → │  Check   │ │
│  └─────────┘   └──────┘   └───────┘   └─────────┘   └──────────┘ │
│                                             │                        │
│                                             ▼                        │
│                                    ┌─────────────────┐              │
│                                    │ Manual Approval │              │
│                                    └────────┬────────┘              │
│                                             │                        │
│                                             ▼                        │
│                                    ┌─────────────────┐              │
│                                    │  Deploy Prod    │              │
│                                    └─────────────────┘              │
└─────────────────────────────────────────────────────────────────────┘
                               │
                               │ Provisions & Deploys
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                           AWS Cloud                                  │
│                                                                       │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                     VPC (per environment)                     │  │
│  │                                                                │  │
│  │  ┌──────────────────────────────────────────────────────┐   │  │
│  │  │              Public Subnets (2 AZs)                   │   │  │
│  │  │                                                         │   │  │
│  │  │  ┌──────────────┐         ┌──────────────┐           │   │  │
│  │  │  │     ALB      │ ←──────→│ ECS Fargate  │           │   │  │
│  │  │  │ (Port 80/443)│         │    Tasks     │           │   │  │
│  │  │  └──────┬───────┘         │  (with IPs)  │           │   │  │
│  │  │         │                  └──────┬───────┘           │   │  │
│  │  │         │                         │                    │   │  │
│  │  │         │                         └─► CloudWatch      │   │  │
│  │  │         │                                 Logs         │   │  │
│  │  └─────────┼─────────────────────────────────────────────┘   │  │
│  │            │                                                   │  │
│  │            └─► Internet Gateway                               │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                       │
│  ┌────────────────┐  ┌──────────────┐  ┌──────────────────────┐   │
│  │ ECR Repository │  │  S3 Bucket   │  │  DynamoDB Table      │   │
│  │ (Docker Images)│  │ (TF State)   │  │  (State Locking)     │   │
│  └────────────────┘  └──────────────┘  └──────────────────────┘   │
│                                                                       │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 2. Detailed Network Architecture

### **Current Optimized Architecture (No NAT Gateway)**

```
                                Internet
                                   │
                                   │
                    ┌──────────────┴──────────────┐
                    │     Internet Gateway        │
                    └──────────────┬──────────────┘
                                   │
            ┌──────────────────────┴─────────────────────┐
            │                                             │
            │              Public Subnets                 │
            │         (ap-south-1a, ap-south-1b)         │
            │                                             │
            │  ┌──────────────────────────────────────┐  │
            │  │  Application Load Balancer (ALB)     │  │
            │  │  - Port 80/443                       │  │
            │  │  - Health Check: /health             │  │
            │  │  - Security Group: Allow 0.0.0.0/0   │  │
            │  └────────────────┬─────────────────────┘  │
            │                   │                         │
            │                   │ Forward Traffic         │
            │                   │                         │
            │  ┌────────────────▼─────────────────────┐  │
            │  │   ECS Fargate Tasks (Target Group)   │  │
            │  │   - Port 80                          │  │
            │  │   - Public IPs assigned              │  │
            │  │   - Security Group: Allow from ALB   │  │
            │  │   - Health Check: /health            │  │
            │  └────────────────┬─────────────────────┘  │
            │                   │                         │
            │                   │ Egress to:              │
            │                   ├─► ECR (pull images)     │
            │                   ├─► CloudWatch (logs)     │
            │                   └─► AWS APIs              │
            │                                             │
            └─────────────────────────────────────────────┘
                                   │
                                   │ Direct Internet Access
                                   ▼
                        ECR / CloudWatch / AWS Services
```

**Key Points:**
- ✅ No NAT Gateway (saves $64/month)
- ✅ ECS tasks in public subnets with public IPs
- ✅ Security groups control all access
- ✅ Only ALB can reach ECS tasks
- ✅ ECS tasks can reach internet directly

---

## 3. Infrastructure Components

### **3.1 Networking Layer**

```
VPC
├── CIDR: 10.1.0.0/16 (staging) / 10.2.0.0/16 (prod)
├── Internet Gateway (IGW)
├── Public Subnets
│   ├── Subnet 1: 10.X.1.0/24 (AZ-a)
│   └── Subnet 2: 10.X.2.0/24 (AZ-b)
├── Private Subnets (exist but unused)
│   ├── Subnet 1: 10.X.10.0/24 (AZ-a)
│   └── Subnet 2: 10.X.11.0/24 (AZ-b)
└── Route Tables
    └── Public RT: 0.0.0.0/0 → IGW
```

### **3.2 Compute Layer**

```
ECS Cluster
├── Capacity Providers: FARGATE + FARGATE_SPOT
├── Container Insights: Enabled
└── ECS Service
    ├── Launch Type: FARGATE (prod) / FARGATE_SPOT (staging)
    ├── Network Mode: awsvpc
    ├── Task Definition
    │   ├── CPU: 256 (staging) / 512 (prod)
    │   ├── Memory: 512 MB (staging) / 1024 MB (prod)
    │   └── Container: nginx + static app
    ├── Desired Count: 1
    ├── Min Tasks: 1
    ├── Max Tasks: 2 (staging) / 3 (prod)
    ├── Auto-scaling
    │   ├── CPU Target: 70%
    │   └── Memory Target: 70%
    └── Load Balancer Integration
        └── Target Group: food-app-{env}-tg
```

### **3.3 Load Balancing**

```
Application Load Balancer (ALB)
├── Scheme: internet-facing
├── Subnets: Public (both AZs)
├── Security Group
│   ├── Ingress: 80/443 from 0.0.0.0/0
│   └── Egress: All
├── Listener (Port 80)
│   └── Forward to Target Group
└── Target Group
    ├── Type: IP
    ├── Port: 80
    ├── Protocol: HTTP
    ├── Health Check
    │   ├── Path: /health
    │   ├── Interval: 30s
    │   ├── Timeout: 5s
    │   ├── Healthy Threshold: 2
    │   └── Unhealthy Threshold: 3
    └── Targets: ECS Task IPs (dynamic)
```

### **3.4 Container Registry**

```
ECR Repository
├── Name: food-app-{env}
├── Image Scanning: On Push
├── Tag Mutability: MUTABLE
├── Lifecycle Policy: Keep last 10 images
└── Images
    ├── latest
    └── {git-sha}
```

### **3.5 Security Layer**

```
Security Groups
├── ALB Security Group
│   ├── Inbound: 0.0.0.0/0:80, 0.0.0.0/0:443
│   └── Outbound: 0.0.0.0/0:all
└── ECS Security Group
    ├── Inbound: ALB-SG:80
    └── Outbound: 0.0.0.0/0:all (for ECR, CloudWatch)

IAM Roles
├── ECS Execution Role
│   ├── Policy: AmazonECSTaskExecutionRolePolicy
│   ├── ECR Pull Permission
│   └── SSM Parameter Read: /{project}/{env}/*
└── ECS Task Role
    └── Application-specific permissions
```

### **3.6 Monitoring Layer**

```
CloudWatch
├── Log Groups
│   ├── /ecs/food-app/staging (retention: 7 days)
│   └── /ecs/food-app/prod (retention: 30 days)
├── Alarms
│   ├── CPU High (>80%)
│   ├── Memory High (>80%)
│   └── ALB 5xx Errors (>10)
└── Container Insights
    └── ECS cluster metrics
```

### **3.7 State Management**

```
Terraform Remote State
├── S3 Bucket
│   ├── Name: food-app-terraform-state-{account-id}
│   ├── Versioning: Enabled
│   ├── Encryption: AES256
│   └── Public Access: Blocked
└── DynamoDB Table
    ├── Name: food-app-terraform-locks
    ├── Key: LockID (String)
    └── Billing: Pay-per-request
```

---

## 4. CI/CD Pipeline Architecture

### **Pipeline Stages**

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. LINT STAGE (Runs on PR + Push)                              │
├─────────────────────────────────────────────────────────────────┤
│  ├─► Terraform fmt -check                                       │
│  ├─► Terraform validate                                         │
│  ├─► TFLint (Terraform best practices)                          │
│  └─► Hadolint (Dockerfile linting)                              │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ 2. TEST STAGE                                                   │
├─────────────────────────────────────────────────────────────────┤
│  └─► Docker build --target test                                 │
│      └─► Validates all app files exist                          │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ 3. INFRA-STAGING (Provision Infrastructure)                     │
├─────────────────────────────────────────────────────────────────┤
│  ├─► AWS OIDC Authentication                                    │
│  ├─► Terraform init -backend-config=backend.hcl                 │
│  └─► Terraform apply (desired_count=0 initially)                │
│      └─► Creates: VPC, Subnets, ALB, ECS, ECR, etc.            │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ 4. BUILD & PUSH                                                 │
├─────────────────────────────────────────────────────────────────┤
│  ├─► Docker build -t food-app                                   │
│  ├─► Tag: {git-sha} + latest                                    │
│  ├─► ECR Login                                                  │
│  └─► Docker push to ECR                                         │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ 5. DEPLOY-STAGING                                               │
├─────────────────────────────────────────────────────────────────┤
│  ├─► Terraform apply (image_tag={git-sha})                      │
│  ├─► ECS update-service --force-new-deployment                  │
│  └─► Health check (5 min timeout)                               │
│      └─► Poll every 15s: runningCount == desiredCount           │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ 6. APPROVE-PROD (Manual Gate - Only on main branch)            │
├─────────────────────────────────────────────────────────────────┤
│  └─► GitHub Environment Protection Rule                         │
│      └─► Requires 1 reviewer approval                           │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ 7. INFRA-PROD (Provision Production)                            │
├─────────────────────────────────────────────────────────────────┤
│  └─► Same as infra-staging but for prod environment             │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ 8. DEPLOY-PROD                                                  │
├─────────────────────────────────────────────────────────────────┤
│  ├─► Capture previous task definition (for rollback)            │
│  ├─► Retag staging image → prod ECR                             │
│  ├─► Terraform apply (prod)                                     │
│  ├─► Health check (5 min timeout)                               │
│  └─► If FAIL → Automatic rollback to previous task def          │
└─────────────────────────────────────────────────────────────────┘
```

### **Authentication Flow**

```
GitHub Actions
      │
      │ 1. Request JWT token
      ▼
GitHub OIDC Provider
      │
      │ 2. Issue JWT with repo info
      ▼
AWS STS (AssumeRoleWithWebIdentity)
      │
      │ 3. Validate JWT & assume IAM role
      ▼
IAM Role (AWS_ROLE_ARN)
      │
      │ 4. Temporary credentials issued
      ▼
Terraform/AWS CLI
      │
      └─► Deploy to AWS
```

---

## 5. Application Architecture

### **Docker Multi-Stage Build**

```
┌─────────────────────────────────────────────────────────────────┐
│ Stage 1: TEST (node:20-alpine)                                  │
├─────────────────────────────────────────────────────────────────┤
│  WORKDIR /app                                                   │
│  COPY app/ .                                                    │
│  RUN test -f index.html && test -f css/style.css && ...        │
│  └─► Validates all required files exist                         │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ Stage 2: PRODUCTION (nginx:1.27-alpine)                         │
├─────────────────────────────────────────────────────────────────┤
│  COPY nginx.conf → /etc/nginx/conf.d/app.conf                  │
│  COPY app/ → /usr/share/nginx/html/                            │
│  EXPOSE 80                                                      │
│  HEALTHCHECK --interval=30s CMD wget -qO- /health               │
│  CMD ["nginx", "-g", "daemon off;"]                             │
└─────────────────────────────────────────────────────────────────┘
```

### **Application Stack**

```
Nginx Container
├── Port: 80
├── Static Files: /usr/share/nginx/html/
│   ├── index.html (Main app)
│   ├── css/style.css
│   └── js/app.js
├── Configuration: nginx.conf
│   ├── Gzip compression
│   ├── Security headers
│   ├── Static asset caching (1 year)
│   └── Health check endpoint
└── Health Check: /health → {"status":"ok"}
```

---

## 6. Terraform Module Structure

```
terraform/
├── backend/
│   ├── bootstrap.sh         # Creates S3 + DynamoDB
│   └── bootstrap.ps1        # Windows version
├── modules/
│   ├── networking/
│   │   ├── main.tf          # VPC, Subnets, IGW, (NAT disabled)
│   │   ├── variables.tf
│   │   └── outputs.tf       # VPC ID, Subnet IDs
│   ├── security/
│   │   ├── main.tf          # Security Groups, IAM Roles
│   │   ├── variables.tf
│   │   └── outputs.tf       # SG IDs, Role ARNs
│   ├── compute/
│   │   ├── main.tf          # ECR, ECS, ALB, Auto-scaling
│   │   ├── variables.tf
│   │   └── outputs.tf       # ECR URL, ECS Cluster, ALB DNS
│   └── monitoring/
│       ├── main.tf          # CloudWatch Logs, Alarms
│       ├── variables.tf
│       └── outputs.tf       # Log Group Name
└── envs/
    ├── dev/
    │   ├── main.tf          # Orchestrates all modules
    │   ├── variables.tf
    │   ├── outputs.tf
    │   ├── terraform.tfvars # Environment-specific values
    │   └── backend.hcl      # S3 backend config
    ├── staging/
    │   └── ... (same structure)
    └── prod/
        └── ... (same structure)
```

---

## 7. Data Flow

### **Deployment Flow**

```
Developer
   │
   │ git push origin main
   ▼
GitHub Repository
   │
   │ Webhook trigger
   ▼
GitHub Actions Runner
   │
   ├─► Build Docker Image
   │   └─► Push to ECR
   │
   └─► Terraform Apply
       │
       ├─► Update ECS Task Definition
       │   └─► References new ECR image:{sha}
       │
       └─► ECS Service Update
           │
           ├─► Pull new task definition
           │
           ├─► Start new task(s)
           │   │
           │   ├─► Pull image from ECR
           │   ├─► Start container
           │   └─► Register with Target Group
           │
           ├─► Health checks pass
           │   └─► ALB marks target healthy
           │
           └─► Drain & stop old tasks
```

### **Request Flow**

```
User Browser
   │
   │ HTTP Request
   ▼
Internet
   │
   ▼
Application Load Balancer (ALB)
   │
   │ Route based on Target Group
   ▼
Target Group
   │
   │ Select healthy target (round-robin)
   ▼
ECS Task (Nginx Container)
   │
   │ Process request
   │ └─► Serve static files
   │ └─► Return response
   ▼
User Browser
   │
   └─► Page rendered
```

### **Logging Flow**

```
ECS Task Container
   │
   │ stdout/stderr
   ▼
awslogs Driver
   │
   │ Stream logs
   ▼
CloudWatch Logs
   │
   ├─► Log Group: /ecs/food-app/{env}
   │   └─► Log Stream: ecs/{container}/{task-id}
   │
   └─► Retention: 7-30 days
```

---

## 8. Security Architecture

### **Network Security**

```
Internet
   │
   │ ✓ Only ports 80/443 allowed
   ▼
ALB Security Group
   │ Ingress: 0.0.0.0/0:80, 0.0.0.0/0:443
   │ Egress: All
   │
   │ ✓ Only ALB can reach ECS tasks
   ▼
ECS Security Group
   │ Ingress: ALB-SG:80 ONLY
   │ Egress: All (for ECR, CloudWatch, AWS APIs)
   ▼
ECS Tasks (Public IPs but secured by SG)
   │
   └─► Can only receive traffic from ALB
```

### **IAM Security**

```
ECS Task
   │
   ├─► Execution Role (for ECS infrastructure)
   │   ├─► Pull from ECR
   │   ├─► Write to CloudWatch Logs
   │   └─► Read SSM Parameters (/{project}/{env}/*)
   │
   └─► Task Role (for application)
       └─► Application-specific permissions
```

### **Secrets Management**

```
Sensitive Data
   │
   ├─► AWS Credentials
   │   └─► GitHub Secrets (OIDC, no long-term keys)
   │
   └─► Application Secrets
       └─► AWS Systems Manager Parameter Store
           └─► Path: /{project}/{env}/{secret-name}
```

---

## 9. Cost Architecture

### **Per Environment Breakdown**

```
Staging Environment (~$20/month)
├── ECS Fargate Spot (256 vCPU, 512 MB, 1 task)    $2
├── Application Load Balancer                       $16
├── ECR Storage (~5 images)                         $1
└── CloudWatch Logs (7 days retention)              $1

Production Environment (~$39/month)
├── ECS Fargate (512 vCPU, 1024 MB, 1 task)        $20
├── Application Load Balancer                       $16
├── ECR Storage (~5 images)                         $1
└── CloudWatch Logs (30 days retention)             $2

Shared Resources (~$1/month)
├── S3 Remote State                                 $0.50
└── DynamoDB Locks                                  $0.50

Total: ~$60/month
```

---

## 10. Deployment Environments

| Aspect | Staging | Production |
|--------|---------|------------|
| **VPC CIDR** | 10.1.0.0/16 | 10.2.0.0/16 |
| **Fargate Type** | SPOT (70% cheaper) | On-Demand |
| **Task CPU** | 256 | 512 |
| **Task Memory** | 512 MB | 1024 MB |
| **Min/Max Tasks** | 1-2 | 1-3 |
| **Log Retention** | 7 days | 30 days |
| **Manual Approval** | No | Yes |
| **Rollback** | No | Automatic on health check fail |

---

## 11. Key Design Decisions

### **Why No NAT Gateway?**
- ✅ Saves $64/month ($32 per environment)
- ✅ ECS tasks can reach internet directly with public IPs
- ✅ Security maintained via Security Groups
- ⚠️ Tasks have public IPs (still protected, only ALB can reach them)

### **Why Fargate Spot for Staging?**
- ✅ 70% cheaper than on-demand
- ⚠️ Can be interrupted (rare, acceptable for staging)

### **Why Public Subnets?**
- ✅ Eliminates NAT Gateway cost
- ✅ Simpler architecture
- ✅ Still secure with security groups

### **Why Single Task Minimum?**
- ✅ Reduces cost by 50%
- ⚠️ Brief downtime during deployments
- ✅ Auto-scaling handles traffic spikes

---

This is the complete architecture of your AWS ECS deployment pipeline! 🎉
