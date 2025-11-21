#!/bin/bash
#
# Alert Response Test Script
# This script tests CloudWatch alarm configurations and response mechanisms
#

set -e

# Configuration
ALARM_CONFIG_FILE=${1:-"alert-test-config.json"}
REGION=${2:-"us-east-1"}
SNS_TOPIC_ARN=${3:-""}
WAIT_TIME=${4:-60}
REPORT_FILE="alert-response-test-report.json"

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: This script requires jq. Please install it first."
    exit 1
fi

echo "Starting Alert Response Testing"
echo "=============================="

# Check if config file exists, create sample if not
if [ ! -f "$ALARM_CONFIG_FILE" ]; then
    echo "Configuration file not found. Creating sample..."
    cat > "$ALARM_CONFIG_FILE" << EOF
{
  "alarms": [
    {
      "name": "test-cpu-alarm",
      "description": "Test CPU Utilization Alarm",
      "namespace": "AWS/EC2",
      "metricName": "CPUUtilization",
      "dimensions": [
        {
          "name": "InstanceId",
          "value": "i-0123456789abcdef0"
        }
      ],
      "threshold": 80,
      "comparisonOperator": "GreaterThanThreshold",
      "evaluationPeriods": 1,
      "period": 60,
      "statistic": "Average"
    },
    {
      "name": "test-memory-alarm",
      "description": "Test Memory Alarm",
      "namespace": "AWS/EC2",
      "metricName": "MemoryUtilization",
      "dimensions": [
        {
          "name": "InstanceId",
          "value": "i-0123456789abcdef0"
        }
      ],
      "threshold": 80,
      "comparisonOperator": "GreaterThanThreshold",
      "evaluationPeriods": 2,
      "period": 60,
      "statistic": "Average"
    }
  ]
}
EOF
    echo "Sample configuration created at $ALARM_CONFIG_FILE. Please edit it and run again."
    exit 0
fi

# Initialize test ID
TEST_ID=$(date +%s)
TEST_DATETIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Load alarm configurations
ALARM_CONFIG=$(cat "$ALARM_CONFIG_FILE")
ALARM_COUNT=$(echo "$ALARM_CONFIG" | jq -r '.alarms | length')

# Initialize results arrays
RESULTS=()
TOTAL_ALARMS=0
SUCCESSFUL_TESTS=0
FAILED_TESTS=0

# Function to create a test alarm
create_test_alarm() {
    local alarm_name=$1
    local description=$2
    local namespace=$3
    local metric_name=$4
    local dimensions=$5
    local threshold=$6
    local comparison_operator=$7
    local evaluation_periods=$8
    local period=$9
    local statistic=${10}
    
    # Format dimensions for AWS CLI
    local dim_params=""
    local dim_count=$(echo "$dimensions" | jq -r '. | length')
    for (( i=0; i<$dim_count; i++ )); do
        local dim_name=$(echo "$dimensions" | jq -r --argjson idx "$i" '.[$idx].name')
        local dim_value=$(echo "$dimensions" | jq -r --argjson idx "$i" '.[$idx].value')
        dim_params+="Name=$dim_name,Value=$dim_value "
    done
    
    # Create the alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "$alarm_name-$TEST_ID" \
        --alarm-description "$description (Test ID: $TEST_ID)" \
        --namespace "$namespace" \
        --metric-name "$metric_name" \
        --dimensions $dim_params \
        --threshold "$threshold" \
        --comparison-operator "$comparison_operator" \
        --evaluation-periods "$evaluation_periods" \
        --period "$period" \
        --statistic "$statistic" \
        --region "$REGION" \
        --ok-actions "$SNS_TOPIC_ARN" \
        --alarm-actions "$SNS_TOPIC_ARN" \
        --insufficient-data-actions "$SNS_TOPIC_ARN"
        
    echo "$alarm_name-$TEST_ID"
}

# Function to check if alarm exists
check_alarm_exists() {
    local alarm_name=$1
    
    aws cloudwatch describe-alarms \
        --alarm-names "$alarm_name" \
        --region "$REGION" \
        --query "MetricAlarms[0].AlarmName" \
        --output text 2>/dev/null
}

# Function to trigger an alarm
trigger_test_alarm() {
    local alarm_name=$1
    
    aws cloudwatch set-alarm-state \
        --alarm-name "$alarm_name" \
        --state-value ALARM \
        --state-reason "DR Test Execution" \
        --region "$REGION"
}

# Function to clean up test alarm
delete_test_alarm() {
    local alarm_name=$1
    
    aws cloudwatch delete-alarms \
        --alarm-names "$alarm_name" \
        --region "$REGION"
}

# Process each alarm
echo "Testing $ALARM_COUNT alarm configurations..."
for (( i=0; i<$ALARM_COUNT; i++ )); do
    # Extract alarm configuration
    ALARM_NAME=$(echo "$ALARM_CONFIG" | jq -r --argjson idx "$i" '.alarms[$idx].name')
    DESCRIPTION=$(echo "$ALARM_CONFIG" | jq -r --argjson idx "$i" '.alarms[$idx].description')
    NAMESPACE=$(echo "$ALARM_CONFIG" | jq -r --argjson idx "$i" '.alarms[$idx].namespace')
    METRIC_NAME=$(echo "$ALARM_CONFIG" | jq -r --argjson idx "$i" '.alarms[$idx].metricName')
    DIMENSIONS=$(echo "$ALARM_CONFIG" | jq -r --argjson idx "$i" '.alarms[$idx].dimensions')
    THRESHOLD=$(echo "$ALARM_CONFIG" | jq -r --argjson idx "$i" '.alarms[$idx].threshold')
    COMPARISON_OPERATOR=$(echo "$ALARM_CONFIG" | jq -r --argjson idx "$i" '.alarms[$idx].comparisonOperator')
    EVALUATION_PERIODS=$(echo "$ALARM_CONFIG" | jq -r --argjson idx "$i" '.alarms[$idx].evaluationPeriods')
    PERIOD=$(echo "$ALARM_CONFIG" | jq -r --argjson idx "$i" '.alarms[$idx].period')
    STATISTIC=$(echo "$ALARM_CONFIG" | jq -r --argjson idx "$i" '.alarms[$idx].statistic')
    
    echo ""
    echo "Testing alarm: $ALARM_NAME"
    TOTAL_ALARMS=$((TOTAL_ALARMS + 1))
    
    # Step 1: Create test alarm
    echo "Creating test alarm..."
    TEST_ALARM_NAME=$(create_test_alarm \
        "$ALARM_NAME" \
        "$DESCRIPTION" \
        "$NAMESPACE" \
        "$METRIC_NAME" \
        "$DIMENSIONS" \
        "$THRESHOLD" \
        "$COMPARISON_OPERATOR" \
        "$EVALUATION_PERIODS" \
        "$PERIOD" \
        "$STATISTIC")
    
    # Step 2: Verify alarm was created
    echo "Verifying alarm creation..."
    ALARM_CHECK=$(check_alarm_exists "$TEST_ALARM_NAME")
    
    if [ -z "$ALARM_CHECK" ]; then
        echo "Failed to create test alarm"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        RESULTS+=("{\"alarmName\":\"$ALARM_NAME\",\"testAlarmName\":\"$TEST_ALARM_NAME\",\"status\":\"FAILED\",\"reason\":\"Failed to create alarm\"}")
        continue
    fi
    
    # Step 3: Trigger the alarm
    echo "Triggering test alarm..."
    trigger_test_alarm "$TEST_ALARM_NAME"
    
    # Step 4: Wait for notifications to be sent
    echo "Waiting $WAIT_TIME seconds for alarm processing..."
    sleep "$WAIT_TIME"
    
    # Step 5: Verify alarm state
    echo "Checking alarm state..."
    ALARM_STATE=$(aws cloudwatch describe-alarms \
        --alarm-names "$TEST_ALARM_NAME" \
        --region "$REGION" \
        --query "MetricAlarms[0].StateValue" \
        --output text)
        
    if [ "$ALARM_STATE" = "ALARM" ]; then
        echo "Alarm test successful"
        STATUS="SUCCESS"
        SUCCESSFUL_TESTS=$((SUCCESSFUL_TESTS + 1))
    else
        echo "Alarm test failed. State: $ALARM_STATE"
        STATUS="FAILED"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    
    # Add to results
    RESULTS+=("{\"alarmName\":\"$ALARM_NAME\",\"testAlarmName\":\"$TEST_ALARM_NAME\",\"status\":\"$STATUS\",\"alarmState\":\"$ALARM_STATE\"}")
    
    # Step 6: Clean up
    echo "Cleaning up test alarm..."
    delete_test_alarm "$TEST_ALARM_NAME"
done

# Calculate success rate
if [ "$TOTAL_ALARMS" -gt 0 ]; then
    SUCCESS_RATE=$(awk "BEGIN {printf \"%.1f\", ($SUCCESSFUL_TESTS * 100 / $TOTAL_ALARMS)}")
else
    SUCCESS_RATE="0.0"
fi

# Generate JSON report
echo ""
echo "Generating test report..."

# Join results array for JSON
JSON_RESULTS=$(printf '%s,' "${RESULTS[@]}" | sed 's/,$//')

# Create JSON report
cat > "$REPORT_FILE" << EOF
{
  "testName": "Alert Response Test",
  "testId": "$TEST_ID",
  "timestamp": "$TEST_DATETIME",
  "region": "$REGION",
  "snsTopicArn": "$SNS_TOPIC_ARN",
  "waitTimeSeconds": $WAIT_TIME,
  "summary": {
    "totalAlarms": $TOTAL_ALARMS,
    "successfulTests": $SUCCESSFUL_TESTS,
    "failedTests": $FAILED_TESTS,
    "successRatePercent": $SUCCESS_RATE
  },
  "results": [$JSON_RESULTS]
}
EOF

# Print summary
echo ""
echo "Alert Response Test Summary:"
echo "==========================="
echo "Total alarms tested: $TOTAL_ALARMS"
echo "Successful tests: $SUCCESSFUL_TESTS"
echo "Failed tests: $FAILED_TESTS"
echo "Success rate: $SUCCESS_RATE%"
echo ""
echo "Detailed report saved to: $REPORT_FILE"