#!/bin/bash

# Alert Setup Script for DR Testing
# This script creates CloudWatch alarms for DR testing scenarios

set -e

# Function to display usage
usage() {
  echo "Usage: $0 [OPTIONS]"
  echo "Options:"
  echo "  --env NAME           Environment name (required)"
  echo "  --aws-profile NAME   AWS profile to use (default: dr-testing)"
  echo "  --region REGION      AWS region (default: us-east-1)"
  echo "  --sns-topic ARN      SNS topic ARN for notifications (required)"
  echo "  --config FILE        JSON config file for custom thresholds"
  echo "  --help               Display this help message"
  exit 1
}

# Default values
AWS_PROFILE="dr-testing"
REGION="us-east-1"
ENV_NAME=""
SNS_TOPIC=""
CONFIG_FILE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --env)
      ENV_NAME="$2"
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
    --sns-topic)
      SNS_TOPIC="$2"
      shift 2
      ;;
    --config)
      CONFIG_FILE="$2"
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

# Check required parameters
if [[ -z "$ENV_NAME" ]]; then
  echo "ERROR: Environment name must be specified"
  usage
fi

if [[ -z "$SNS_TOPIC" ]]; then
  echo "ERROR: SNS topic ARN must be specified"
  usage
fi

echo "====== Setting up DR Test Alerts ======"
echo "Environment: $ENV_NAME"
echo "AWS Profile: $AWS_PROFILE"
echo "Region: $REGION"
echo "SNS Topic: $SNS_TOPIC"

# Check if config file exists
if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
  echo "Using custom config: $CONFIG_FILE"
  # Read configuration values from JSON file
  # Example for parsing with jq (if available)
  if command -v jq &> /dev/null; then
    CPU_THRESHOLD=$(jq -r '.cpuThreshold // "80"' "$CONFIG_FILE")
    MEM_THRESHOLD=$(jq -r '.memThreshold // "85"' "$CONFIG_FILE")
    DISK_THRESHOLD=$(jq -r '.diskThreshold // "85"' "$CONFIG_FILE")
    RTO_THRESHOLD=$(jq -r '.rtoThresholdSeconds // "300"' "$CONFIG_FILE")
    RPO_THRESHOLD=$(jq -r '.rpoThresholdSeconds // "900"' "$CONFIG_FILE")
  else
    echo "WARNING: jq not found, using default thresholds"
    CPU_THRESHOLD="80"
    MEM_THRESHOLD="85"
    DISK_THRESHOLD="85"
    RTO_THRESHOLD="300"
    RPO_THRESHOLD="900"
  fi
else
  echo "Using default thresholds"
  # Default configuration values
  CPU_THRESHOLD="80"
  MEM_THRESHOLD="85"
  DISK_THRESHOLD="85"
  RTO_THRESHOLD="300"
  RPO_THRESHOLD="900"
fi

echo "Thresholds:"
echo "- CPU: $CPU_THRESHOLD%"
echo "- Memory: $MEM_THRESHOLD%"
echo "- Disk: $DISK_THRESHOLD%"
echo "- RTO: $RTO_THRESHOLD seconds"
echo "- RPO: $RPO_THRESHOLD seconds"

# Get resources with environment tag
echo "Finding resources in $ENV_NAME environment..."

# Find EC2 instances
EC2_INSTANCES=$(aws ec2 describe-instances \
  --filters "Name=tag:Environment,Values=$ENV_NAME" "Name=instance-state-name,Values=running" \
  --query "Reservations[*].Instances[*].InstanceId" \
  --output text \
  --profile "$AWS_PROFILE" \
  --region "$REGION")

echo "Found EC2 instances: $EC2_INSTANCES"

# Find RDS instances
RDS_INSTANCES=$(aws rds describe-db-instances \
  --query "DBInstances[*].DBInstanceIdentifier" \
  --output text \
  --profile "$AWS_PROFILE" \
  --region "$REGION")

# Filter RDS instances by tag (more complex as it requires separate API calls)
if [[ -n "$RDS_INSTANCES" ]]; then
  FILTERED_RDS_INSTANCES=""
  for DB_ID in $RDS_INSTANCES; do
    HAS_TAG=$(aws rds list-tags-for-resource \
      --resource-name "arn:aws:rds:$REGION:$(aws sts get-caller-identity --query Account --output text --profile "$AWS_PROFILE"):db:$DB_ID" \
      --query "TagList[?Key=='Environment' && Value=='$ENV_NAME'] | length(@)" \
      --output text \
      --profile "$AWS_PROFILE" \
      --region "$REGION")
    
    if [[ "$HAS_TAG" -gt 0 ]]; then
      if [[ -z "$FILTERED_RDS_INSTANCES" ]]; then
        FILTERED_RDS_INSTANCES="$DB_ID"
      else
        FILTERED_RDS_INSTANCES="$FILTERED_RDS_INSTANCES $DB_ID"
      fi
    fi
  done
  
  RDS_INSTANCES="$FILTERED_RDS_INSTANCES"
  echo "Found RDS instances: $RDS_INSTANCES"
fi

# Create a unique namespace for DR test metrics
NAMESPACE="DRTest"

# Create alarms for EC2 instances
if [[ -n "$EC2_INSTANCES" ]]; then
  echo "Creating EC2 alarms..."
  
  for INSTANCE in $EC2_INSTANCES; do
    # CPU alarm
    aws cloudwatch put-metric-alarm \
      --alarm-name "DR-Test-CPU-$ENV_NAME-$INSTANCE" \
      --alarm-description "DR Test - High CPU usage for $INSTANCE" \
      --metric-name CPUUtilization \
      --namespace AWS/EC2 \
      --dimensions "Name=InstanceId,Value=$INSTANCE" \
      --statistic Average \
      --period 60 \
      --evaluation-periods 2 \
      --threshold $CPU_THRESHOLD \
      --comparison-operator GreaterThanThreshold \
      --alarm-actions "$SNS_TOPIC" \
      --profile "$AWS_PROFILE" \
      --region "$REGION"
    
    echo "Created CPU alarm for $INSTANCE"
    
    # Status check alarm
    aws cloudwatch put-metric-alarm \
      --alarm-name "DR-Test-StatusCheck-$ENV_NAME-$INSTANCE" \
      --alarm-description "DR Test - Status check failure for $INSTANCE" \
      --metric-name StatusCheckFailed \
      --namespace AWS/EC2 \
      --dimensions "Name=InstanceId,Value=$INSTANCE" \
      --statistic Maximum \
      --period 60 \
      --evaluation-periods 2 \
      --threshold 1 \
      --comparison-operator GreaterThanOrEqualToThreshold \
      --alarm-actions "$SNS_TOPIC" \
      --profile "$AWS_PROFILE" \
      --region "$REGION"
    
    echo "Created status check alarm for $INSTANCE"
    
    # If CloudWatch agent is installed, add memory and disk alarms
    # This assumes CloudWatch agent is configured to publish these metrics
    HAS_CW_AGENT=$(aws ssm describe-instance-information \
      --filters "Key=InstanceIds,Values=$INSTANCE" \
      --query "InstanceInformationList[*].PingStatus" \
      --output text \
      --profile "$AWS_PROFILE" \
      --region "$REGION" 2>/dev/null || echo "")
    
    if [[ "$HAS_CW_AGENT" == "Online" ]]; then
      # Memory alarm
      aws cloudwatch put-metric-alarm \
        --alarm-name "DR-Test-Memory-$ENV_NAME-$INSTANCE" \
        --alarm-description "DR Test - High memory usage for $INSTANCE" \
        --metric-name mem_used_percent \
        --namespace CWAgent \
        --dimensions "Name=InstanceId,Value=$INSTANCE" \
        --statistic Average \
        --period 60 \
        --evaluation-periods 2 \
        --threshold $MEM_THRESHOLD \
        --comparison-operator GreaterThanThreshold \
        --alarm-actions "$SNS_TOPIC" \
        --profile "$AWS_PROFILE" \
        --region "$REGION"
      
      echo "Created memory alarm for $INSTANCE"
      
      # Disk alarm
      aws cloudwatch put-metric-alarm \
        --alarm-name "DR-Test-Disk-$ENV_NAME-$INSTANCE" \
        --alarm-description "DR Test - High disk usage for $INSTANCE" \
        --metric-name disk_used_percent \
        --namespace CWAgent \
        --dimensions "Name=InstanceId,Value=$INSTANCE" "Name=path,Value=/" "Name=device,Value=xvda1" "Name=fstype,Value=xfs" \
        --statistic Average \
        --period 60 \
        --evaluation-periods 2 \
        --threshold $DISK_THRESHOLD \
        --comparison-operator GreaterThanThreshold \
        --alarm-actions "$SNS_TOPIC" \
        --profile "$AWS_PROFILE" \
        --region "$REGION"
      
      echo "Created disk alarm for $INSTANCE"
    fi
  done
fi

# Create alarms for RDS instances
if [[ -n "$RDS_INSTANCES" ]]; then
  echo "Creating RDS alarms..."
  
  for DB_INSTANCE in $RDS_INSTANCES; do
    # CPU alarm
    aws cloudwatch put-metric-alarm \
      --alarm-name "DR-Test-CPU-$ENV_NAME-$DB_INSTANCE" \
      --alarm-description "DR Test - High CPU usage for $DB_INSTANCE" \
      --metric-name CPUUtilization \
      --namespace AWS/RDS \
      --dimensions "Name=DBInstanceIdentifier,Value=$DB_INSTANCE" \
      --statistic Average \
      --period 60 \
      --evaluation-periods 2 \
      --threshold $CPU_THRESHOLD \
      --comparison-operator GreaterThanThreshold \
      --alarm-actions "$SNS_TOPIC" \
      --profile "$AWS_PROFILE" \
      --region "$REGION"
    
    echo "Created CPU alarm for $DB_INSTANCE"
    
    # Free storage space alarm
    aws cloudwatch put-metric-alarm \
      --alarm-name "DR-Test-Storage-$ENV_NAME-$DB_INSTANCE" \
      --alarm-description "DR Test - Low free storage for $DB_INSTANCE" \
      --metric-name FreeStorageSpace \
      --namespace AWS/RDS \
      --dimensions "Name=DBInstanceIdentifier,Value=$DB_INSTANCE" \
      --statistic Average \
      --period 60 \
      --evaluation-periods 2 \
      --threshold 10737418240 \
      --comparison-operator LessThanThreshold \
      --alarm-actions "$SNS_TOPIC" \
      --profile "$AWS_PROFILE" \
      --region "$REGION"
    
    echo "Created storage alarm for $DB_INSTANCE"
    
    # Connection count alarm - dynamic based on instance class
    DB_CLASS=$(aws rds describe-db-instances \
      --db-instance-identifier "$DB_INSTANCE" \
      --query "DBInstances[0].DBInstanceClass" \
      --output text \
      --profile "$AWS_PROFILE" \
      --region "$REGION")
    
    # Set connection threshold based on instance class
    # This is a simplified example - adjust for your specific needs
    CONN_THRESHOLD=100
    if [[ "$DB_CLASS" == *".large"* ]]; then
      CONN_THRESHOLD=200
    elif [[ "$DB_CLASS" == *".xlarge"* ]]; then
      CONN_THRESHOLD=500
    elif [[ "$DB_CLASS" == *".2xlarge"* ]]; then
      CONN_THRESHOLD=1000
    elif [[ "$DB_CLASS" == *".4xlarge"* || "$DB_CLASS" == *".8xlarge"* ]]; then
      CONN_THRESHOLD=2000
    fi
    
    aws cloudwatch put-metric-alarm \
      --alarm-name "DR-Test-Connections-$ENV_NAME-$DB_INSTANCE" \
      --alarm-description "DR Test - High connection count for $DB_INSTANCE" \
      --metric-name DatabaseConnections \
      --namespace AWS/RDS \
      --dimensions "Name=DBInstanceIdentifier,Value=$DB_INSTANCE" \
      --statistic Average \
      --period 60 \
      --evaluation-periods 2 \
      --threshold $CONN_THRESHOLD \
      --comparison-operator GreaterThanThreshold \
      --alarm-actions "$SNS_TOPIC" \
      --profile "$AWS_PROFILE" \
      --region "$REGION"
    
    echo "Created connection alarm for $DB_INSTANCE (threshold: $CONN_THRESHOLD)"
  done
fi

# Create DR-specific composite alarms
echo "Creating DR test specific alarms..."

# RTO alarm - custom metric
aws cloudwatch put-metric-alarm \
  --alarm-name "DR-Test-RTO-$ENV_NAME" \
  --alarm-description "DR Test - Recovery Time Objective exceeded" \
  --metric-name RecoveryTime \
  --namespace $NAMESPACE \
  --dimensions "Name=TestId,Value=latest" \
  --statistic Maximum \
  --period 60 \
  --evaluation-periods 1 \
  --threshold $RTO_THRESHOLD \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions "$SNS_TOPIC" \
  --profile "$AWS_PROFILE" \
  --region "$REGION"

echo "Created RTO alarm (threshold: $RTO_THRESHOLD seconds)"

# RPO alarm - custom metric
aws cloudwatch put-metric-alarm \
  --alarm-name "DR-Test-RPO-$ENV_NAME" \
  --alarm-description "DR Test - Recovery Point Objective exceeded" \
  --metric-name DataLoss \
  --namespace $NAMESPACE \
  --dimensions "Name=TestId,Value=latest" \
  --statistic Maximum \
  --period 60 \
  --evaluation-periods 1 \
  --threshold $RPO_THRESHOLD \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions "$SNS_TOPIC" \
  --profile "$AWS_PROFILE" \
  --region "$REGION"

echo "Created RPO alarm (threshold: $RPO_THRESHOLD seconds)"

# Test Success Rate alarm - custom metric
aws cloudwatch put-metric-alarm \
  --alarm-name "DR-Test-SuccessRate-$ENV_NAME" \
  --alarm-description "DR Test - Test success rate below threshold" \
  --metric-name SuccessRate \
  --namespace $NAMESPACE \
  --dimensions "Name=TestId,Value=latest" \
  --statistic Average \
  --period 60 \
  --evaluation-periods 1 \
  --threshold 90 \
  --comparison-operator LessThanThreshold \
  --alarm-actions "$SNS_TOPIC" \
  --profile "$AWS_PROFILE" \
  --region "$REGION"

echo "Created success rate alarm (threshold: 90%)"

echo "Alert setup complete!"
echo "Configured alarms can be viewed at: https://$REGION.console.aws.amazon.com/cloudwatch/home?region=$REGION#alarmsV2:?"