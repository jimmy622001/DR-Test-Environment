#!/bin/bash

# InSpec Setup Script for DR Testing Environment
# This script installs and configures InSpec for AWS testing

set -e

# Function to display usage
usage() {
  echo "Usage: $0 [OPTIONS]"
  echo "Options:"
  echo "  --aws-profile NAME   AWS profile to use (default: dr-testing)"
  echo "  --help               Display this help message"
  exit 1
}

# Default values
AWS_PROFILE="dr-testing"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --aws-profile)
      AWS_PROFILE="$2"
      shift 2
      ;;
    --help)
      usage
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

# Detect OS
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  OS="linux"
elif [[ "$OSTYPE" == "darwin"* ]]; then
  OS="macos"
elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
  OS="windows"
else
  echo "Unsupported OS: $OSTYPE"
  exit 1
fi

echo "Setting up InSpec for AWS DR testing..."
echo "OS detected: $OS"

# Install InSpec if not present
if ! command -v inspec &> /dev/null; then
  echo "InSpec not found, installing..."
  
  if [[ "$OS" == "linux" ]]; then
    curl https://omnitruck.chef.io/install.sh | sudo bash -s -- -P inspec
  elif [[ "$OS" == "macos" ]]; then
    curl https://omnitruck.chef.io/install.sh | sudo bash -s -- -P inspec
  elif [[ "$OS" == "windows" ]]; then
    echo "Please manually install InSpec from: https://downloads.chef.io/tools/inspec"
    echo "After installation, restart this script."
    exit 1
  fi
else
  echo "InSpec already installed"
  inspec version
fi

# Install AWS InSpec resource pack
echo "Installing AWS InSpec resource pack..."
inspec plugin install inspec-aws

# Verify AWS credentials
echo "Verifying AWS credentials..."
if ! aws sts get-caller-identity --profile "$AWS_PROFILE" &> /dev/null; then
  echo "AWS CLI not configured correctly. Please run aws-cli-setup.sh first"
  exit 1
fi

# Create InSpec AWS configuration
echo "Creating InSpec AWS configuration..."
mkdir -p ~/.inspec/plugins.json.d

cat > ~/.inspec/plugins.json.d/aws.json << EOF
{
  "aws_profile": {
    "primary": "${AWS_PROFILE}-primary",
    "dr": "${AWS_PROFILE}-dr"
  }
}
EOF

# Set up InSpec inputs for AWS testing
echo "Setting up InSpec inputs for AWS testing..."
mkdir -p inspec/inputs

# Create sample inputs file
cat > inspec/inputs/aws-dr.yml << EOF
# AWS DR Test Inputs
vpc_id: 'vpc-12345'  # Replace with your actual VPC ID
environment: 'dr'
rds_db_instance_identifier: 'dr-database'  # Replace with your actual DB identifier
primary_account_id: '123456789012'  # Replace with your primary account ID
failover_region: 'us-west-2'  # Replace with your actual failover region
rpo_threshold_minutes: 15
rto_threshold_minutes: 30

# Add your specific AWS resource IDs and configuration values below
# security_group_ids:
#   - sg-12345
#   - sg-67890
EOF

# Verify InSpec AWS connection
echo "Verifying InSpec AWS connection..."
inspec detect -t aws://

# Display next steps
echo "InSpec setup complete!"
echo ""
echo "To run InSpec tests against AWS:"
echo "inspec exec inspec/profiles/dev -t aws://${AWS_PROFILE}-primary"
echo "inspec exec inspec/profiles/dr -t aws://${AWS_PROFILE}-dr"
echo ""
echo "To modify AWS resource IDs for testing:"
echo "Edit inspec/inputs/aws-dr.yml with your actual AWS resource IDs"