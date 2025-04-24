#!/bin/bash
# Azure Deployment Script for OpenHands
# This script deploys OpenHands to Azure using Azure Container Instances

set -e

# Configuration
RESOURCE_GROUP="openhands-rg"
LOCATION="eastus"  # Change to your preferred region
CONTAINER_NAME="openhands"
IMAGE_NAME="openhands"
REGISTRY_NAME="openhandsregistry"  # Must be globally unique
CPU="2"
MEMORY="4"  # In GB
DNS_NAME_LABEL="openhands"  # Must be globally unique within the Azure region

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo -e "${RED}Azure CLI is not installed. Please install it first.${NC}"
    echo "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker is not installed. Please install it first.${NC}"
    exit 1
fi

# Check if logged in to Azure
if ! az account show &> /dev/null; then
    echo -e "${YELLOW}Not logged in to Azure. Logging in...${NC}"
    az login
fi

# Build the application
echo -e "${YELLOW}Building the application...${NC}"
cd "$(dirname "$0")/.."
make build

# Create resource group if it doesn't exist
if ! az group show --name ${RESOURCE_GROUP} &> /dev/null; then
    echo -e "${YELLOW}Creating resource group: ${RESOURCE_GROUP}...${NC}"
    az group create --name ${RESOURCE_GROUP} --location ${LOCATION}
fi

# Create Azure Container Registry if it doesn't exist
if ! az acr show --name ${REGISTRY_NAME} &> /dev/null; then
    echo -e "${YELLOW}Creating Azure Container Registry: ${REGISTRY_NAME}...${NC}"
    az acr create --resource-group ${RESOURCE_GROUP} --name ${REGISTRY_NAME} --sku Basic
fi

# Log in to the container registry
echo -e "${YELLOW}Logging in to Azure Container Registry...${NC}"
az acr login --name ${REGISTRY_NAME}

# Build and tag the Docker image
REGISTRY_URL=$(az acr show --name ${REGISTRY_NAME} --query loginServer --output tsv)
FULL_IMAGE_NAME="${REGISTRY_URL}/${IMAGE_NAME}:latest"
echo -e "${YELLOW}Building Docker image: ${FULL_IMAGE_NAME}...${NC}"
docker build -t ${FULL_IMAGE_NAME} .

# Push the image to Azure Container Registry
echo -e "${YELLOW}Pushing image to Azure Container Registry...${NC}"
docker push ${FULL_IMAGE_NAME}

# Create service principal for ACI to pull from ACR
echo -e "${YELLOW}Creating service principal for ACI...${NC}"
ACR_ID=$(az acr show --name ${REGISTRY_NAME} --query id --output tsv)
SP_PASSWORD=$(az ad sp create-for-rbac --name "openhands-sp" --scopes ${ACR_ID} --role acrpull --query password --output tsv)
SP_APP_ID=$(az ad sp list --display-name "openhands-sp" --query "[].appId" --output tsv)

# Deploy to Azure Container Instances
echo -e "${YELLOW}Deploying to Azure Container Instances...${NC}"
az container create \
    --resource-group ${RESOURCE_GROUP} \
    --name ${CONTAINER_NAME} \
    --image ${FULL_IMAGE_NAME} \
    --registry-login-server ${REGISTRY_URL} \
    --registry-username ${SP_APP_ID} \
    --registry-password ${SP_PASSWORD} \
    --dns-name-label ${DNS_NAME_LABEL} \
    --ports 3000 \
    --cpu ${CPU} \
    --memory ${MEMORY} \
    --environment-variables BACKEND_HOST=0.0.0.0 BACKEND_PORT=3000

# Get the FQDN
FQDN=$(az container show --resource-group ${RESOURCE_GROUP} --name ${CONTAINER_NAME} --query ipAddress.fqdn --output tsv)

echo -e "${GREEN}Deployment completed successfully!${NC}"
echo -e "Your application is available at: ${GREEN}http://${FQDN}:3000${NC}"