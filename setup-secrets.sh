#!/bin/bash

# Script to create and populate AWS Secrets Manager secret

set -e

# Configuration
SECRET_NAME="api-cron-credentials"
AWS_REGION="us-east-1"

echo "🔐 Setting up AWS Secrets Manager secret..."

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

# Collect credentials interactively
echo ""
echo "📝 Please provide the following credentials:"
echo ""

read -p "Username: " USERNAME
read -s -p "Password: " PASSWORD
echo ""
read -p "Site: " SITE
read -p "Client ID: " CLIENT_ID
read -p "Splunk HEC URL: " SPLUNK_HEC_URL
read -s -p "Splunk HEC Token: " SPLUNK_HEC_TOKEN
echo ""

# Create JSON payload
SECRET_VALUE=$(cat <<EOF
{
  "username": "$USERNAME",
  "password": "$PASSWORD",
  "site": "$SITE",
  "client_id": "$CLIENT_ID",
  "splunk_hec_url": "$SPLUNK_HEC_URL",
  "splunk_hec_token": "$SPLUNK_HEC_TOKEN"
}
EOF
)

if [ "$ACTION" = "create" ]; then
    echo "🔨 Creating secret in AWS Secrets Manager..."
    aws secretsmanager create-secret \
        --name "$SECRET_NAME" \
        --description "API and Splunk credentials for cron job" \
        --secret-string "$SECRET_VALUE" \
        --region "$AWS_REGION"
    
    echo "✅ Secret created successfully!"
else
    echo "🔄 Updating existing secret..."
    aws secretsmanager update-secret \
        --secret-id "$SECRET_NAME" \
        --secret-string "$SECRET_VALUE" \
        --region "$AWS_REGION"
    
    echo "✅ Secret updated successfully!"
fi

echo ""
echo "🎯 Secret ARN:"
aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$AWS_REGION" --query 'ARN' --output text

echo ""
echo "📋 Next steps:"
echo "1. Update your terraform.tfvars file:"
echo "   secrets_manager_secret_name = \"$SECRET_NAME\""
echo "   create_secret = false"
echo ""
echo "2. Run terraform plan and apply"
