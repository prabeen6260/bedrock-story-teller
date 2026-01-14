import boto3
from google import genai
from google.genai import types
from PIL import Image
from io import BytesIO
import os

os.environ["GOOGLE_API_REGION"] = "us-central1"

def get_gemini_key():
    ssm = boto3.client('ssm', region_name='us-east-2') 
    parameter = ssm.get_parameter(
        Name='/my-app/gemini-key', 
        WithDecryption=True
    )
    return parameter['Parameter']['Value']

def generate_image(prompt):
    print(f"Generating image for: {prompt}")
    GOOGLE_API_KEY = get_gemini_key()
    client = genai.Client(api_key=GOOGLE_API_KEY)

    response = client.models.generate_content(
        model="gemini-2.5-flash-image",
        contents=[prompt],
        config=types.GenerateContentConfig(
            response_modalities=["IMAGE"] # Force image output
        )
    )

    if response.candidates and response.candidates[0].content.parts:
        for part in response.candidates[0].content.parts:
            
            # Handle Inline Image Data (Base64)
            if part.inline_data:
                # Decode the Bytes
                image_bytes = part.inline_data.data
                
                # Save to /tmp for Lambda compatibility
                output_path = "/tmp/image.png"
                img = Image.open(BytesIO(image_bytes))
                img.save(output_path)
                
                print(f"Image saved successfully to {output_path}")
                return output_path
                
    raise Exception("No image found in Gemini response")

# --- Local Testing ---
if __name__ == "__main__":
    generate_image("A cute robot holding a coffee cup")