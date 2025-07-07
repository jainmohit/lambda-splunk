#!/usr/bin/env python3
"""
Test script to verify authentication flow locally before deployment
"""

import json
import urllib3
import sys

def test_auth_flow():
    """Test the authentication and API call flow"""
    
    # Configuration - update these values
    AUTH_ENDPOINT = "https://api.example.com/auth/token"
    API_ENDPOINT = "https://api.example.com/data"
    USERNAME = "your-username"
    PASSWORD = "your-password"
    SITE = "your-site"
    CLIENT_ID = "your-client-id"
    
    http = urllib3.PoolManager()
    
    print("🔐 Testing authentication flow...")
    
    # Step 1: Get bearer token
    print(f"📡 Calling auth endpoint: {AUTH_ENDPOINT}")
    
    auth_data = {
        'username': USERNAME,
        'password': PASSWORD,
        'site': SITE,
        'client_id': CLIENT_ID
    }
    
    headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
    }
    
    try:
        auth_response = http.request(
            'POST',
            AUTH_ENDPOINT,
            body=json.dumps(auth_data),
            headers=headers
        )
        
        print(f"Auth response status: {auth_response.status}")
        
        if auth_response.status == 200:
            token_data = json.loads(auth_response.data.decode('utf-8'))
            print("✅ Authentication successful!")
            print(f"Token data keys: {list(token_data.keys())}")
            
            # Extract token (adjust based on your API response format)
            if 'access_token' in token_data:
                bearer_token = token_data['access_token']
            elif 'token' in token_data:
                bearer_token = token_data['token']
            else:
                print("⚠️  Unknown token format. Available keys:", list(token_data.keys()))
                bearer_token = input("Enter the token key name: ")
                bearer_token = token_data.get(bearer_token)
            
            # Step 2: Call API with bearer token
            print(f"📡 Calling API endpoint: {API_ENDPOINT}")
            
            api_headers = {
                'Authorization': f'Bearer {bearer_token}',
                'Content-Type': 'application/json',
                'Accept': 'application/json'
            }
            
            api_response = http.request('GET', API_ENDPOINT, headers=api_headers)
            print(f"API response status: {api_response.status}")
            
            if api_response.status == 200:
                api_data = json.loads(api_response.data.decode('utf-8'))
                print("✅ API call successful!")
                print(f"Response data preview: {str(api_data)[:200]}...")
            else:
                print(f"❌ API call failed: {api_response.data.decode('utf-8')}")
                
        else:
            print(f"❌ Authentication failed: {auth_response.data.decode('utf-8')}")
            
    except Exception as e:
        print(f"❌ Error: {str(e)}")

if __name__ == "__main__":
    test_auth_flow()
