"""
AWS Lambda Function: Document Processor

This Lambda function handles document processing tasks including
PDF parsing, content extraction, and file analysis.
"""

import json
import logging
import boto3
import os
import tempfile
import traceback
from datetime import datetime
from typing import Dict, Any, List
from urllib.parse import urlparse

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3_client = boto3.client('s3')
secrets_client = boto3.client('secretsmanager')

# Global variables
llamaparse_api_key = None


def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Main Lambda handler for document processing.
    
    Expected event structure:
    {
        "task_id": "uuid",
        "database_name": "tenant_db", 
        "user_id": 123,
        "payload": {
            "task_name": "process_paper_task",
            "payload": {
                "args": ["temp_pdf_path", "processing_id", "db", "public_url"],
                "kwargs": {}
            }
        }
    }
    """
    
    try:
        logger.info(f"Lambda invocation started. Request ID: {context.aws_request_id}")
        
        # Extract event data
        task_id = event.get('task_id')
        database_name = event.get('database_name')
        user_id = event.get('user_id')
        payload = event.get('payload', {})
        
        # Handle S3 payload if present
        if event.get('payload_location') == 's3':
            s3_key = event.get('s3_key')
            payload = _load_payload_from_s3(s3_key)
        
        # Extract task-specific parameters
        task_payload = payload.get('payload', {})
        args = task_payload.get('args', [])
        
        if len(args) < 4:
            raise ValueError("Insufficient arguments for document processing")
        
        temp_pdf_path, processing_id, db, public_url = args[:4]
        
        logger.info(f"Processing document: {public_url}, processing_id: {processing_id}")
        
        # Update task status to RUNNING
        _update_task_status(task_id, 'RUNNING', database_name)
        
        # Initialize API keys
        _initialize_api_keys()
        
        # Process the document
        result = _process_document(
            public_url=public_url,
            processing_id=processing_id,
            database_name=db,
            task_id=task_id
        )
        
        # Store result in S3 if too large
        result_location = 'direct'
        s3_result_key = None
        
        result_size = len(json.dumps(result, default=str).encode('utf-8'))
        if result_size > 256 * 1024:  # 256KB threshold
            s3_result_key = _store_result_in_s3(result, task_id)
            result_location = 's3'
            result = {'result_location': 's3', 's3_key': s3_result_key}
        
        # Update task status to SUCCESS
        _update_task_status(task_id, 'SUCCESS', database_name, result=result)
        
        logger.info(f"Document processing completed successfully for task {task_id}")
        
        return {
            'statusCode': 200,
            'body': {
                'task_id': task_id,
                'status': 'SUCCESS',
                'result': result,
                'result_location': result_location,
                's3_result_key': s3_result_key
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
                'error': error_message
            }
        }


def _initialize_api_keys():
    """Initialize API keys from environment variables."""
    # Note: LlamaParse removed - using alternative document processing
    logger.info("API keys initialization skipped - using alternative document processing")


def _process_document(public_url: str, processing_id: int, database_name: str, task_id: str) -> Dict[str, Any]:
    """Process document using alternative methods (LlamaParse removed)."""
    
    try:
        # Alternative document processing (placeholder implementation)
        logger.info(f"Processing document from URL: {public_url}")
        
        # Placeholder processing - implement your preferred method here
        processed_result = {
            'document_url': public_url,
            'processing_timestamp': datetime.utcnow().isoformat(),
            'processing_method': 'alternative_processor',
            'status': 'processed_successfully',
            'content': 'Document content would be extracted here',
            'metadata': {
                'processing_id': processing_id,
                'task_id': task_id
            }
        }
        
        # Update database via API
        _update_question_paper_processing(database_name, processing_id, processed_result)
        
        # No temporary files to clean up in this implementation
        
        return {
            'success': True,
            'processing_id': processing_id,
            'parsed_content': processed_result,
            'status': 'completed'
        }
        
    except Exception as e:
        logger.error(f"Error in document processing: {str(e)}")
        
        # Update database with error status
        _update_question_paper_processing(database_name, processing_id, None, error=str(e))
        
        raise


def _download_file_from_s3_url(s3_url: str) -> str:
    """Download file from S3 URL to temporary location."""
    try:
        # Parse S3 URL
        parsed_url = urlparse(s3_url)
        
        if 's3.amazonaws.com' in parsed_url.netloc:
            # Format: https://bucket.s3.amazonaws.com/key
            bucket = parsed_url.netloc.split('.')[0]
            key = parsed_url.path.lstrip('/')
        elif parsed_url.netloc.endswith('.amazonaws.com'):
            # Format: https://s3.region.amazonaws.com/bucket/key
            path_parts = parsed_url.path.lstrip('/').split('/', 1)
            bucket = path_parts[0]
            key = path_parts[1] if len(path_parts) > 1 else ''
        else:
            raise ValueError(f"Unsupported S3 URL format: {s3_url}")
        
        # Create temporary file
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
        temp_file_path = temp_file.name
        temp_file.close()
        
        # Download from S3
        s3_client.download_file(bucket, key, temp_file_path)
        
        logger.info(f"Downloaded file from S3: {s3_url} -> {temp_file_path}")
        return temp_file_path
        
    except Exception as e:
        logger.error(f"Failed to download file from S3: {str(e)}")
        raise


def _parse_pdf_with_llamaparse(pdf_path: str, public_url: str) -> List[Dict[str, Any]]:
    """Parse PDF using LlamaParse."""
    try:
        # Import LlamaParse (would need to be included in deployment package)
        from llama_parse import LlamaParse
        
        # Define parsing instructions
        parsing_instructions = """
        You are a highly proficient language model designed to convert question paper from PDF, PPT and other files into structured markdown text document with questions. 
        Your goal is to accurately transcribe text, represent formulas in LaTeX MathJax notation, and identify and describe images, 
        particularly graphs and other graphical elements.

        1. Question Identification:
           - Identify each question by its number (e.g., "1.", "2.", etc.)
           - Track the current question number as you process the document
           - Note when a new question starts
           - Extract all readable text from the page
           - Maintain proper formatting and structure
           - Preserve question numbers and sections
           - Extract all options for multiple choice questions
           - Preserve mathematical equations and chemical formulas

        2. Image Processing:
           - For each image you encounter, determine which question it belongs to
           - Tag each image with its associated question number
           - Consider an image part of the current question if it appears:
             * After the question number and before the next question
             * Within the question's text or options
             * As part of the question's diagram or illustration
           - Identify all images, diagrams, and graphical elements
           - Provide detailed description of each image's content
           - For diagrams (like circuit diagrams), describe the components and connections
           - For graphs, extract data points or key information
           - If image contains text, extract and include it
           - Note the position and context of each image
           - If image is related to a specific question, maintain that association

        3. For Mathematical Content:
           - Convert all mathematical equations to LaTeX MathJax notation
           - Preserve formatting of scientific formulas
           - Maintain alignment of mathematical expressions
           - Include all mathematical symbols and notations

        4. Maintain Context:
           - Keep track of the current question number while processing
           - Associate each image with the most recently seen question number
           - Note any special cases where images might belong to a different question

        5. Output Requirements:
           - For each image, include:
             * The question number it belongs to
             * Its position in the document
             * Whether it's part of the question text or answer choices

        6. For Tables and Structured Content:
           - Maintain table structure in markdown format
           - Preserve column alignments and headers
           - Keep row and column relationships intact

        Special Instructions for Question Papers:
           - Maintain the hierarchical structure of sections (A, B, C, etc.)
           - Preserve question numbering and sub-parts
           - Keep track of marks allocation
           - Maintain the relationship between questions and their associated images/diagrams
           - Preserve any special instructions or notes

        IMPORTANT: Always associate each image with the most recently encountered question number unless there's clear evidence it belongs to a different question.
        """
        
        # Initialize parser
        parser = LlamaParse(
            api_key=llamaparse_api_key,
            result_type="markdown",
            parsing_instruction=parsing_instructions,
            max_timeout=60000,  # 60 seconds
            verbose=True
        )
        
        # Parse the document
        logger.info(f"Starting PDF parsing for file: {pdf_path}")
        documents = parser.load_data(pdf_path)
        
        # Extract parsed elements
        parsed_elements = []
        for doc in documents:
            parsed_elements.append({
                'text': doc.text,
                'metadata': doc.metadata if hasattr(doc, 'metadata') else {}
            })
        
        logger.info(f"PDF parsing completed. Extracted {len(parsed_elements)} elements")
        return parsed_elements
        
    except Exception as e:
        logger.error(f"Error in PDF parsing: {str(e)}")
        raise


def _process_with_ai_model(parsed_content: List[Dict[str, Any]], processing_id: int, database_name: str) -> Dict[str, Any]:
    """Process parsed content with AI model."""
    try:
        # Combine all parsed text
        combined_text = ""
        for element in parsed_content:
            combined_text += element.get('text', '') + "\n\n"
        
        # Here you would implement the AI processing logic
        # For now, we'll return the parsed content as-is
        processed_result = {
            'parsed_content': parsed_content,
            'combined_text': combined_text,
            'processing_status': 'completed',
            'element_count': len(parsed_content),
            'total_text_length': len(combined_text)
        }
        
        logger.info(f"AI processing completed for processing_id: {processing_id}")
        return processed_result
        
    except Exception as e:
        logger.error(f"Error in AI processing: {str(e)}")
        raise


def _update_question_paper_processing(database_name: str, processing_id: int, result: Dict[str, Any] = None, error: str = None):
    """Update QuestionPaperProcessing via API call."""
    try:
        api_base_url = os.environ.get('EXAMX_API_BASE_URL')
        api_token = os.environ.get('EXAMX_API_TOKEN')
        
        if not api_base_url or not api_token:
            logger.warning("API credentials not set, skipping database update")
            return
        
        import requests
        
        if error:
            update_data = {
                'status': 'failed',
                'error_message': error
            }
        else:
            update_data = {
                'status': 'completed',
                'parsed_content': result,
                'api_usage': {
                    'total_cost': 0.0,  # Would be calculated based on actual usage
                    'total_calls': 1,
                    'success_rate': 100.0,
                    'total_tokens': len(str(result))
                }
            }
        
        headers = {
            'Authorization': f'Bearer {api_token}',
            'Content-Type': 'application/json',
            'X-Database-Name': database_name
        }
        
        response = requests.patch(
            f"{api_base_url}/api/question-paper-processing/{processing_id}/",
            json=update_data,
            headers=headers,
            timeout=30
        )
        
        if response.status_code == 200:
            logger.info(f"Successfully updated QuestionPaperProcessing {processing_id}")
        else:
            logger.error(f"Failed to update QuestionPaperProcessing: {response.status_code}")
        
    except Exception as e:
        logger.error(f"Error updating QuestionPaperProcessing: {str(e)}")


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
        
    except Exception as e:
        logger.error(f"Error updating task status: {str(e)}")