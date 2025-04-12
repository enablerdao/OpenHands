#!/bin/bash
# Google Cloud Platform Deployment Script for OpenHands
# This script deploys OpenHands to GCP using Cloud Run

set -e

# Configuration
PROJECT_ID=""  # Your GCP project ID
REGION="us-central1"  # Change to your preferred region
SERVICE_NAME="openhands"
MEMORY="2Gi"
CPU="1"
MIN_INSTANCES="0"
MAX_INSTANCES="10"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if gcloud CLI is installed
if ! command -v gcloud &> /dev/null; then
    echo -e "${RED}Google Cloud SDK is not installed. Please install it first.${NC}"
    echo "Visit: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker is not installed. Please install it first.${NC}"
    exit 1
fi

# Get project ID if not provided
if [ -z "$PROJECT_ID" ]; then
    PROJECT_ID=$(gcloud config get-value project)
    if [ -z "$PROJECT_ID" ]; then
        echo -e "${RED}No project ID provided and no default project set.${NC}"
        echo "Please set a project ID in the script or run 'gcloud config set project YOUR_PROJECT_ID'"
        exit 1
    fi
fi

# Build the application
echo -e "${YELLOW}Building the application...${NC}"
cd "$(dirname "$0")/.."
make build

# Build and tag the Docker image
IMAGE_NAME="gcr.io/${PROJECT_ID}/${SERVICE_NAME}"
echo -e "${YELLOW}Building Docker image: ${IMAGE_NAME}...${NC}"
docker build -t ${IMAGE_NAME} .

# Push the image to Google Container Registry
echo -e "${YELLOW}Pushing image to Google Container Registry...${NC}"
gcloud auth configure-docker --quiet
docker push ${IMAGE_NAME}

# Deploy to Cloud Run
echo -e "${YELLOW}Deploying to Cloud Run...${NC}"
gcloud run deploy ${SERVICE_NAME} \
    --image ${IMAGE_NAME} \
    --platform managed \
    --region ${REGION} \
    --memory ${MEMORY} \
    --cpu ${CPU} \
    --min-instances ${MIN_INSTANCES} \
    --max-instances ${MAX_INSTANCES} \
    --allow-unauthenticated \
    --port 3000

# Get the service URL
SERVICE_URL=$(gcloud run services describe ${SERVICE_NAME} --platform managed --region ${REGION} --format="value(status.url)")

echo -e "${GREEN}Deployment completed successfully!${NC}"
echo -e "Your application is available at: ${GREEN}${SERVICE_URL}${NC}"