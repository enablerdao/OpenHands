#!/bin/bash
# DigitalOcean Deployment Script for OpenHands
# This script deploys OpenHands to DigitalOcean App Platform

set -e

# Configuration
APP_NAME="openhands"
REGION="nyc"  # Change to your preferred region

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if doctl CLI is installed
if ! command -v doctl &> /dev/null; then
    echo -e "${RED}DigitalOcean CLI (doctl) is not installed. Please install it first.${NC}"
    echo "Visit: https://docs.digitalocean.com/reference/doctl/how-to/install/"
    exit 1
fi

# Check if logged in to DigitalOcean
if ! doctl account get &> /dev/null; then
    echo -e "${YELLOW}Not logged in to DigitalOcean. Logging in...${NC}"
    doctl auth init
fi

# Build the application
echo -e "${YELLOW}Building the application...${NC}"
cd "$(dirname "$0")/.."
make build

# Create app.yaml for DigitalOcean App Platform
echo -e "${YELLOW}Creating app.yaml...${NC}"
cat > .do/app.yaml << EOF
name: ${APP_NAME}
region: ${REGION}
services:
- name: api
  github:
    branch: main
    deploy_on_push: true
    repo: enablerdao/OpenHands
  build_command: make build
  run_command: poetry run uvicorn openhands.server.listen:app --host 0.0.0.0 --port \$PORT
  http_port: 8080
  instance_count: 1
  instance_size_slug: basic-xs
  routes:
  - path: /api
  - path: /ws
  - path: /socket.io
  envs:
  - key: BACKEND_HOST
    value: 0.0.0.0
  - key: BACKEND_PORT
    value: "8080"

- name: frontend
  github:
    branch: main
    deploy_on_push: true
    repo: enablerdao/OpenHands
  build_command: cd frontend && npm install && npm run build
  output_dir: frontend/build
  routes:
  - path: /
EOF

# Create .do directory if it doesn't exist
mkdir -p .do

# Deploy to DigitalOcean App Platform
echo -e "${YELLOW}Deploying to DigitalOcean App Platform...${NC}"
doctl apps create --spec .do/app.yaml

# Get the app ID
APP_ID=$(doctl apps list --format ID,Spec.Name --no-header | grep ${APP_NAME} | awk '{print $1}')

# Wait for the deployment to complete
echo -e "${YELLOW}Waiting for deployment to complete...${NC}"
doctl apps get ${APP_ID} --format DefaultIngress --no-header

# Get the app URL
APP_URL=$(doctl apps get ${APP_ID} --format DefaultIngress --no-header)

echo -e "${GREEN}Deployment completed successfully!${NC}"
echo -e "Your application is available at: ${GREEN}https://${APP_URL}${NC}"