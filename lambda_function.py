import json
import os
import boto3
import urllib3
import logging
from datetime import datetime, timedelta
from urllib.parse import urlencode
from zoneinfo import ZoneInfo

# Configure logging to be sent to CloudWatch
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS and HTTP clients
secrets_client = boto3.client('secretsmanager')
http = urllib3.PoolManager()

def get_api_credentials(secret_arn):
    """Retrieve API credentials from AWS Secrets Manager"""
    try:
        response = secrets_client.get_secret_value(SecretId=secret_arn)
        credentials = json.loads(response['SecretString'])
        
        required_fields = ['username', 'password', 'site', 'client_id']
        missing_fields = [field for field in required_fields if field not in credentials]
        
        if missing_fields:
            raise ValueError(f"Missing required API credential fields: {missing_fields}")
        
        logger.info("Successfully retrieved API credentials from Secrets Manager")
        return credentials
        
    except Exception as e:
        logger.error(f"Error retrieving API credentials: {str(e)}")
        raise

def get_bearer_token(auth_endpoint, username, password, site, client_id):
    """Get bearer token from the authentication endpoint"""
    try:
        auth_data = {
            'username': username,
            'password': password,
            'site': site,
            'client_id': client_id
        }
        headers = {'Content-Type': 'application/json', 'Accept': 'application/json'}
        
        logger.info(f"Requesting bearer token from: {auth_endpoint}")
        
        response = http.request('POST', auth_endpoint, body=json.dumps(auth_data), headers=headers)
        
        if response.status == 200:
            token_data = json.loads(response.data.decode('utf-8'))
            token = token_data.get('access_token') or token_data.get('token') or token_data.get('bearer_token')
            
            if not token:
                 raise ValueError("Could not identify token in authentication response")

            logger.info("Bearer token obtained successfully")
            return {
                'success': True,
                'token': token,
                'expires_in': token_data.get('expires_in'),
                'token_type': token_data.get('token_type', 'Bearer')
            }
        else:
            error_msg = f"Authentication failed with status: {response.status} - {response.data.decode('utf-8')}"
            logger.error(error_msg)
            return {'success': False, 'error': error_msg, 'status_code': response.status}
            
    except Exception as e:
        logger.error(f"Error getting bearer token: {str(e)}")
        return {'success': False, 'error': str(e)}

def call_api_with_token(url, bearer_token):
    """Call the target API using the obtained bearer token"""
    try:
        headers = {'Authorization': f'Bearer {bearer_token}', 'Accept': 'application/json'}
        logger.info(f"Calling API URL: {url}")
        
        response = http.request('GET', url, headers=headers)
        
        if response.status == 200:
            data = json.loads(response.data.decode('utf-8'))
            logger.info(f"API call successful. Status: {response.status}")
            return {
                'success': True,
                'status_code': response.status,
                'data': data,
                'timestamp': datetime.utcnow().isoformat()
            }
        else:
            error_msg = f"API call failed with status: {response.status} - {response.data.decode('utf-8')}"
            logger.warning(error_msg)
            return {
                'success': False,
                'status_code': response.status,
                'error': error_msg,
                'timestamp': datetime.utcnow().isoformat()
            }
    except Exception as e:
        logger.error(f"Error calling API: {str(e)}")
        return {'success': False, 'error': str(e), 'timestamp': datetime.utcnow().isoformat()}

def handler(event, context):
    """Lambda handler function"""
    execution_start = datetime.utcnow()
    logger.info(f"Starting cron job execution - Request ID: {context.aws_request_id}")
    
    try:
        # Get environment variables
        auth_endpoint = os.environ['AUTH_ENDPOINT']
        api_endpoint = os.environ['API_ENDPOINT']
        api_credentials_secret_arn = os.environ['API_CREDENTIALS_SECRET_ARN']
        
        # Step 1: Get API credentials from Secrets Manager
        api_credentials = get_api_credentials(api_credentials_secret_arn)
        
        # Step 2: Get bearer token
        token_result = get_bearer_token(
            auth_endpoint,
            api_credentials['username'],
            api_credentials['password'],
            api_credentials['site'],
            api_credentials['client_id']
        )
        
        if not token_result['success']:
            raise Exception(f"Authentication failed: {token_result['error']}")
        
        # Step 3: Construct API URL with dynamic start time
        try:
            sydney_tz = ZoneInfo("Australia/Sydney")
            now_sydney = datetime.now(tz=sydney_tz)
        except Exception as e:
            logger.warning(f"Could not load timezone 'Australia/Sydney'. Defaulting to UTC. Error: {e}")
            now_sydney = datetime.utcnow()

        start_time = now_sydney - timedelta(minutes=5)
        formatted_start_time = start_time.strftime('%H:%M')
        
        try:
            additional_params = json.loads(os.environ.get('ADDITIONAL_QUERY_PARAMS', '{}'))
        except json.JSONDecodeError:
            logger.error("Invalid JSON in ADDITIONAL_QUERY_PARAMS. Using empty params.")
            additional_params = {}

        query_params = {**additional_params, 'starttime': formatted_start_time}
        full_api_url = f"{api_endpoint}?{urlencode(query_params)}"
        logger.info(f"Constructed API URL: {full_api_url}")

        # Step 4: Call API with bearer token
        api_result = call_api_with_token(full_api_url, token_result['token'])
        
        # Log a comprehensive result object to CloudWatch
        final_log = {
            'execution_id': context.aws_request_id,
            'execution_start': execution_start.isoformat(),
            'auth_success': token_result['success'],
            'api_call_success': api_result['success'],
            'api_call_status_code': api_result.get('status_code'),
            'api_url_called': full_api_url,
            'execution_duration_ms': (datetime.utcnow() - execution_start).total_seconds() * 1000
        }
        
        if not api_result['success']:
            final_log['api_error'] = api_result.get('error')

        logger.info(f"Execution summary: {json.dumps(final_log, default=str)}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Cron job executed successfully',
                **final_log
            })
        }
        
    except Exception as e:
        # Log the exception to CloudWatch
        logger.error(f"Lambda execution failed: {str(e)}", exc_info=True)
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'error_type': type(e).__name__,
                'execution_id': context.aws_request_id,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
