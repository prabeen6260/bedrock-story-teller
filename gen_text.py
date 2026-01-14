import boto3
import json

bedrock = boto3.client(
    service_name="bedrock-runtime",
    region_name="us-east-2"
)

# Claude 3.5 Haiku (US Cross-Region Inference Profile)
MODEL_ID = "us.anthropic.claude-3-5-haiku-20241022-v1:0"

def generate_story(prompt_text):
    """
    Generates a story using Claude 3.5 Haiku via Bedrock.
    Args:
        prompt_text (str): The user's input prompt.
    Returns:
        str: The generated story text.
    """
    
    # Construct the payload using the exact structure Claude 3 expects
    body = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 500,
        "temperature": 0.8,
        "messages": [
            {
                "role": "user",
                "content": prompt_text  # Uses the dynamic input now
            }
        ]
    }

    try:
        # Invoke model
        response = bedrock.invoke_model(
            modelId=MODEL_ID,
            body=json.dumps(body),
            contentType="application/json",
            accept="application/json"
        )

        # Parse response
        response_body = json.loads(response["body"].read())
        story = response_body["content"][0]["text"]
        
        return story

    except Exception as e:
        print(f"Error calling Bedrock: {e}")
        # In production, you might want to re-raise this or return a fallback
        raise e

# --- Local Testing Block ---
if __name__ == "__main__":
    test_prompt = "Write a short fantasy story about a dragon who is afraid of fire."
    print(generate_story(test_prompt))