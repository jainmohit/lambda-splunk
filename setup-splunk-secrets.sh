#!/bin/bash

# Script to create and populate Splunk credentials in AWS Secrets Manager

set -e

# Configuration
SECRET_NAME="api-cron-splunk-credentials"
AWS_REGION="us-east-1"

echo "🔐 Setting up Splunk credentials in AWS Secrets Manager..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if secret already exists
if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$AWS_REGION" &>/dev/null; then
    echo "⚠️  Secret '$SECRET_NAME' already exists."
    read -p "Do you want to update it? (yes/no): " update_secret
    
    if [ "$update_secret" != "yes" ]; then
        echo "❌ Setup cancelled."
        exit 1
    fi
    
    ACTION="update"
else
    ACTION="create"
fi

# Collect Splunk credentials interactively
echo ""
echo "📝 Please provide the Splunk configuration:"
echo ""

read -p "Splunk HEC URL: " SPLUNK_HEC_URL
read -s -p "Splunk HEC Token: " SPLUNK_HEC_TOKEN
echo ""
read -p "Splunk Index (default: main): " SPLUNK_INDEX
read -p "Splunk Sourcetype (default: api_cron_job): " SPLUNK_SOURCETYPE
read -p "Splunk Source (default: aws_lambda): " SPLUNK_SOURCE

# Set defaults if empty
SPLUNK_INDEX=${SPLUNK_INDEX:-main}
SPLUNK_SOURCETYPE=${SPLUNK_SOURCETYPE:-api_cron_job}
SPLUNK_SOURCE=${SPLUNK_SOURCE:-aws_lambda}

# Create JSON payload for Splunk credentials
SECRET_VALUE=$(cat <<EOF
{
  "hec_url": "$SPLUNK_HEC_URL",
  "hec_token": "$SPLUNK_HEC_TOKEN",
  "index": "$SPLUNK_INDEX",
  "sourcetype": "$SPLUNK_SOURCETYPE",
  "source": "$SPLUNK_SOURCE"
}
EOF
)

if [ "$ACTION" = "create" ]; then
    echo "🔨 Creating Splunk credentials secret in AWS Secrets Manager..."
    aws secretsmanager create-secret \
        --name "$SECRET_NAME" \
        --description "Splunk HEC credentials for cron job" \
        --secret-string "$SECRET_VALUE" \
        --region "$AWS_REGION" \
        --tags '[{"Key":"Purpose","Value":"API Cron Job - Splunk"},{"Key":"SecretType","Value":"splunk-credentials"}]'
    
    echo "✅ Splunk credentials secret created successfully!"
else
    echo "🔄 Updating existing Splunk credentials secret..."
    aws secretsmanager update-secret \
        --secret-id "$SECRET_NAME" \
        --secret-string "$SECRET_VALUE" \
        --region "$AWS_REGION"
    
    echo "✅ Splunk credentials secret updated successfully!"
fi

echo ""
echo "🎯 Splunk Credentials Secret ARN:"
aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$AWS_REGION" --query 'ARN' --output text

echo ""
echo "📋 Next steps:"
echo "1. Update your terraform.tfvars file:"
echo "   splunk_credentials_secret_name = \"$SECRET_NAME\""
echo "   create_splunk_secret = false"
echo ""
echo "2. Run terraform plan and apply"
