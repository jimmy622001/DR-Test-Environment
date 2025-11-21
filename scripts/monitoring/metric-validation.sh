#!/bin/bash
#
# Metric Validation Script
# This script validates that CloudWatch metrics are being correctly collected
# from all required sources after a DR event.
#

set -e

# Configuration
CONFIG_FILE=${1:-"metric-sources.json"}
REGION=${2:-"us-east-1"}
LOOKBACK_MINUTES=${3:-15}
REPORT_FILE="metric-validation-report.json"

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: This script requires jq. Please install it first."
    exit 1
fi

echo "Starting CloudWatch Metric Validation"
echo "===================================="

# Check if config file exists, create sample if not
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Configuration file not found. Creating sample..."
    cat > "$CONFIG_FILE" << EOF
[
  {
    "namespace": "AWS/EC2",
    "metrics": [
      {
        "name": "CPUUtilization",
        "dimensions": [
          {
            "name": "InstanceId",
            "value": "i-0123456789abcdef0"
          }
        ],
        "statistic": "Average",
        "period": 300
      }
    ]
  },
  {
    "namespace": "AWS/RDS",
    "metrics": [
      {
        "name": "CPUUtilization",
        "dimensions": [
          {
            "name": "DBInstanceIdentifier",
            "value": "database-1"
          }
        ],
        "statistic": "Average",
        "period": 300
      },
      {
        "name": "FreeableMemory",
        "dimensions": [
          {
            "name": "DBInstanceIdentifier",
            "value": "database-1"
          }
        ],
        "statistic": "Average",
        "period": 300
      }
    ]
  }
]
EOF
    echo "Sample configuration created at $CONFIG_FILE. Please edit it and run again."
    exit 0
fi

# Load configuration
METRICS_CONFIG=$(cat "$CONFIG_FILE")
NAMESPACES=$(echo "$METRICS_CONFIG" | jq -r '.[].namespace')

# Calculate time range
END_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
START_TIME=$(date -u -d "$LOOKBACK_MINUTES minutes ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -v-${LOOKBACK_MINUTES}M +"%Y-%m-%dT%H:%M:%SZ")

# Initialize results
TOTAL_METRICS=0
AVAILABLE_METRICS=0
MISSING_METRICS=0
RESULTS=()

# Process each namespace and metric
for NAMESPACE in $NAMESPACES; do
    echo ""
    echo "Checking metrics in namespace: $NAMESPACE"
    
    # Get metrics in this namespace from config
    METRICS=$(echo "$METRICS_CONFIG" | jq -r --arg ns "$NAMESPACE" '.[] | select(.namespace == $ns).metrics')
    METRIC_COUNT=$(echo "$METRICS" | jq -r '. | length')
    
    for (( i=0; i<$METRIC_COUNT; i++ )); do
        METRIC_NAME=$(echo "$METRICS" | jq -r --argjson idx "$i" '.[$idx].name')
        STATISTIC=$(echo "$METRICS" | jq -r --argjson idx "$i" '.[$idx].statistic')
        PERIOD=$(echo "$METRICS" | jq -r --argjson idx "$i" '.[$idx].period')
        
        # Build dimensions parameter
        DIMENSIONS=$(echo "$METRICS" | jq -r --argjson idx "$i" '.[$idx].dimensions | map("Name=\(.name),Value=\(.value)") | join(" ")')
        
        echo "Checking metric: $METRIC_NAME (Dimensions: $DIMENSIONS)"
        TOTAL_METRICS=$((TOTAL_METRICS + 1))
        
        # Get metric data using AWS CLI
        METRIC_DATA=$(aws cloudwatch get-metric-statistics \
            --namespace "$NAMESPACE" \
            --metric-name "$METRIC_NAME" \
            --start-time "$START_TIME" \
            --end-time "$END_TIME" \
            --period "$PERIOD" \
            --statistics "$STATISTIC" \
            --dimensions $DIMENSIONS \
            --region "$REGION" \
            --output json 2>/dev/null)
        
        DATAPOINTS_COUNT=$(echo "$METRIC_DATA" | jq -r '.Datapoints | length')
        
        if [ "$DATAPOINTS_COUNT" -gt 0 ]; then
            STATUS="AVAILABLE"
            AVAILABLE_METRICS=$((AVAILABLE_METRICS + 1))
            LATEST_VALUE=$(echo "$METRIC_DATA" | jq -r '.Datapoints | sort_by(.Timestamp) | reverse | .[0].'"$STATISTIC")
        else
            STATUS="MISSING"
            MISSING_METRICS=$((MISSING_METRICS + 1))
            LATEST_VALUE="null"
        fi
        
        # Format dimensions for JSON
        JSON_DIMENSIONS=$(echo "$METRICS" | jq -r --argjson idx "$i" '.[$idx].dimensions')
        
        # Add to results
        RESULT=$(cat <<EOF
{
  "namespace": "$NAMESPACE",
  "metricName": "$METRIC_NAME",
  "dimensions": $JSON_DIMENSIONS,
  "status": "$STATUS",
  "datapoints": $DATAPOINTS_COUNT,
  "latestValue": $LATEST_VALUE
}
EOF
)
        RESULTS+=("$RESULT")
        
        echo "Status: $STATUS (Datapoints: $DATAPOINTS_COUNT)"
        if [ "$STATUS" = "AVAILABLE" ]; then
            echo "Latest value: $LATEST_VALUE"
        fi
    done
done

# Calculate success rate
if [ "$TOTAL_METRICS" -gt 0 ]; then
    SUCCESS_RATE=$(awk "BEGIN {printf \"%.1f\", ($AVAILABLE_METRICS * 100 / $TOTAL_METRICS)}")
else
    SUCCESS_RATE="0.0"
fi

# Generate JSON report
echo ""
echo "Generating validation report..."

# Join results array for JSON
JSON_RESULTS=$(printf '%s,' "${RESULTS[@]}" | sed 's/,$//')

# Create JSON report
cat > "$REPORT_FILE" << EOF
{
  "testName": "CloudWatch Metric Validation",
  "startTime": "$START_TIME",
  "endTime": "$END_TIME",
  "region": "$REGION",
  "lookbackMinutes": $LOOKBACK_MINUTES,
  "summary": {
    "totalMetrics": $TOTAL_METRICS,
    "availableMetrics": $AVAILABLE_METRICS,
    "missingMetrics": $MISSING_METRICS,
    "successRatePercent": $SUCCESS_RATE
  },
  "results": [$JSON_RESULTS]
}
EOF

# Print summary
echo ""
echo "Metric Validation Summary:"
echo "========================="
echo "Total metrics checked: $TOTAL_METRICS"
echo "Available metrics: $AVAILABLE_METRICS"
echo "Missing metrics: $MISSING_METRICS"
echo "Success rate: $SUCCESS_RATE%"
echo ""
echo "Detailed report saved to: $REPORT_FILE"