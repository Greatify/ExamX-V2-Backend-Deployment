# 🚀 Optimized Lambda Integration - Usage Examples

## **Database-Only Lambda Architecture Examples**

### **1. AI Question Generation (Optimized)**

```python
# ExamX-V2-Backend/ai_question_bank_generator/tasks.py

from utility.hybrid_task_decorator import hybrid_task
from django.db import OperationalError, InterfaceError
import json
import logging

logger = logging.getLogger(__name__)

@hybrid_task(
    lambda_function_name_env_var="LAMBDA_AI_QUESTION_GENERATOR",
    task_type="AI_QUESTION_GENERATION",
    bind=True,
    max_retries=3,
    autoretry_for=(OperationalError, InterfaceError),
    retry_backoff=True,
    queue="question_generator_ai",
    priority=8
)
def generate_ai_questions_optimized(self, question_gen_template, database_name, task_db_id):
    """
    Optimized AI question generation - routes to Lambda or Celery automatically.
    Results stored directly in database (no S3).
    """
    try:
        logger.info(f"Starting AI question generation - Task ID: {task_db_id}")
        
        # This decorator automatically:
        # 1. Checks if Lambda is enabled and available
        # 2. Routes to Lambda if conditions are met
        # 3. Falls back to Celery if needed
        # 4. Stores results directly in database
        
        # Core AI generation logic (runs in Lambda or Celery)
        from openai import OpenAI
        client = OpenAI()
        
        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": "You are an expert educational AI."},
                {"role": "user", "content": question_gen_template}
            ],
            temperature=0.2
        )
        
        gpt_response = response.choices[0].message.content
        question_data = json.loads(gpt_response.replace('```json\n', '').replace('```', ''))
        
        # Update database directly (no S3 involved)
        from ai_question_bank_generator.models import QuestionGenerationTask
        task = QuestionGenerationTask.objects.db_manager(database_name).get(id=task_db_id)
        task.result_data = question_data
        task.status = "SUCCESS"
        task.progress_percent = 100
        task.progress_message = "Generation complete"
        task.save()
        
        logger.info(f"AI question generation completed - Task ID: {task_db_id}")
        return {"status": "SUCCESS", "task_id": task_db_id, "result": question_data}
        
    except Exception as e:
        logger.error(f"AI question generation failed - Task ID: {task_db_id}: {e}")
        # Update task status to failed
        task = QuestionGenerationTask.objects.db_manager(database_name).get(id=task_db_id)
        task.status = "FAILED"
        task.progress_message = f"Generation failed: {str(e)}"
        task.save()
        raise
```

### **2. Document Processing (Optimized)**

```python
# ExamX-V2-Backend/ai_app/views/question_paper_parser.py

from utility.hybrid_task_decorator import hybrid_task
import logging

logger = logging.getLogger(__name__)

@hybrid_task(
    lambda_function_name_env_var="LAMBDA_DOCUMENT_PROCESSOR",
    task_type="DOCUMENT_PROCESSING",
    bind=True,
    max_retries=2,
    queue="document_processing",
    priority=7
)
def process_document_optimized(self, document_url, processing_id, database_name):
    """
    Optimized document processing - no LlamaParse, no S3 storage.
    Implement your preferred document processing method here.
    """
    try:
        logger.info(f"Starting document processing - ID: {processing_id}")
        
        # Alternative document processing implementation
        # Replace this with your preferred method:
        
        # Option 1: PyPDF2 for simple text extraction
        import PyPDF2
        import requests
        from io import BytesIO
        
        # Download document
        response = requests.get(document_url)
        pdf_file = BytesIO(response.content)
        
        # Extract text using PyPDF2
        pdf_reader = PyPDF2.PdfReader(pdf_file)
        extracted_text = ""
        for page in pdf_reader.pages:
            extracted_text += page.extract_text() + "\n"
        
        # Process extracted content
        processed_result = {
            'document_url': document_url,
            'extracted_text': extracted_text,
            'page_count': len(pdf_reader.pages),
            'processing_method': 'pypdf2',
            'status': 'completed',
            'timestamp': datetime.utcnow().isoformat()
        }
        
        # Update database directly (no S3)
        from ai_app.models import QuestionPaperProcessing
        processing_task = QuestionPaperProcessing.objects.db_manager(database_name).get(id=processing_id)
        processing_task.status = 'completed'
        processing_task.parsed_content = processed_result
        processing_task.save()
        
        logger.info(f"Document processing completed - ID: {processing_id}")
        return {"status": "SUCCESS", "processing_id": processing_id, "result": processed_result}
        
    except Exception as e:
        logger.error(f"Document processing failed - ID: {processing_id}: {e}")
        # Update status to failed
        processing_task = QuestionPaperProcessing.objects.db_manager(database_name).get(id=processing_id)
        processing_task.status = 'failed'
        processing_task.error_message = str(e)
        processing_task.save()
        raise
```

### **3. Lambda Function Example (AI Question Generator)**

```python
# lambda_functions/ai_question_generator/lambda_function.py (Optimized)

import json
import os
import logging
import requests
from datetime import datetime
from openai import OpenAI

logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO').upper())

def lambda_handler(event, context):
    """
    Optimized AI Question Generator Lambda - Direct result return, no S3.
    """
    try:
        # Extract task information
        task_id = event.get('task_id')
        database_name = event.get('database_name')
        payload = event.get('payload', {})
        
        logger.info(f"Processing AI question generation - Task: {task_id}")
        
        # Initialize OpenAI client
        openai_client = OpenAI(api_key=os.environ.get('OPENAI_API_KEY'))
        
        # Extract question generation template
        kwargs = payload.get('kwargs', {})
        question_gen_template = kwargs.get('question_gen_template', '')
        
        # Generate AI questions
        response = openai_client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": "You are an expert educational AI."},
                {"role": "user", "content": question_gen_template}
            ],
            temperature=0.2
        )
        
        gpt_response = response.choices[0].message.content
        question_data = json.loads(gpt_response.replace('```json\n', '').replace('```', ''))
        
        # Send result directly to Django API (no S3 storage)
        api_base_url = os.environ.get('EXAMX_API_BASE_URL', 'https://klockwork.ai')
        callback_url = f"{api_base_url}/api/lambda-tasks/{task_id}/complete/"
        
        callback_payload = {
            'task_id': task_id,
            'status': 'SUCCESS',
            'result': question_data,
            'database_name': database_name,
            'execution_duration_ms': context.get_remaining_time_in_millis()
        }
        
        # Send callback to Django
        headers = {
            'Content-Type': 'application/json',
            'X-Database-Name': database_name
        }
        
        response = requests.post(callback_url, json=callback_payload, headers=headers, timeout=30)
        response.raise_for_status()
        
        logger.info(f"AI question generation completed - Task: {task_id}")
        
        # Return result directly (no S3 references)
        return {
            'statusCode': 200,
            'body': {
                'task_id': task_id,
                'status': 'SUCCESS',
                'result': question_data
            }
        }
        
    except Exception as e:
        logger.error(f"AI question generation failed: {str(e)}")
        
        # Send error callback
        if 'task_id' in locals():
            error_callback = {
                'task_id': task_id,
                'status': 'FAILED',
                'error_message': str(e),
                'database_name': database_name
            }
            
            try:
                requests.post(f"{api_base_url}/api/lambda-tasks/{task_id}/complete/", 
                            json=error_callback, headers=headers, timeout=30)
            except:
                pass  # Don't fail on callback error
        
        return {
            'statusCode': 500,
            'body': {
                'task_id': task_id if 'task_id' in locals() else None,
                'status': 'FAILED',
                'error': str(e)
            }
        }
```

### **4. Django API Callback Handler (Optimized)**

```python
# ExamX-V2-Backend/admin_app/views/lambda_task_views.py

from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
from rest_framework.decorators import api_view
import json
import logging

logger = logging.getLogger(__name__)

@csrf_exempt
@api_view(['POST'])
def lambda_task_complete_callback(request, task_id):
    """
    Optimized callback handler for Lambda task completion.
    Receives results directly (no S3 involved).
    """
    try:
        data = json.loads(request.body)
        status = data.get('status')
        result = data.get('result')
        error_message = data.get('error_message')
        database_name = data.get('database_name')
        execution_duration = data.get('execution_duration_ms')
        
        logger.info(f"Received Lambda callback - Task: {task_id}, Status: {status}")
        
        # Update LambdaTaskExecution record
        from admin_app.models.lambda_models import LambdaTaskExecution
        
        task_execution = LambdaTaskExecution.objects.db_manager(database_name).get(
            task_id=task_id
        )
        
        task_execution.status = status
        task_execution.completed_at = timezone.now()
        
        if status == 'SUCCESS':
            # Store result directly in database (no S3)
            task_execution.result = result
        elif status == 'FAILED':
            task_execution.error_message = error_message
        
        if execution_duration:
            task_execution.execution_duration_ms = execution_duration
        
        task_execution.save()
        
        # Update related task models based on task type
        if hasattr(task_execution, 'question_generation_task') and task_execution.question_generation_task:
            related_task = task_execution.question_generation_task
            related_task.status = status
            if status == 'SUCCESS':
                related_task.result_data = result
                related_task.progress_percent = 100
                related_task.progress_message = "Generation complete"
            else:
                related_task.progress_message = f"Generation failed: {error_message}"
            related_task.save()
        
        logger.info(f"Lambda task callback processed successfully - Task: {task_id}")
        
        return JsonResponse({
            'status': 'success',
            'message': 'Callback processed successfully'
        })
        
    except Exception as e:
        logger.error(f"Error processing Lambda callback - Task: {task_id}: {e}")
        return JsonResponse({
            'status': 'error',
            'message': 'Failed to process callback'
        }, status=500)
```

### **5. Environment Configuration Example**

```bash
# .env file (optimized configuration)

# API Configuration
EXAMX_API_BASE_URL=https://klockwork.ai

# AWS Configuration
AWS_DEFAULT_REGION=ap-south-1
AWS_ACCESS_KEY_ID=your-access-key  # Optional if using IAM roles
AWS_SECRET_ACCESS_KEY=your-secret-key  # Optional if using IAM roles

# Lambda Function Names (from terraform output)
LAMBDA_AI_QUESTION_GENERATOR=examx-v2-ai-question-generator-production
LAMBDA_DOCUMENT_PROCESSOR=examx-v2-document-processor-production

# API Keys (required)
OPENAI_API_KEY=sk-your-actual-openai-api-key

# Lambda Task Routing
LAMBDA_ENABLE_AI_GENERATION=true
LAMBDA_ENABLE_DOCUMENT_PROCESSING=true
LAMBDA_FALLBACK_TO_CELERY=true

# Performance Settings
LAMBDA_TIMEOUT_SECONDS=900
LAMBDA_MEMORY_MB=1024
LAMBDA_MAX_PAYLOAD_SIZE=6291456  # 6MB

# Circuit Breaker
LAMBDA_CIRCUIT_BREAKER_ENABLED=true
LAMBDA_CIRCUIT_BREAKER_FAILURE_THRESHOLD=5
LAMBDA_CIRCUIT_BREAKER_TIMEOUT_SECONDS=300

# Cost Control
LAMBDA_MAX_DAILY_COST_USD=100.0
LAMBDA_COST_ALERT_THRESHOLD_USD=80.0

# Note: S3 bucket configurations removed
# Note: LLAMAPARSE_API_KEY removed
# Note: EXAMX_API_TOKEN removed
```

### **6. Testing the Optimized Integration**

```python
# Test script for optimized Lambda integration

from django.test import TestCase
from utility.hybrid_task_decorator import hybrid_task
from admin_app.models.lambda_models import LambdaTaskExecution

class OptimizedLambdaIntegrationTest(TestCase):
    
    def test_ai_question_generation_lambda_routing(self):
        """Test AI question generation routes to Lambda when enabled."""
        
        # Enable Lambda for AI generation
        with override_settings(LAMBDA_ENABLE_AI_GENERATION=True):
            from ai_question_bank_generator.tasks import generate_ai_questions_optimized
            
            # This should route to Lambda
            result = generate_ai_questions_optimized.delay(
                question_gen_template="Generate a test question about Python",
                database_name="test_db",
                task_db_id=123
            )
            
            # Check that LambdaTaskExecution record was created
            task_execution = LambdaTaskExecution.objects.filter(
                task_id=result.id
            ).first()
            
            self.assertIsNotNone(task_execution)
            self.assertEqual(task_execution.status, 'PENDING')
    
    def test_celery_fallback_when_lambda_disabled(self):
        """Test fallback to Celery when Lambda is disabled."""
        
        # Disable Lambda for AI generation
        with override_settings(LAMBDA_ENABLE_AI_GENERATION=False):
            from ai_question_bank_generator.tasks import generate_ai_questions_optimized
            
            # This should route to Celery
            result = generate_ai_questions_optimized.delay(
                question_gen_template="Generate a test question about Python",
                database_name="test_db",
                task_db_id=123
            )
            
            # Check that it's a Celery task
            self.assertTrue(hasattr(result, 'id'))
            self.assertFalse(LambdaTaskExecution.objects.filter(
                task_id=result.id
            ).exists())
    
    def test_direct_result_storage(self):
        """Test that results are stored directly in database (no S3)."""
        
        # Mock Lambda callback
        callback_data = {
            'task_id': 'test-123',
            'status': 'SUCCESS',
            'result': {'questions': [{'id': 1, 'text': 'Test question'}]},
            'database_name': 'test_db'
        }
        
        # Create task execution record
        task_execution = LambdaTaskExecution.objects.create(
            task_id='test-123',
            function_name='test-function',
            status='RUNNING'
        )
        
        # Process callback
        from admin_app.views.lambda_task_views import lambda_task_complete_callback
        
        response = self.client.post(
            f'/api/lambda-tasks/test-123/complete/',
            data=json.dumps(callback_data),
            content_type='application/json'
        )
        
        self.assertEqual(response.status_code, 200)
        
        # Check result stored in database
        task_execution.refresh_from_db()
        self.assertEqual(task_execution.status, 'SUCCESS')
        self.assertIsNotNone(task_execution.result)
        self.assertIsNone(task_execution.s3_result_key)  # No S3 key
```

---

## **🎯 Key Benefits of Optimized Architecture**

1. **💰 Cost Savings**: No S3 storage or transfer costs
2. **🚀 Performance**: Direct result return, no S3 I/O latency
3. **🔧 Simplicity**: Fewer AWS services to manage and monitor
4. **🛡️ Security**: No external file storage, database-only approach
5. **📊 Reliability**: Proven Django database patterns
6. **⚡ Scalability**: Lambda auto-scaling with database result storage

This optimized architecture provides all the benefits of Lambda for heavy tasks while maintaining the simplicity and reliability of database-only storage, exactly as you requested!