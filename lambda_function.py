import json
import os
import boto3
import urllib3
import logging
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize clients
secrets_client = boto3.client('secretsmanager')
http = urllib3.PoolManager()

def get_api_credentials(secret_arn):
    """Retrieve API credentials from AWS Secrets Manager"""
    try:
        response = secrets_client.get_secret_value(SecretId=secret_arn)
        credentials = json.loads(response['SecretString'])
        
        # Validate required fields for API credentials
        required_fields = ['username', 'password', 'site', 'client_id']
        missing_fields = [field for field in required_fields if field not in credentials]
        
        if missing_fields:
            raise ValueError(f"Missing required API credential fields: {missing_fields}")
        
        logger.info("Successfully retrieved API credentials from Secrets Manager")
        return credentials
        
    except Exception as e:
        logger.error(f"Error retrieving API credentials: {str(e)}")
        raise

def get_splunk_credentials(secret_arn):
    """Retrieve Splunk credentials from AWS Secrets Manager"""
    try:
        response = secrets_client.get_secret_value(SecretId=secret_arn)
        credentials = json.loads(response['SecretString'])
        
        # Validate required fields for Splunk credentials
        required_fields = ['hec_url', 'hec_token']
        missing_fields = [field for field in required_fields if field not in credentials]
        
        if missing_fields:
            raise ValueError(f"Missing required Splunk credential fields: {missing_fields}")
        
        # Set defaults for optional fields
        credentials.setdefault('index', 'main')
        credentials.setdefault('sourcetype', 'api_cron_job')
        credentials.setdefault('source', 'aws_lambda')
        
        logger.info("Successfully retrieved Splunk credentials from Secrets Manager")
        return credentials
        
    except Exception as e:
        logger.error(f"Error retrieving Splunk credentials: {str(e)}")
        raise

def get_bearer_token(auth_endpoint, username, password, site, client_id):
    """Get bearer token from authentication endpoint"""
    try:
        # Prepare authentication request body
        auth_data = {
            'username': username,
            'password': password,
            'site': site,
            'client_id': client_id
        }
        
        headers = {
            'Content-Type': 'application/json',
            'Accept': 'application/json'
        }
        
        logger.info(f"Requesting bearer token from: {auth_endpoint}")
        logger.info(f"Auth request for user: {username}, site: {site}, client_id: {client_id}")
        
        response = http.request(
            'POST',
            auth_endpoint,
            body=json.dumps(auth_data),
            headers=headers
        )
        
        if response.status == 200:
            token_data = json.loads(response.data.decode('utf-8'))
            
            # Common token response formats - adjust based on your API
            if 'access_token' in token_data:
                token = token_data['access_token']
            elif 'token' in token_data:
                token = token_data['token']
            elif 'bearer_token' in token_data:
                token = token_data['bearer_token']
            else:
                # Log available keys for debugging
                logger.warning(f"Unknown token format. Available keys: {list(token_data.keys())}")
                # Try to use the first string value as token
                for key, value in token_data.items():
                    if isinstance(value, str) and len(value) > 10:
                        token = value
                        logger.info(f"Using '{key}' as token field")
                        break
                else:
                    raise ValueError("Could not identify token in response")
            
            logger.info("Bearer token obtained successfully")
            return {
                'success': True,
                'token': token,
                'expires_in': token_data.get('expires_in'),
                'token_type': token_data.get('token_type', 'Bearer'),
                'response_keys': list(token_data.keys())
            }
        else:
            error_msg = f"Authentication failed with status: {response.status}"
            logger.error(error_msg)
            try:
                error_data = json.loads(response.data.decode('utf-8'))
                error_msg += f" - {error_data}"
            except:
                error_msg += f" - {response.data.decode('utf-8')}"
            
            return {
                'success': False,
                'error': error_msg,
                'status_code': response.status
            }
            
    except Exception as e:
        logger.error(f"Error getting bearer token: {str(e)}")
        return {
            'success': False,
            'error': str(e)
        }

def call_api_with_token(api_endpoint, bearer_token):
    """Call the API using bearer token"""
    try:
        headers = {
            'Authorization': f'Bearer {bearer_token}',
            'Content-Type': 'application/json',
            'Accept': 'application/json'
        }
        
        logger.info(f"Calling API endpoint: {api_endpoint}")
        
        response = http.request('GET', api_endpoint, headers=headers)
        
        if response.status == 200:
            data = json.loads(response.data.decode('utf-8'))
            logger.info(f"API call successful. Status: {response.status}")
            logger.info(f"Response data keys: {list(data.keys()) if isinstance(data, dict) else 'Non-dict response'}")
            
            return {
                'success': True,
                'status_code': response.status,
                'data': data,
                'data_size': len(str(data)),
                'timestamp': datetime.utcnow().isoformat()
            }
        else:
            error_msg = f"API call failed with status: {response.status}"
            try:
                error_data = json.loads(response.data.decode('utf-8'))
                error_msg += f" - {error_data}"
            except:
                error_msg += f" - {response.data.decode('utf-8')}"
            
            logger.warning(error_msg)
            return {
                'success': False,
                'status_code': response.status,
                'error': error_msg,
                'timestamp': datetime.utcnow().isoformat()
            }
    except Exception as e:
        logger.error(f"Error calling API: {str(e)}")
        return {
            'success': False,
            'error': str(e),
            'timestamp': datetime.utcnow().isoformat()
        }

def send_to_splunk(splunk_config, data):
    """Send data to Splunk via HEC"""
    try:
        headers = {
            'Authorization': f'Splunk {splunk_config["hec_token"]}',
            'Content-Type': 'application/json'
        }
        
        splunk_event = {
            'event': data,
            'sourcetype': splunk_config['sourcetype'],
            'source': splunk_config['source'],
            'index': splunk_config['index'],
            'host': 'aws-lambda-cron'
        }
        
        logger.info(f"Sending data to Splunk: {splunk_config['hec_url']}")
        logger.info(f"Splunk config - Index: {splunk_config['index']}, Sourcetype: {splunk_config['sourcetype']}")
        
        response = http.request(
            'POST',
            splunk_config['hec_url'],
            body=json.dumps(splunk_event),
            headers=headers
        )
        
        if response.status == 200:
            logger.info("Data sent to Splunk successfully")
            return True
        else:
            logger.error(f"Failed to send data to Splunk. Status: {response.status}")
            logger.error(f"Splunk response: {response.data.decode('utf-8')}")
            return False
            
    except Exception as e:
        logger.error(f"Error sending data to Splunk: {str(e)}")
        return False

def handler(event, context):
    """Lambda handler function"""
    execution_start = datetime.utcnow()
    
    try:
        # Get environment variables
        auth_endpoint = os.environ['AUTH_ENDPOINT']
        api_endpoint = os.environ['API_ENDPOINT']
        api_credentials_secret_arn = os.environ['API_CREDENTIALS_SECRET_ARN']
        splunk_credentials_secret_arn = os.environ['SPLUNK_CREDENTIALS_SECRET_ARN']
        
        logger.info(f"Starting cron job execution - Request ID: {context.aws_request_id}")
        logger.info(f"Auth endpoint: {auth_endpoint}")
        logger.info(f"API endpoint: {api_endpoint}")
        
        # Get credentials from both Secrets Manager secrets
        logger.info("Retrieving API credentials from Secrets Manager")
        api_credentials = get_api_credentials(api_credentials_secret_arn)
        
        logger.info("Retrieving Splunk credentials from Secrets Manager")
        splunk_credentials = get_splunk_credentials(splunk_credentials_secret_arn)
        
        # Step 1: Get bearer token
        logger.info("Step 1: Getting bearer token")
        token_result = get_bearer_token(
            auth_endpoint,
            api_credentials['username'],
            api_credentials['password'],
            api_credentials['site'],
            api_credentials['client_id']
        )
        
        if not token_result['success']:
            logger.error("Failed to obtain bearer token")
            raise Exception(f"Authentication failed: {token_result['error']}")
        
        # Step 2: Call API with bearer token
        logger.info("Step 2: Calling API with bearer token")
        api_result = call_api_with_token(api_endpoint, token_result['token'])
        
        # Combine results for logging and Splunk
        combined_result = {
            'execution_id': context.aws_request_id,
            'execution_start': execution_start.isoformat(),
            'execution_end': datetime.utcnow().isoformat(),
            'auth_success': token_result['success'],
            'auth_token_type': token_result.get('token_type'),
            'auth_expires_in': token_result.get('expires_in'),
            'api_call_result': api_result,
            'lambda_function': context.function_name,
            'lambda_version': context.function_version,
            'lambda_memory_limit': context.memory_limit_in_mb,
            'lambda_remaining_time': context.get_remaining_time_in_millis(),
            'secrets_used': {
                'api_credentials_secret': api_credentials_secret_arn.split(':')[-1],
                'splunk_credentials_secret': splunk_credentials_secret_arn.split(':')[-1]
            }
        }
        
        # Log to CloudWatch
        logger.info(f"Combined Result: {json.dumps(combined_result, default=str)}")
        
        # Step 3: Send to Splunk
        logger.info("Step 3: Sending data to Splunk")
        splunk_success = send_to_splunk(splunk_credentials, combined_result)
        
        # Prepare response
        response = {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Cron job executed successfully',
                'execution_id': context.aws_request_id,
                'auth_success': token_result['success'],
                'api_call_success': api_result['success'],
                'splunk_forward_success': splunk_success,
                'timestamp': datetime.utcnow().isoformat(),
                'execution_duration_ms': (datetime.utcnow() - execution_start).total_seconds() * 1000
            })
        }
        
        logger.info("Cron job execution completed successfully")
        return response
        
    except Exception as e:
        logger.error(f"Lambda execution error: {str(e)}")
        
        # Send error to Splunk as well (if Splunk credentials are available)
        error_data = {
            'execution_id': context.aws_request_id,
            'error': str(e),
            'error_type': type(e).__name__,
            'timestamp': datetime.utcnow().isoformat(),
            'lambda_function': context.function_name,
            'execution_duration_ms': (datetime.utcnow() - execution_start).total_seconds() * 1000
        }
        
        try:
            splunk_credentials = get_splunk_credentials(os.environ['SPLUNK_CREDENTIALS_SECRET_ARN'])
            send_to_splunk(splunk_credentials, error_data)
        except Exception as splunk_error:
            logger.error(f"Failed to send error data to Splunk: {str(splunk_error)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'execution_id': context.aws_request_id,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
