#!/bin/bash
#
# RDS Backup and Recovery Test Script
# This script validates RDS snapshot creation, restoration, and data integrity
#

set -e

# Configuration
DB_IDENTIFIER=${1:-"test-db"}
SNAPSHOT_IDENTIFIER="${DB_IDENTIFIER}-snapshot-$(date +%Y%m%d-%H%M%S)"
RESTORED_DB_IDENTIFIER="${DB_IDENTIFIER}-restored"
VALIDATION_QUERY=${2:-"SELECT COUNT(*) FROM critical_table;"}
RESULT_FILE="rds-backup-test-results.json"

echo "Starting RDS Backup and Recovery Test for $DB_IDENTIFIER"
echo "=================================================="

# Step 1: Capture database metrics before backup
echo "Capturing pre-backup database metrics..."
PRE_BACKUP_COUNT=$(aws rds describe-db-instances --query "DBInstances[?DBInstanceIdentifier=='$DB_IDENTIFIER'].{Status:DBInstanceStatus}" --output text)
echo "Pre-backup DB status: $PRE_BACKUP_COUNT"

# Step 2: Create RDS snapshot
echo "Creating RDS snapshot $SNAPSHOT_IDENTIFIER..."
aws rds create-db-snapshot \
  --db-instance-identifier $DB_IDENTIFIER \
  --db-snapshot-identifier $SNAPSHOT_IDENTIFIER

# Step 3: Wait for snapshot to complete
echo "Waiting for snapshot to complete..."
aws rds wait db-snapshot-completed \
  --db-snapshot-identifier $SNAPSHOT_IDENTIFIER

echo "Snapshot creation completed"

# Step 4: Restore DB instance from snapshot
echo "Restoring DB instance from snapshot..."
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier $RESTORED_DB_IDENTIFIER \
  --db-snapshot-identifier $SNAPSHOT_IDENTIFIER \
  --db-subnet-group-name default

# Step 5: Wait for DB instance to be available
echo "Waiting for restored DB instance to be available..."
aws rds wait db-instance-available \
  --db-instance-identifier $RESTORED_DB_IDENTIFIER

echo "DB instance restoration completed"

# Step 6: Run data validation query (requires SQL client)
echo "Validating data integrity..."
echo "Please run the following validation query against both databases:"
echo "$VALIDATION_QUERY"
echo "Then compare the results to ensure data integrity"

# Step 7: Generate test report
echo "Generating test report..."

cat > $RESULT_FILE << EOL
{
  "testName": "RDS Backup and Recovery Test",
  "startTime": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "dbIdentifier": "$DB_IDENTIFIER",
  "snapshotIdentifier": "$SNAPSHOT_IDENTIFIER",
  "restoredDbIdentifier": "$RESTORED_DB_IDENTIFIER",
  "testResult": "MANUAL_VALIDATION_REQUIRED",
  "notes": "Execute validation query on both databases to verify data integrity"
}
EOL

echo "Test completed. Results saved to $RESULT_FILE"
echo "To complete validation:"
echo "1. Connect to original DB: $DB_IDENTIFIER"
echo "2. Connect to restored DB: $RESTORED_DB_IDENTIFIER"
echo "3. Run validation query on both and compare results"
echo "4. Clean up the restored DB when testing is complete with:"
echo "   aws rds delete-db-instance --db-instance-identifier $RESTORED_DB_IDENTIFIER --skip-final-snapshot"

# Cleanup instructions
echo ""
echo "Clean up resources with:"
echo "aws rds delete-db-snapshot --db-snapshot-identifier $SNAPSHOT_IDENTIFIER"
echo "aws rds delete-db-instance --db-instance-identifier $RESTORED_DB_IDENTIFIER --skip-final-snapshot"