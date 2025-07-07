#!/usr/bin/env python3
"""
Test script to verify both API and Splunk secrets are properly configured
"""

import boto3
import json
import sys

def test_api_credentials():
    """Test API credentials secret"""
    SECRET_NAME = "api-cron-app-credentials"
    AWS_REGION = "us-east-1"
    
    print(f"🔐 Testing API credentials secret: {SECRET_NAME}")
    
    try:
        secrets_client = boto3.client('secretsmanager', region_name=AWS_REGION)
        response = secrets_client.get_secret_value(SecretId=SECRET_NAME)
        credentials = json.loads(response['SecretString'])
        
        required_fields = ['username', 'password', 'site', 'client_id']
        missing_fields = []
        
        print("📋 Checking API credential fields:")
        for field in required_fields:
            if field in credentials:
                if field == 'password':
                    print(f"✅ {field}: [HIDDEN]")
                else:
                    print(f"✅ {field}: {credentials[field]}")
            else:
                print(f"❌ {field}: MISSING")
                missing_fields.append(field)
        
        return len(missing_fields) == 0
        
    except Exception as e:
        print(f"❌ Error retrieving API credentials: {str(e)}")
        return False

def test_splunk_credentials():
    """Test Splunk credentials secret"""
    SECRET_NAME = "api-cron-splunk-credentials"
    AWS_REGION = "us-east-1"
    
    print(f"\n🔐 Testing Splunk credentials secret: {SECRET_NAME}")
    
    try:
        secrets_client = boto3.client('secretsmanager', region_name=AWS_REGION)
        response = secrets_client.get_secret_value(SecretId=SECRET_NAME)
        credentials = json.loads(response['SecretString'])
        
        required_fields = ['hec_url', 'hec_token']
        optional_fields = ['index', 'sourcetype', 'source']
        missing_fields = []
        
        print("📋 Checking Splunk credential fields:")
        for field in required_fields:
            if field in credentials:
                if field == 'hec_token':
                    print(f"✅ {field}: [HIDDEN]")
                else:
                    print(f"✅ {field}: {credentials[field]}")
            else:
                print(f"❌ {field}: MISSING")
                missing_fields.append(field)
        
        for field in optional_fields:
            if field in credentials:
                print(f"✅ {field}: {credentials[field]}")
            else:
                print(f"⚠️  {field}: Not set (will use default)")
        
        return len(missing_fields) == 0
        
    except Exception as e:
        print(f"❌ Error retrieving Splunk credentials: {str(e)}")
        return False

def main():
    print("🧪 Testing AWS Secrets Manager configuration for API Cron Job")
    print("=" * 60)
    
    api_success = test_api_credentials()
    splunk_success = test_splunk_credentials()
    
    print("\n" + "=" * 60)
    if api_success and splunk_success:
        print("✅ All secrets are properly configured!")
        print("You can now deploy the Terraform infrastructure.")
        return True
    else:
        print("❌ Some secrets are missing or misconfigured.")
        print("\nTo fix:")
        if not api_success:
            print("1. Run: ./setup-api-secrets.sh")
        if not splunk_success:
            print("2. Run: ./setup-splunk-secrets.sh")
        return False

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
