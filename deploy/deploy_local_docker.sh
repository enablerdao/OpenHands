#!/bin/bash
# Local Docker Deployment Script for OpenHands
# This script deploys OpenHands locally using Docker

set -e

# Configuration
IMAGE_NAME="openhands"
CONTAINER_NAME="openhands-app"
BACKEND_PORT=3000
FRONTEND_PORT=3001
WORKSPACE_DIR="./workspace"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker is not installed. Please install it first.${NC}"
    exit 1
fi

# Build the application
echo -e "${YELLOW}Building the application...${NC}"
cd "$(dirname "$0")/.."
make build

# Create Docker network if it doesn't exist
if ! docker network inspect openhands-network &> /dev/null; then
    echo -e "${YELLOW}Creating Docker network: openhands-network...${NC}"
    docker network create openhands-network
fi

# Stop and remove existing container if it exists
if docker ps -a | grep -q ${CONTAINER_NAME}; then
    echo -e "${YELLOW}Stopping and removing existing container...${NC}"
    docker stop ${CONTAINER_NAME} || true
    docker rm ${CONTAINER_NAME} || true
fi

# Build Docker image
echo -e "${YELLOW}Building Docker image: ${IMAGE_NAME}...${NC}"
docker build -t ${IMAGE_NAME}:latest .

# Create workspace directory if it doesn't exist
mkdir -p ${WORKSPACE_DIR}

# Run the container
echo -e "${YELLOW}Running container: ${CONTAINER_NAME}...${NC}"
docker run -d \
    --name ${CONTAINER_NAME} \
    --network openhands-network \
    -p ${BACKEND_PORT}:${BACKEND_PORT} \
    -p ${FRONTEND_PORT}:${FRONTEND_PORT} \
    -v ${WORKSPACE_DIR}:/app/workspace \
    -e BACKEND_HOST=0.0.0.0 \
    -e BACKEND_PORT=${BACKEND_PORT} \
    -e FRONTEND_PORT=${FRONTEND_PORT} \
    ${IMAGE_NAME}:latest

# Wait for the application to start
echo -e "${YELLOW}Waiting for the application to start...${NC}"
sleep 5

# Check if the container is running
if docker ps | grep -q ${CONTAINER_NAME}; then
    echo -e "${GREEN}Container is running successfully!${NC}"
    echo -e "Backend is available at: ${GREEN}http://localhost:${BACKEND_PORT}${NC}"
    echo -e "Frontend is available at: ${GREEN}http://localhost:${FRONTEND_PORT}${NC}"
else
    echo -e "${RED}Container failed to start. Check logs with: docker logs ${CONTAINER_NAME}${NC}"
    exit 1
fi

# Show container logs
echo -e "${YELLOW}Container logs:${NC}"
docker logs ${CONTAINER_NAME} --tail 20