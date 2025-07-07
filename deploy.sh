#!/bin/bash

# Enhanced deployment script for the API cron job infrastructure

set -e

echo "🚀 Deploying API Cron Job Infrastructure..."

# Check if terraform.tfvars exists
if [ ! -f "terraform.tfvars" ]; then
    echo "❌ terraform.tfvars file not found!"
    echo "Please copy terraform.tfvars.example to terraform.tfvars and fill in your values."
    exit 1
fi

# Check if AWS CLI is available
if ! command -v aws &> /dev/null; then
    echo "⚠️  AWS CLI not found. Please install it for secret management."
fi

# Check if secrets are set up
API_SECRET_NAME=$(grep "api_credentials_secret_name" terraform.tfvars | cut -d'"' -f2)
SPLUNK_SECRET_NAME=$(grep "splunk_credentials_secret_name" terraform.tfvars | cut -d'"' -f2)
CREATE_API_SECRET=$(grep "create_api_secret" terraform.tfvars | grep -o "true\|false")
CREATE_SPLUNK_SECRET=$(grep "create_splunk_secret" terraform.tfvars | grep -o "true\|false")

echo "📋 Secret Configuration:"
echo "  API Secret: $API_SECRET_NAME (create: $CREATE_API_SECRET)"
echo "  Splunk Secret: $SPLUNK_SECRET_NAME (create: $CREATE_SPLUNK_SECRET)"
echo ""

if [ "$CREATE_API_SECRET" = "true" ] || [ "$CREATE_SPLUNK_SECRET" = "true" ]; then
    echo "⚠️  You have create_*_secret = true in terraform.tfvars"
    echo "This will create empty secrets. You'll need to populate them manually."
    echo ""
    echo "To set up secrets properly:"
    if [ "$CREATE_API_SECRET" = "true" ]; then
        echo "1. Run: chmod +x setup-api-secrets.sh && ./setup-api-secrets.sh"
    fi
    if [ "$CREATE_SPLUNK_SECRET" = "true" ]; then
        echo "2. Run: chmod +x setup-splunk-secrets.sh && ./setup-splunk-secrets.sh"
    fi
    echo "3. Update terraform.tfvars: create_api_secret = false, create_splunk_secret = false"
    echo "4. Re-run this deployment script"
    echo ""
    read -p "Continue with empty secret creation? (yes/no): " continue_empty
    
    if [ "$continue_empty" != "yes" ]; then
        echo "❌ Deployment cancelled."
        echo "Please set up secrets first using the setup scripts."
        exit 1
    fi
fi

# Initialize Terraform
echo "📦 Initializing Terraform..."
terraform init

# Validate configuration
echo "✅ Validating Terraform configuration..."
terraform validate

# Plan deployment
echo "📋 Planning deployment..."
terraform plan

# Apply deployment
echo "🔨 Applying deployment..."
terraform apply -auto-approve

echo "✅ Deployment completed successfully!"
echo ""
echo "📊 Resources created:"
terraform output

echo ""
echo "🔍 To monitor the cron job:"
echo "1. Check CloudWatch Logs: /aws/lambda/api-cron-function"
echo "2. Monitor Lambda function: api-cron-function"
echo "3. Check EventBridge rule: api-cron-schedule"

if [ "$CREATE_API_SECRET" = "true" ] || [ "$CREATE_SPLUNK_SECRET" = "true" ]; then
    echo ""
    echo "⚠️  IMPORTANT: Don't forget to populate your secrets!"
    if [ "$CREATE_API_SECRET" = "true" ]; then
        echo "Run: ./setup-api-secrets.sh"
    fi
    if [ "$CREATE_SPLUNK_SECRET" = "true" ]; then
        echo "Run: ./setup-splunk-secrets.sh"
    fi
fi
