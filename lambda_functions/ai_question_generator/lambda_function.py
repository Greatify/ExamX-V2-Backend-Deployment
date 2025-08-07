"""
AWS Lambda Function: AI Question Generator

This Lambda function handles AI-powered question generation tasks
that were previously handled by Celery workers.
"""

import json
import logging
import boto3
import os
import traceback
from datetime import datetime
from typing import Dict, Any, Optional
from openai import OpenAI

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3_client = boto3.client('s3')
secrets_client = boto3.client('secretsmanager')

# Global variables for reuse across invocations
openai_client = None
database_config = None


def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Main Lambda handler for AI question generation.
    
    Expected event structure:
    {
        "task_id": "uuid",
        "database_name": "tenant_db",
        "user_id": 123,
        "timestamp": "2024-01-01T00:00:00Z",
        "payload": {
            "task_name": "generate_ai_questions_in_celery",
            "payload": {
                "args": [],
                "kwargs": {
                    "question_gen_template": "...",
                    "database_name": "...",
                    "task_db_id": 123
                }
            },
            "timeout": 900
        },
        "metadata": {}
    }
    """
    
    try:
        logger.info(f"Lambda invocation started. Request ID: {context.aws_request_id}")
        logger.info(f"Event: {json.dumps(event, default=str)}")
        
        # Extract event data
        task_id = event.get('task_id')
        database_name = event.get('database_name')
        user_id = event.get('user_id')
        payload = event.get('payload', {})
        
        # Direct payload handling only (no S3)
        
        # Extract task-specific parameters
        task_payload = payload.get('payload', {})
        kwargs = task_payload.get('kwargs', {})
        
        question_gen_template = kwargs.get('question_gen_template')
        task_db_id = kwargs.get('task_db_id')
        
        if not question_gen_template or not task_db_id:
            raise ValueError("Missing required parameters: question_gen_template or task_db_id")
        
        logger.info(f"Processing AI question generation for task_db_id: {task_db_id}")
        
        # Update task status to RUNNING
        _update_task_status(task_id, 'RUNNING', database_name)
        
        # Initialize OpenAI client
        _initialize_openai_client()
        
        # Generate questions using OpenAI
        result = _generate_ai_questions(
            question_gen_template=question_gen_template,
            database_name=database_name,
            task_db_id=task_db_id,
            user_id=user_id
        )
        
        # Direct result return (no S3 storage)
        result_location = 'direct'
        
        # Update task status to SUCCESS
        _update_task_status(task_id, 'SUCCESS', database_name, result=result)
        
        # Update performance metrics
        _update_performance_metrics(task_id, context, database_name)
        
        logger.info(f"AI question generation completed successfully for task {task_id}")
        
        return {
            'statusCode': 200,
            'body': {
                'task_id': task_id,
                'status': 'SUCCESS',
                'result': result,
                'execution_time_ms': context.get_remaining_time_in_millis()
            }
        }
        
    except Exception as e:
        error_message = f"Lambda execution failed: {str(e)}"
        logger.error(error_message)
        logger.error(traceback.format_exc())
        
        # Update task status to FAILED
        if 'task_id' in locals():
            _update_task_status(task_id, 'FAILED', database_name, error_message=error_message)
        
        return {
            'statusCode': 500,
            'body': {
                'task_id': task_id if 'task_id' in locals() else None,
                'status': 'FAILED',
                'error': error_message,
                'traceback': traceback.format_exc()
            }
        }


def _initialize_openai_client():
    """Initialize OpenAI client with API key from environment variables."""
    global openai_client
    
    if openai_client is None:
        try:
            # Get OpenAI API key from environment variables
            api_key = os.environ.get('OPENAI_API_KEY')
            
            if not api_key:
                raise ValueError("OpenAI API key not found in environment variables")
            
            openai_client = OpenAI(api_key=api_key)
            logger.info("OpenAI client initialized successfully")
            
        except Exception as e:
            logger.error(f"Failed to initialize OpenAI client: {str(e)}")
            raise


def _generate_ai_questions(question_gen_template: str, 
                          database_name: str, 
                          task_db_id: int,
                          user_id: Optional[int]) -> Dict[str, Any]:
    """Generate AI questions using OpenAI."""
    
    try:
        logger.info(f"Starting OpenAI API call for task_db_id: {task_db_id}")
        
        # Make OpenAI API call
        response = openai_client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {
                    "role": "system",
                    "content": "You are an expert educational analyst AI. Provide precise numerical analysis for question paper metrics."
                },
                {
                    "role": "user", 
                    "content": question_gen_template
                }
            ],
            temperature=0.2
        )
        
        logger.info("GPT raw response received")
        
        # Parse GPT response
        gpt_response = response.choices[0].message.content
        question_content = gpt_response.replace('```json\n', '').replace('```', '')
        
        try:
            question_data = json.loads(question_content)
        except json.JSONDecodeError as e:
            logger.error(f"GPT response is not valid JSON: {gpt_response}")
            raise ValueError(f"The analysis response from GPT is not in valid JSON format: {str(e)}")
        
        logger.info(f"Parsed JSON GPT-generated question data: {len(question_data) if isinstance(question_data, list) else 'single_item'}")
        
        # Update database via API call (since we can't directly access the database)
        _update_question_generation_task(database_name, task_db_id, question_data)
        
        return {
            'success': True,
            'task_db_id': task_db_id,
            'question_data': question_data,
            'generated_count': len(question_data) if isinstance(question_data, list) else 1,
            'tokens_used': response.usage.total_tokens if hasattr(response, 'usage') else None
        }
        
    except Exception as e:
        logger.error(f"Error in AI question generation: {str(e)}")
        raise


def _update_question_generation_task(database_name: str, task_db_id: int, question_data: Dict[str, Any]):
    """Update QuestionGenerationTask via API call."""
    
    try:
        # Get API endpoint from environment
        api_base_url = os.environ.get('EXAMX_API_BASE_URL')
        if not api_base_url:
            logger.warning("EXAMX_API_BASE_URL not set, skipping database update")
            return
        
        # Get API authentication token
        api_token = os.environ.get('EXAMX_API_TOKEN')
        if not api_token:
            logger.warning("EXAMX_API_TOKEN not set, skipping database update")
            return
        
        # Make API call to update task
        import requests
        
        update_data = {
            'result_data': question_data,
            'progress_message': 'Generation complete. Results stored.',
            'progress_percent': 100,
            'status': 'SUCCESS'
        }
        
        headers = {
            'Authorization': f'Bearer {api_token}',
            'Content-Type': 'application/json',
            'X-Database-Name': database_name
        }
        
        response = requests.patch(
            f"{api_base_url}/api/ai-question-bank/tasks/{task_db_id}/",
            json=update_data,
            headers=headers,
            timeout=30
        )
        
        if response.status_code == 200:
            logger.info(f"Successfully updated QuestionGenerationTask {task_db_id}")
        else:
            logger.error(f"Failed to update QuestionGenerationTask: {response.status_code} - {response.text}")
        
    except Exception as e:
        logger.error(f"Error updating QuestionGenerationTask: {str(e)}")
        # Don't raise exception here to avoid breaking the main flow


def _load_payload_from_s3(s3_key: str) -> Dict[str, Any]:
    """Load payload from S3."""
    try:
        bucket_name = os.environ.get('LAMBDA_PAYLOAD_BUCKET', 'examx-lambda-payloads')
        
        response = s3_client.get_object(Bucket=bucket_name, Key=s3_key)
        payload = json.loads(response['Body'].read())
        
        logger.info(f"Loaded payload from S3: {s3_key}")
        return payload
        
    except Exception as e:
        logger.error(f"Failed to load payload from S3: {str(e)}")
        raise


def _store_result_in_s3(result: Dict[str, Any], task_id: str) -> str:
    """Store large result in S3."""
    try:
        bucket_name = os.environ.get('LAMBDA_RESULT_BUCKET', 'examx-lambda-results')
        s3_key = f"lambda-results/{datetime.utcnow().strftime('%Y/%m/%d')}/{task_id}.json"
        
        s3_client.put_object(
            Bucket=bucket_name,
            Key=s3_key,
            Body=json.dumps(result, default=str),
            ContentType='application/json',
            ServerSideEncryption='AES256'
        )
        
        logger.info(f"Result stored in S3: s3://{bucket_name}/{s3_key}")
        return s3_key
        
    except Exception as e:
        logger.error(f"Failed to store result in S3: {str(e)}")
        raise


def _update_task_status(task_id: str, 
                       status: str, 
                       database_name: str,
                       result: Dict[str, Any] = None,
                       error_message: str = None):
    """Update task status via API call."""
    try:
        api_base_url = os.environ.get('EXAMX_API_BASE_URL')
        api_token = os.environ.get('EXAMX_API_TOKEN')
        
        if not api_base_url or not api_token:
            logger.warning("API credentials not set, skipping status update")
            return
        
        import requests
        
        update_data = {
            'status': status,
            'completed_at': datetime.utcnow().isoformat() if status in ['SUCCESS', 'FAILED'] else None
        }
        
        if result:
            update_data['result'] = result
        
        if error_message:
            update_data['error_message'] = error_message
        
        headers = {
            'Authorization': f'Bearer {api_token}',
            'Content-Type': 'application/json',
            'X-Database-Name': database_name
        }
        
        response = requests.patch(
            f"{api_base_url}/api/lambda-tasks/{task_id}/",
            json=update_data,
            headers=headers,
            timeout=10
        )
        
        if response.status_code == 200:
            logger.info(f"Successfully updated task status: {task_id} -> {status}")
        else:
            logger.error(f"Failed to update task status: {response.status_code}")
        
    except Exception as e:
        logger.error(f"Error updating task status: {str(e)}")


def _update_performance_metrics(task_id: str, context, database_name: str):
    """Update performance metrics for the task."""
    try:
        # Calculate metrics
        execution_time_ms = context.get_remaining_time_in_millis()
        memory_used_mb = int(context.memory_limit_in_mb)
        
        # Estimate cost (rough calculation)
        # Lambda pricing: $0.0000166667 per GB-second
        execution_seconds = (900000 - execution_time_ms) / 1000  # Convert to seconds
        gb_seconds = (memory_used_mb / 1024) * execution_seconds
        estimated_cost = gb_seconds * 0.0000166667
        
        # Update via API (using klockwork.ai)
        api_base_url = os.environ.get('EXAMX_API_BASE_URL', 'https://klockwork.ai')
        
        if not api_base_url:
            return
        
        import requests
        
        metrics_data = {
            'execution_duration_ms': int(execution_seconds * 1000),
            'memory_used_mb': memory_used_mb,
            'estimated_cost_usd': round(estimated_cost, 6)
        }
        
        headers = {
            'Content-Type': 'application/json',
            'X-Database-Name': database_name
        }
        
        requests.patch(
            f"{api_base_url}/api/lambda-tasks/{task_id}/metrics/",
            json=metrics_data,
            headers=headers,
            timeout=10
        )
        
        logger.info(f"Performance metrics updated for task {task_id}")
        
    except Exception as e:
        logger.error(f"Error updating performance metrics: {str(e)}")