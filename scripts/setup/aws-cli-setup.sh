#!/bin/bash

# AWS CLI Setup Script for DR Testing Environment
# This script installs and configures AWS CLI for DR testing

set -e

# Function to display usage
usage() {
  echo "Usage: $0 [OPTIONS]"
  echo "Options:"
  echo "  --profile NAME       AWS profile name (default: dr-testing)"
  echo "  --region REGION      AWS region (default: us-east-1)"
  echo "  --mfa-serial ARN     MFA device ARN for authentication"
  echo "  --help               Display this help message"
  exit 1
}

# Default values
PROFILE="dr-testing"
REGION="us-east-1"
MFA_SERIAL=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --profile)
      PROFILE="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    --mfa-serial)
      MFA_SERIAL="$2"
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

echo "Setting up AWS CLI for DR testing..."
echo "OS detected: $OS"

# Install AWS CLI if not present
if ! command -v aws &> /dev/null; then
  echo "AWS CLI not found, installing..."
  
  if [[ "$OS" == "linux" ]]; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
    rm -rf aws/ awscliv2.zip
  elif [[ "$OS" == "macos" ]]; then
    curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
    sudo installer -pkg AWSCLIV2.pkg -target /
    rm AWSCLIV2.pkg
  elif [[ "$OS" == "windows" ]]; then
    echo "Please manually install AWS CLI from: https://awscli.amazonaws.com/AWSCLIV2.msi"
    echo "After installation, restart this script."
    exit 1
  fi
else
  echo "AWS CLI already installed"
  aws --version
fi

# Configure AWS CLI
echo "Configuring AWS CLI profile: $PROFILE"
aws configure set region "$REGION" --profile "$PROFILE"
aws configure set output json --profile "$PROFILE"

# Ask for credentials if not using SSO
echo "Setting up AWS credentials for profile $PROFILE"
echo "Enter your AWS Access Key ID:"
read -r AWS_ACCESS_KEY_ID
echo "Enter your AWS Secret Access Key:"
read -r -s AWS_SECRET_ACCESS_KEY

aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID" --profile "$PROFILE"
aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY" --profile "$PROFILE"

# Configure MFA if provided
if [[ -n "$MFA_SERIAL" ]]; then
  echo "MFA serial ARN provided: $MFA_SERIAL"
  aws configure set mfa_serial "$MFA_SERIAL" --profile "$PROFILE"
  
  echo "To use MFA with this profile, run:"
  echo "aws sts get-session-token --serial-number $MFA_SERIAL --token-code XXXXXX --profile $PROFILE"
fi

# Validate configuration
echo "Validating AWS CLI configuration..."
if aws sts get-caller-identity --profile "$PROFILE" &> /dev/null; then
  echo "AWS CLI configuration successful!"
  aws sts get-caller-identity --profile "$PROFILE"
else
  echo "AWS CLI configuration validation failed. Please check your credentials."
  exit 1
fi

echo "Creating named profiles for DR testing..."
# Create profiles for primary and DR regions
PRIMARY_REGION="$REGION"
DR_REGION="us-west-2"  # Default DR region, can be changed

# Create primary profile
aws configure set region "$PRIMARY_REGION" --profile "${PROFILE}-primary"
aws configure set source_profile "$PROFILE" --profile "${PROFILE}-primary"

# Create DR profile
aws configure set region "$DR_REGION" --profile "${PROFILE}-dr"
aws configure set source_profile "$PROFILE" --profile "${PROFILE}-dr"

echo "AWS CLI setup complete!"
echo "Primary profile: ${PROFILE}-primary (region: $PRIMARY_REGION)"
echo "DR profile: ${PROFILE}-dr (region: $DR_REGION)"
echo ""
echo "To test connectivity:"
echo "aws sts get-caller-identity --profile ${PROFILE}-primary"
echo "aws sts get-caller-identity --profile ${PROFILE}-dr"