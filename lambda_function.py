import json
import boto3
import os
import uuid
# Import your modules
from gen_text import generate_story
from gen_image import generate_image

s3 = boto3.client('s3', region_name='us-east-2')
BUCKET_NAME = "bedrock-storyteller-content-us-east-2" # We will create this in Terraform

def lambda_handler(event, context):
    try:
        # 1. Parse Input
        # API Gateway sends the body as a string, sometimes double-encoded
        body_str = event.get('body', '{}')
        body = json.loads(body_str) if isinstance(body_str, str) else body_str
        user_prompt = body.get('prompt', 'A cyberpunk cat')

        print(f"1. Received Prompt: {user_prompt}")

        # 2. Generate Text (Claude)
        enhanced_prompt = f"Write a creative short story (max 200 words) about: {user_prompt}"
        story_text = generate_story(enhanced_prompt)
        print("2. Story Generated")

        # 3. Generate Image (Gemini)
        # We use the story text as the prompt, or you can use the user_prompt
        image_path = generate_image(user_prompt) 
        print("3. Image Generated")

        # 4. Upload to S3
        unique_id = str(uuid.uuid4())[:8]
        story_key = f"{unique_id}_story.txt"
        image_key = f"{unique_id}_image.png"

        # Save story to /tmp to upload
        with open(f"/tmp/{story_key}", "w") as f:
            f.write(story_text)

        s3.upload_file(f"/tmp/{story_key}", BUCKET_NAME, story_key)
        s3.upload_file(image_path, BUCKET_NAME,image_key,ExtraArgs={'ContentType': 'image/png'}) 

        # 5. Return URLs
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Success',
                'story_text': story_text, # Return text directly for speed
                'image_url': f"https://{BUCKET_NAME}.s3.us-east-2.amazonaws.com/{image_key}"
            })
        }

    except Exception as e:
        print(f"ERROR: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f"Error: {str(e)}")
        }