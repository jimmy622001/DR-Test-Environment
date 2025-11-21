#!/bin/bash
#
# File Recovery Test Script
# Tests the restoration of files from backups by validating checksum integrity
#

set -e

# Configuration
BACKUP_LOCATION=${1:-"s3://my-backup-bucket/backups"}
RECOVERY_LOCATION=${2:-"./recovery-test"}
TEST_FILE_PATTERN=${3:-"*.json"}
CHECKSUM_METHOD=${4:-"sha256sum"}
MAX_FILES_TO_TEST=${5:-5}
REPORT_FILE="file-recovery-test-report.json"

echo "Starting File Recovery Test"
echo "=========================="
echo "Backup Location: $BACKUP_LOCATION"
echo "Recovery Location: $RECOVERY_LOCATION"
echo "Test File Pattern: $TEST_FILE_PATTERN"

# Create recovery directory
mkdir -p "$RECOVERY_LOCATION"

# Step 1: Select random files for testing
echo "Selecting files for recovery testing..."
if [[ $BACKUP_LOCATION == s3://* ]]; then
    # AWS S3 backup
    FILES_TO_TEST=$(aws s3 ls $BACKUP_LOCATION --recursive | grep "$TEST_FILE_PATTERN" | awk '{print $4}' | sort -R | head -n $MAX_FILES_TO_TEST)
else
    # Local backup
    FILES_TO_TEST=$(find "$BACKUP_LOCATION" -name "$TEST_FILE_PATTERN" | sort -R | head -n $MAX_FILES_TO_TEST)
fi

if [ -z "$FILES_TO_TEST" ]; then
    echo "No matching files found in backup location."
    exit 1
fi

# Step 2: Initialize results tracking
TOTAL_FILES=0
SUCCESSFUL_RECOVERIES=0
FAILED_RECOVERIES=0
TEST_RESULTS=()

# Step 3: Perform recovery tests
echo "Testing file recovery..."

for FILE in $FILES_TO_TEST; do
    echo "Testing recovery of: $FILE"
    TOTAL_FILES=$((TOTAL_FILES + 1))
    FILENAME=$(basename "$FILE")
    
    # Capture start time
    START_TIME=$(date +%s)
    
    # Calculate checksum of backup file
    if [[ $BACKUP_LOCATION == s3://* ]]; then
        # For S3 backups
        aws s3 cp "${BACKUP_LOCATION}/${FILE}" "${RECOVERY_LOCATION}/${FILENAME}"
        BACKUP_CHECKSUM=$(eval "$CHECKSUM_METHOD ${RECOVERY_LOCATION}/${FILENAME}" | awk '{print $1}')
    else
        # For local backups
        BACKUP_CHECKSUM=$(eval "$CHECKSUM_METHOD $FILE" | awk '{print $1}')
        cp "$FILE" "${RECOVERY_LOCATION}/${FILENAME}"
    fi
    
    # Calculate checksum of recovered file
    RECOVERED_CHECKSUM=$(eval "$CHECKSUM_METHOD ${RECOVERY_LOCATION}/${FILENAME}" | awk '{print $1}')
    
    # Capture end time and calculate duration
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    # Compare checksums
    if [ "$BACKUP_CHECKSUM" == "$RECOVERED_CHECKSUM" ]; then
        RESULT="SUCCESS"
        SUCCESSFUL_RECOVERIES=$((SUCCESSFUL_RECOVERIES + 1))
    else
        RESULT="FAILURE"
        FAILED_RECOVERIES=$((FAILED_RECOVERIES + 1))
    fi
    
    # Record test result
    TEST_RESULTS+=("{\"file\":\"$FILENAME\",\"result\":\"$RESULT\",\"duration_seconds\":$DURATION}")
    
    echo "Recovery test for $FILENAME: $RESULT (${DURATION}s)"
done

# Step 4: Generate test report
echo "Generating test report..."

# Build JSON array of test results
JSON_RESULTS=$(printf '%s,' "${TEST_RESULTS[@]}" | sed 's/,$//')

# Create JSON report
cat > $REPORT_FILE << EOL
{
  "testName": "File Recovery Test",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "backupLocation": "$BACKUP_LOCATION",
  "recoveryLocation": "$RECOVERY_LOCATION",
  "filePattern": "$TEST_FILE_PATTERN",
  "summary": {
    "totalFiles": $TOTAL_FILES,
    "successfulRecoveries": $SUCCESSFUL_RECOVERIES,
    "failedRecoveries": $FAILED_RECOVERIES,
    "successRate": $(echo "scale=2; ($SUCCESSFUL_RECOVERIES * 100) / $TOTAL_FILES" | bc)
  },
  "testResults": [$JSON_RESULTS]
}
EOL

echo ""
echo "Test completed. Results saved to $REPORT_FILE"
echo "Summary:"
echo "${SUCCESSFUL_RECOVERIES}/${TOTAL_FILES} files recovered successfully"
echo "${FAILED_RECOVERIES}/${TOTAL_FILES} files failed recovery"

# Step 5: Cleanup
echo ""
echo "Test artifacts are available at: ${RECOVERY_LOCATION}"
echo "To clean up test artifacts, run: rm -rf ${RECOVERY_LOCATION}"