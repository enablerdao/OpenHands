#!/bin/bash
# AWS Deployment Script for OpenHands
# This script deploys OpenHands to AWS using Elastic Beanstalk

set -e

# Configuration
APP_NAME="openhands"
ENV_NAME="production"
REGION="us-west-2"  # Change to your preferred region
PLATFORM="Docker"
INSTANCE_TYPE="t3.medium"  # Change based on your needs

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}AWS CLI is not installed. Please install it first.${NC}"
    echo "Visit: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    exit 1
fi

# Check if AWS CLI is configured
if ! aws configure list &> /dev/null; then
    echo -e "${RED}AWS CLI is not configured. Please run 'aws configure' first.${NC}"
    exit 1
fi

# Check if EB CLI is installed
if ! command -v eb &> /dev/null; then
    echo -e "${YELLOW}Elastic Beanstalk CLI is not installed. Installing...${NC}"
    pip install awsebcli
fi

# Build the application
echo -e "${YELLOW}Building the application...${NC}"
cd "$(dirname "$0")/.."
make build

# Create Dockerrun.aws.json for Elastic Beanstalk
cat > Dockerrun.aws.json << EOF
{
  "AWSEBDockerrunVersion": "1",
  "Image": {
    "Name": "${APP_NAME}:latest",
    "Update": "true"
  },
  "Ports": [
    {
      "ContainerPort": 3000,
      "HostPort": 80
    }
  ],
  "Logging": "/var/log/openhands"
}
EOF

# Initialize Elastic Beanstalk if not already initialized
if [ ! -d .elasticbeanstalk ]; then
    echo -e "${YELLOW}Initializing Elastic Beanstalk...${NC}"
    eb init ${APP_NAME} --region ${REGION} --platform ${PLATFORM}
fi

# Check if environment exists
if ! eb status ${ENV_NAME} &> /dev/null; then
    echo -e "${YELLOW}Creating Elastic Beanstalk environment...${NC}"
    eb create ${ENV_NAME} --instance_type ${INSTANCE_TYPE} --single
else
    echo -e "${YELLOW}Deploying to existing environment...${NC}"
    eb deploy ${ENV_NAME}
fi

# Get the environment URL
ENV_URL=$(eb status ${ENV_NAME} | grep CNAME | awk '{print $2}')

echo -e "${GREEN}Deployment completed successfully!${NC}"
echo -e "Your application is available at: ${GREEN}http://${ENV_URL}${NC}"