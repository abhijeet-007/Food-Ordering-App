# Run once to bootstrap Terraform remote state infrastructure
# Usage: .\bootstrap.ps1 -Region ap-south-1 -Project food-app

param(
    [string]$Region  = "ap-south-1",
    [string]$Project = "food-app"
)

$AccountId = aws sts get-caller-identity --query Account --output text
$Bucket    = "$Project-terraform-state-$AccountId"
$Table     = "$Project-terraform-locks"

Write-Host "Creating S3 bucket: $Bucket" -ForegroundColor Cyan

aws s3api create-bucket `
    --bucket $Bucket `
    --region $Region `
    --create-bucket-configuration LocationConstraint=$Region

aws s3api put-bucket-versioning `
    --bucket $Bucket `
    --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption `
    --bucket $Bucket `
    --server-side-encryption-configuration '{\"Rules\":[{\"ApplyServerSideEncryptionByDefault\":{\"SSEAlgorithm\":\"AES256\"}}]}'

aws s3api put-public-access-block `
    --bucket $Bucket `
    --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

Write-Host "Creating DynamoDB table: $Table" -ForegroundColor Cyan

aws dynamodb create-table `
    --table-name $Table `
    --attribute-definitions AttributeName=LockID,AttributeType=S `
    --key-schema AttributeName=LockID,KeyType=HASH `
    --billing-mode PAY_PER_REQUEST `
    --region $Region

Write-Host ""
Write-Host "Bootstrap complete!" -ForegroundColor Green
Write-Host "Update backend.hcl in each env with:" -ForegroundColor Yellow
Write-Host "  bucket = `"$Bucket`""
Write-Host "  dynamodb_table = `"$Table`""
Write-Host "  region = `"$Region`""
