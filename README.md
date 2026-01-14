# Bedrock Storyteller 🐑

A full-stack serverless application that generates short stories and matching scene illustrations using generative AI.

Live Demo: https://story-teller.lambda-lambs.com

---

## Technologies

### Architecture
The application runs entirely on serverless infrastructure, keeping costs near zero when idle.

### Tech Stack
- Frontend: React (Vite), TypeScript, CSS Modules.
- Backend: Python 3.12 (FastAPI), Dockerized.
- AI Models: AWS Bedrock (Claude 3 Haiku), Google Gemini (via API).
- Infrastructure: Terraform (IaC).
- CI/CD: GitHub Actions (OIDC authentication).
- Cloud Services:
  - Compute: AWS Lambda (Container Image).
  - Hosting: S3 + CloudFront (Global CDN).
  - DNS: Route 53.
  - Security: IAM Roles (Least Privilege).

## Key Features
- Hybrid AI Pipeline: Orchestrates calls between Bedrock (for high-quality narrative text) and generative models for visuals.
- Serverless Docker: The backend is packaged as a Docker container but runs on Lambda, avoiding the complexity of EC2/ECS.
- Automated Deployment: Commits to main trigger a pipeline that builds the Docker image, updates the Lambda function, builds the React frontend, and syncs it to S3.
- Infrastructure as Code: Entire AWS environment (Networking, Compute, Storage, DNS) is defined in Terraform.

## Local Development

### Prerequisites
- Node.js 18+
- Python 3.12
- Docker
- Terraform
- AWS CLI (configured)
...existing code...