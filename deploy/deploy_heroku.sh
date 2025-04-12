#!/bin/bash
# Heroku Deployment Script for OpenHands
# This script deploys OpenHands to Heroku

set -e

# Configuration
APP_NAME="openhands"  # Your Heroku app name

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if Heroku CLI is installed
if ! command -v heroku &> /dev/null; then
    echo -e "${RED}Heroku CLI is not installed. Please install it first.${NC}"
    echo "Visit: https://devcenter.heroku.com/articles/heroku-cli"
    exit 1
fi

# Check if Git is installed
if ! command -v git &> /dev/null; then
    echo -e "${RED}Git is not installed. Please install it first.${NC}"
    exit 1
fi

# Check if logged in to Heroku
if ! heroku auth:whoami &> /dev/null; then
    echo -e "${YELLOW}Not logged in to Heroku. Logging in...${NC}"
    heroku login
fi

# Build the application
echo -e "${YELLOW}Building the application...${NC}"
cd "$(dirname "$0")/.."
make build

# Create Heroku app if it doesn't exist
if ! heroku apps:info --app ${APP_NAME} &> /dev/null; then
    echo -e "${YELLOW}Creating Heroku app: ${APP_NAME}...${NC}"
    heroku apps:create ${APP_NAME}
else
    echo -e "${YELLOW}Using existing Heroku app: ${APP_NAME}...${NC}"
fi

# Create Procfile for Heroku
echo -e "${YELLOW}Creating Procfile...${NC}"
cat > Procfile << EOF
web: poetry run uvicorn openhands.server.listen:app --host 0.0.0.0 --port \$PORT
EOF

# Create runtime.txt for Heroku
echo -e "${YELLOW}Creating runtime.txt...${NC}"
echo "python-3.12.0" > runtime.txt

# Create app.json for Heroku
echo -e "${YELLOW}Creating app.json...${NC}"
cat > app.json << EOF
{
  "name": "OpenHands",
  "description": "OpenHands: Code Less, Make More",
  "repository": "https://github.com/enablerdao/OpenHands",
  "keywords": ["python", "fastapi", "react", "ai"],
  "buildpacks": [
    {
      "url": "heroku/python"
    },
    {
      "url": "heroku/nodejs"
    }
  ],
  "env": {
    "BACKEND_HOST": {
      "description": "Backend host",
      "value": "0.0.0.0"
    }
  }
}
EOF

# Set up Heroku Git remote if not already set
if ! git remote | grep -q heroku; then
    echo -e "${YELLOW}Setting up Heroku Git remote...${NC}"
    heroku git:remote --app ${APP_NAME}
fi

# Set Heroku buildpacks
echo -e "${YELLOW}Setting Heroku buildpacks...${NC}"
heroku buildpacks:clear --app ${APP_NAME}
heroku buildpacks:add heroku/python --app ${APP_NAME}
heroku buildpacks:add heroku/nodejs --app ${APP_NAME}

# Deploy to Heroku
echo -e "${YELLOW}Deploying to Heroku...${NC}"
git add .
git commit -m "Prepare for Heroku deployment" || true
git push heroku main

# Scale the dyno
echo -e "${YELLOW}Scaling the dyno...${NC}"
heroku ps:scale web=1 --app ${APP_NAME}

# Get the app URL
APP_URL=$(heroku apps:info --app ${APP_NAME} | grep "Web URL" | awk '{print $3}')

echo -e "${GREEN}Deployment completed successfully!${NC}"
echo -e "Your application is available at: ${GREEN}${APP_URL}${NC}"