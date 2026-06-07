# Terraform State Checksum Mismatch

## Problem

```
Error refreshing state: state data in S3 does not have the expected content.

The checksum calculated for the state stored in S3 does not match the checksum
stored in DynamoDB.

Bucket: food-app-terraform-state-294659523259
Key:    staging/terraform.tfstate
Calculated checksum: d91d28a71054d3cb7d3eb4ab1acdb476
Stored checksum:     f7a57a61abe8ca1ba831f1f6e86f0d31
```

## Root Cause

This happens when:
1. S3 state file was updated but DynamoDB lock table wasn't updated
2. Multiple terraform operations ran concurrently
3. Previous `terraform destroy` or operation was interrupted
4. S3 eventual consistency delays (rare)

## Solution

### Option 1: Wait and Retry (Try First)

Sometimes S3 replication takes time:

```bash
# Wait 1-2 minutes, then retry
sleep 120
terraform init -backend-config=backend.hcl
terraform plan
```

### Option 2: Update DynamoDB Checksum (Recommended)

Update the DynamoDB table with the correct checksum:

```bash
# Get the correct checksum from error message
CORRECT_CHECKSUM="f7a57a61abe8ca1ba831f1f6e86f0d31"

# Update DynamoDB
aws dynamodb put-item \
  --table-name food-app-terraform-locks \
  --item '{
    "LockID": {"S": "food-app-terraform-state-294659523259/staging/terraform.tfstate-md5"},
    "Digest": {"S": "'$CORRECT_CHECKSUM'"}
  }' \
  --region ap-south-1

# Retry terraform
terraform init -backend-config=backend.hcl
```

### Option 3: Force Unlock (If Locked)

If state is locked from previous operation:

```bash
# List locks
aws dynamodb scan \
  --table-name food-app-terraform-locks \
  --region ap-south-1

# Force unlock (use Lock ID from error)
terraform force-unlock <LOCK_ID>

# Or delete from DynamoDB directly
aws dynamodb delete-item \
  --table-name food-app-terraform-locks \
  --key '{"LockID": {"S": "food-app-terraform-state-294659523259/staging/terraform.tfstate"}}' \
  --region ap-south-1
```

### Option 4: Recalculate and Update Checksum

```bash
# Download state file
aws s3 cp s3://food-app-terraform-state-294659523259/staging/terraform.tfstate ./state.tfstate \
  --region ap-south-1

# Calculate MD5 checksum
md5sum state.tfstate  # Linux/Mac
# or
certutil -hashfile state.tfstate MD5  # Windows

# Update DynamoDB with calculated checksum
aws dynamodb put-item \
  --table-name food-app-terraform-locks \
  --item '{
    "LockID": {"S": "food-app-terraform-state-294659523259/staging/terraform.tfstate-md5"},
    "Digest": {"S": "<CALCULATED_MD5>"}
  }' \
  --region ap-south-1
```

### Option 5: Delete DynamoDB Entry (Last Resort)

```bash
# Delete checksum entry
aws dynamodb delete-item \
  --table-name food-app-terraform-locks \
  --key '{"LockID": {"S": "food-app-terraform-state-294659523259/staging/terraform.tfstate-md5"}}' \
  --region ap-south-1

# Terraform will recreate it on next run
terraform init -backend-config=backend.hcl
```

### Option 6: Reset Remote State (Nuclear Option)

**⚠️ WARNING: Only if infrastructure is already destroyed!**

```bash
# Backup current state
aws s3 cp s3://food-app-terraform-state-294659523259/staging/terraform.tfstate ./backup-state.tfstate \
  --region ap-south-1

# Delete state file
aws s3 rm s3://food-app-terraform-state-294659523259/staging/terraform.tfstate \
  --region ap-south-1

# Delete all DynamoDB entries for this state
aws dynamodb delete-item \
  --table-name food-app-terraform-locks \
  --key '{"LockID": {"S": "food-app-terraform-state-294659523259/staging/terraform.tfstate"}}' \
  --region ap-south-1

aws dynamodb delete-item \
  --table-name food-app-terraform-locks \
  --key '{"LockID": {"S": "food-app-terraform-state-294659523259/staging/terraform.tfstate-md5"}}' \
  --region ap-south-1

# Reinitialize
cd terraform/envs/staging
terraform init -backend-config=backend.hcl
```

## For GitHub Actions Pipeline

If this happens in CI/CD, add retry logic:

```yaml
- name: Terraform init & apply staging
  working-directory: terraform/envs/staging
  run: |
    # Retry logic
    for i in {1..3}; do
      if terraform init "-backend-config=backend.hcl"; then
        break
      fi
      echo "Retrying terraform init (attempt $i/3)..."
      sleep 30
    done
    
    terraform apply -auto-approve \
      -var="image_tag=latest" \
      -var="desired_count=0"
```

## Prevention

1. **Never run terraform concurrently** on same environment
2. **Always use state locking** (already configured)
3. **Let terraform operations complete** before running another
4. **Use workspaces** for different environments (optional)

## Verify Fix

```bash
# Check DynamoDB entry
aws dynamodb get-item \
  --table-name food-app-terraform-locks \
  --key '{"LockID": {"S": "food-app-terraform-state-294659523259/staging/terraform.tfstate-md5"}}' \
  --region ap-south-1

# Check S3 state exists
aws s3 ls s3://food-app-terraform-state-294659523259/staging/ \
  --region ap-south-1

# Test terraform
terraform init -backend-config=backend.hcl
terraform plan
```

## How to Get Lock ID and Digest

### From Terraform Error Message (Easiest)

The error message contains everything you need:

```
Bucket: food-app-terraform-state-294659523259
Key:    staging/terraform.tfstate
Calculated checksum: d91d28a71054d3cb7d3eb4ab1acdb476  ← Use this (current S3 checksum)
Stored checksum:     f7a57a61abe8ca1ba831f1f6e86f0d31  ← Old DynamoDB checksum
```

**Lock ID Format:**
```
{bucket-name}/{key}-md5
```
Example: `food-app-terraform-state-294659523259/staging/terraform.tfstate-md5`

**Digest:**
Use the **"Calculated checksum"** value (what's currently in S3):
```
d91d28a71054d3cb7d3eb4ab1acdb476
```

### Calculate Digest from S3 State File

```bash
# Download state file
aws s3 cp s3://food-app-terraform-state-294659523259/staging/terraform.tfstate ./temp-state.tfstate \
  --region ap-south-1

# Calculate MD5 (Linux/Mac)
md5sum temp-state.tfstate

# Calculate MD5 (Windows PowerShell)
Get-FileHash -Algorithm MD5 temp-state.tfstate

# Calculate MD5 (Windows Git Bash)
md5sum temp-state.tfstate

# Clean up
rm temp-state.tfstate
```

### Check Current DynamoDB Entry

```bash
# See what's currently stored
aws dynamodb get-item \
  --table-name food-app-terraform-locks \
  --key '{"LockID": {"S": "food-app-terraform-state-294659523259/staging/terraform.tfstate-md5"}}' \
  --region ap-south-1
```

Output:
```json
{
  "Item": {
    "LockID": {"S": "food-app-terraform-state-294659523259/staging/terraform.tfstate-md5"},
    "Digest": {"S": "f7a57a61abe8ca1ba831f1f6e86f0d31"}  ← Old/wrong checksum
  }
}
```

### List All DynamoDB Entries

```bash
# See all locks and checksums
aws dynamodb scan \
  --table-name food-app-terraform-locks \
  --region ap-south-1
```

### Quick Reference Table

| Item | Where to Find | Example |
|------|---------------|----------|
| **Lock ID** | `{bucket}/{key}-md5` from error | `food-app-terraform-state-294659523259/staging/terraform.tfstate-md5` |
| **Digest** | Use **"Calculated checksum"** from error | `d91d28a71054d3cb7d3eb4ab1acdb476` |
| **Bucket** | From error message | `food-app-terraform-state-294659523259` |
| **Key** | From error message | `staging/terraform.tfstate` |
| **Region** | From backend.hcl | `ap-south-1` |

### Which Checksum To Use?

```
Calculated checksum: d91d28a71054d3cb7d3eb4ab1acdb476  ← Use this (matches current S3)
Stored checksum:     f7a57a61abe8ca1ba831f1f6e86f0d31  ← Old (out of sync)
```

**Always use the "Calculated checksum"** because:
- It matches what's currently in S3
- It's the truth source after your last operation
- DynamoDB needs to be updated to match S3

## Quick Fix for Your Current Error

Based on your error, run this immediately:

```bash
aws dynamodb put-item \
  --table-name food-app-terraform-locks \
  --item '{
    "LockID": {"S": "food-app-terraform-state-294659523259/staging/terraform.tfstate-md5"},
    "Digest": {"S": "d91d28a71054d3cb7d3eb4ab1acdb476"}
  }' \
  --region ap-south-1
```

**Note:** Use the "Calculated checksum" value from YOUR specific error message.

Then retry your pipeline or run:
```bash
cd terraform/envs/staging
terraform init -backend-config=backend.hcl
terraform apply -auto-approve -var="image_tag=latest" -var="desired_count=0"
```
