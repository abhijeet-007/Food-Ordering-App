#!/bin/bash
# Run once to bootstrap Terraform remote state infrastructure
# Usage: ./bootstrap.sh <aws-region> <project-name>

set -e

REGION=${1:-"ap-south-1"}
PROJECT=${2:-"food-app"}
BUCKET="${PROJECT}-terraform-state-$(aws sts get-caller-identity --query Account --output text)"
TABLE="${PROJECT}-terraform-locks"

echo "Creating S3 bucket: $BUCKET"
if [ "$REGION" = "ap-south-1" ]; then
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION"
else
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION"
fi

aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket "$BUCKET" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}
    }]
  }'

aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

echo "Creating DynamoDB table: $TABLE"
aws dynamodb create-table \
  --table-name "$TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$REGION"

echo ""
echo "Bootstrap complete. Add to your backend.tf:"
echo "  bucket         = \"$BUCKET\""
echo "  dynamodb_table = \"$TABLE\""
echo "  region         = \"$REGION\""
