#!/bin/bash

# Script to create and populate API credentials in AWS Secrets Manager

set -e

# Configuration
SECRET_NAME="api-cron-app-credentials"
AWS_REGION="us-east-1"

echo "🔐 Setting up API credentials in AWS Secrets Manager..."

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

# Collect API credentials interactively
echo ""
echo "📝 Please provide the API authentication credentials:"
echo ""

read -p "Username: " USERNAME
read -s -p "Password: " PASSWORD
echo ""
read -p "Site: " SITE
read -p "Client ID: " CLIENT_ID
echo ""

# Create JSON payload for API credentials
SECRET_VALUE=$(cat <<EOF
{
  "username": "$USERNAME",
  "password": "$PASSWORD",
  "site": "$SITE",
  "client_id": "$CLIENT_ID"
}
EOF
)

if [ "$ACTION" = "create" ]; then
    echo "🔨 Creating API credentials secret in AWS Secrets Manager..."
    aws secretsmanager create-secret \
        --name "$SECRET_NAME" \
        --description "API authentication credentials for cron job" \
        --secret-string "$SECRET_VALUE" \
        --region "$AWS_REGION" \
        --tags '[{"Key":"Purpose","Value":"API Cron Job - Authentication"},{"Key":"SecretType","Value":"api-credentials"}]'
    
    echo "✅ API credentials secret created successfully!"
else
    echo "🔄 Updating existing API credentials secret..."
    aws secretsmanager update-secret \
        --secret-id "$SECRET_NAME" \
        --secret-string "$SECRET_VALUE" \
        --region "$AWS_REGION"
    
    echo "✅ API credentials secret updated successfully!"
fi

echo ""
echo "🎯 API Credentials Secret ARN:"
aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$AWS_REGION" --query 'ARN' --output text

echo ""
echo "📋 Next steps:"
echo "1. Run ./setup-splunk-secrets.sh to set up Splunk credentials"
echo "2. Update your terraform.tfvars file:"
echo "   api_credentials_secret_name = \"$SECRET_NAME\""
echo "   create_api_secret = false"
echo ""
echo "3. Run terraform plan and apply"
