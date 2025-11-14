#!/bin/bash

# FIS Experiment Execution Script
# This script runs AWS Fault Injection Simulator experiments for DR testing

set -e

# Function to display usage
usage() {
  echo "Usage: $0 [OPTIONS]"
  echo "Options:"
  echo "  --experiment FILE    JSON experiment template file (required)"
  echo "  --aws-profile NAME   AWS profile to use (default: dr-testing)"
  echo "  --region REGION      AWS region (default: us-east-1)"
  echo "  --duration SECONDS   Override experiment duration in seconds"
  echo "  --dry-run            Validate but don't run the experiment"
  echo "  --help               Display this help message"
  exit 1
}

# Default values
AWS_PROFILE="dr-testing"
REGION="us-east-1"
EXPERIMENT_FILE=""
DURATION=""
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --experiment)
      EXPERIMENT_FILE="$2"
      shift 2
      ;;
    --aws-profile)
      AWS_PROFILE="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    --duration)
      DURATION="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
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

# Check required parameters
if [[ -z "$EXPERIMENT_FILE" ]]; then
  echo "ERROR: Experiment file must be specified"
  usage
fi

if [[ ! -f "$EXPERIMENT_FILE" ]]; then
  echo "ERROR: Experiment file not found: $EXPERIMENT_FILE"
  exit 1
fi

echo "====== AWS FIS Experiment Runner ======"
echo "Experiment file: $EXPERIMENT_FILE"
echo "AWS Profile: $AWS_PROFILE"
echo "Region: $REGION"
echo "Dry run: $DRY_RUN"

# Read and modify experiment template
TEMP_FILE=$(mktemp)
cp "$EXPERIMENT_FILE" "$TEMP_FILE"

# Override duration if specified
if [[ -n "$DURATION" ]]; then
  echo "Overriding duration to $DURATION seconds"
  if grep -q "durationSeconds" "$TEMP_FILE"; then
    # For EC2 stress actions
    sed -i "s/\"durationSeconds\": \"[0-9]*\"/\"durationSeconds\": \"$DURATION\"/" "$TEMP_FILE"
  elif grep -q "duration" "$TEMP_FILE"; then
    # For network actions (using ISO8601 duration format)
    sed -i "s/\"duration\": \"PT[0-9]*M\"/\"duration\": \"PT${DURATION}S\"/" "$TEMP_FILE"
  fi
fi

# Update account ID in role ARN if it's the placeholder value
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query "Account" --output text)
sed -i "s/arn:aws:iam::123456789012:role/arn:aws:iam::$ACCOUNT_ID:role/" "$TEMP_FILE"

# Generate a unique experiment template ID
EXPERIMENT_TEMPLATE_ID="dr-test-$(date +%Y%m%d-%H%M%S)"

echo "Creating experiment template: $EXPERIMENT_TEMPLATE_ID"
TEMPLATE_ARN=$(aws fis create-experiment-template \
  --cli-input-json "file://$TEMP_FILE" \
  --profile "$AWS_PROFILE" \
  --region "$REGION" \
  --query "experimentTemplate.id" \
  --output text)

echo "Experiment template created: $TEMPLATE_ARN"

if [[ "$DRY_RUN" == true ]]; then
  echo "Dry run mode, skipping execution"
  exit 0
fi

# Ask for confirmation before starting experiment
echo ""
echo "CAUTION: This will inject faults into your AWS environment!"
echo "Review the experiment configuration at: https://$REGION.console.aws.amazon.com/fis/home?region=$REGION#ExperimentTemplates"
echo ""
read -p "Do you want to proceed with the experiment? (yes/no): " CONFIRMATION

if [[ "$CONFIRMATION" != "yes" ]]; then
  echo "Experiment cancelled. Template remains for review."
  exit 0
fi

# Start the experiment
echo "Starting FIS experiment..."
EXPERIMENT_ID=$(aws fis start-experiment \
  --experiment-template-id "$TEMPLATE_ARN" \
  --profile "$AWS_PROFILE" \
  --region "$REGION" \
  --query "experiment.id" \
  --output text)

echo "Experiment started with ID: $EXPERIMENT_ID"
echo "Monitor at: https://$REGION.console.aws.amazon.com/fis/home?region=$REGION#Experiments"

# Monitor experiment progress
echo "Monitoring experiment progress..."
while true; do
  EXPERIMENT_STATUS=$(aws fis get-experiment \
    --id "$EXPERIMENT_ID" \
    --profile "$AWS_PROFILE" \
    --region "$REGION" \
    --query "experiment.state" \
    --output text)
  
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Experiment status: $EXPERIMENT_STATUS"
  
  if [[ "$EXPERIMENT_STATUS" == "completed" || "$EXPERIMENT_STATUS" == "failed" || "$EXPERIMENT_STATUS" == "stopped" ]]; then
    break
  fi
  
  sleep 10
done

# Get detailed experiment results
echo "Experiment completed with status: $EXPERIMENT_STATUS"
aws fis get-experiment \
  --id "$EXPERIMENT_ID" \
  --profile "$AWS_PROFILE" \
  --region "$REGION" \
  --output json > "experiment-result-$EXPERIMENT_ID.json"

echo "Full experiment results saved to: experiment-result-$EXPERIMENT_ID.json"

# Cleanup temporary file
rm "$TEMP_FILE"

# If experiment failed, exit with error code
if [[ "$EXPERIMENT_STATUS" == "failed" ]]; then
  echo "Experiment failed! Check results for details."
  exit 1
fi

echo "Experiment completed successfully!"