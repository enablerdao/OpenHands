# OpenHands Deployment Scripts

This directory contains scripts for deploying OpenHands to various platforms and services.

## Available Deployment Scripts

- **AWS (Elastic Beanstalk)**: `deploy_aws.sh`
- **Google Cloud Platform (Cloud Run)**: `deploy_gcp.sh`
- **Microsoft Azure (Container Instances)**: `deploy_azure.sh`
- **Heroku**: `deploy_heroku.sh`
- **DigitalOcean (App Platform)**: `deploy_digitalocean.sh`
- **Local Docker**: `deploy_local_docker.sh`
- **Test Without API Keys**: `test_without_api_keys.sh`

## Prerequisites

Before using these deployment scripts, ensure you have the following installed:

- Docker
- Git
- Python 3.12+
- Node.js 22+
- Poetry
- Platform-specific CLI tools (e.g., AWS CLI, gcloud, az, heroku, doctl)

## Usage

1. Make sure you have built the application first:
   ```bash
   cd /path/to/OpenHands
   make build
   ```

2. Run the deployment script for your target platform:
   ```bash
   cd /path/to/OpenHands
   ./deploy/deploy_aws.sh  # Replace with your target platform
   ```

3. Follow the prompts and instructions provided by the script.

## Testing Without API Keys

To test OpenHands without requiring any LLM API keys:

```bash
cd /path/to/OpenHands
./deploy/test_without_api_keys.sh
```

This will start a mock LLM server locally that responds with placeholder responses, allowing you to test the application's functionality without needing actual API keys.

## Customization

Each deployment script contains configuration variables at the top that you can modify to suit your needs:

- App/service names
- Regions
- Instance types/sizes
- Port numbers
- etc.

Edit these variables before running the scripts to customize your deployment.

## Troubleshooting

If you encounter issues with the deployment scripts:

1. Check that you have the necessary CLI tools installed and configured
2. Verify that you have the required permissions for the target platform
3. Check the platform-specific logs for error messages
4. Ensure your application builds successfully locally before deploying

## Contributing

If you improve these deployment scripts or add support for additional platforms, please consider contributing back to the OpenHands project by submitting a pull request.