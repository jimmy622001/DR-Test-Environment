#!/usr/bin/env python3
"""
S3 Backup Validation Script

This script validates S3 bucket replications and backup strategies by:
1. Comparing source and destination buckets
2. Validating object integrity
3. Testing restoration procedures
"""

import argparse
import boto3
import hashlib
import json
import time
from datetime import datetime
from botocore.exceptions import ClientError

def get_md5(s3_client, bucket, key):
    """Get MD5 hash of an S3 object"""
    try:
        response = s3_client.head_object(Bucket=bucket, Key=key)
        return response.get('ETag', '').strip('"')
    except ClientError as e:
        print(f"Error getting MD5 for {bucket}/{key}: {e}")
        return None

def compare_objects(s3_client, source_bucket, dest_bucket, prefix=''):
    """Compare objects between source and destination buckets"""
    print(f"Comparing objects with prefix '{prefix}'...")
    
    results = {
        'matching_objects': 0,
        'missing_objects': 0,
        'mismatched_objects': [],
        'details': []
    }
    
    # Get objects from source bucket
    paginator = s3_client.get_paginator('list_objects_v2')
    source_pages = paginator.paginate(Bucket=source_bucket, Prefix=prefix)
    
    for page in source_pages:
        if 'Contents' not in page:
            continue
            
        for obj in page['Contents']:
            source_key = obj['Key']
            source_size = obj['Size']
            source_md5 = obj['ETag'].strip('"')
            
            # Check if object exists in destination
            try:
                dest_obj = s3_client.head_object(Bucket=dest_bucket, Key=source_key)
                dest_size = dest_obj['ContentLength']
                dest_md5 = dest_obj['ETag'].strip('"')
                
                if source_md5 == dest_md5 and source_size == dest_size:
                    results['matching_objects'] += 1
                    status = "MATCH"
                else:
                    results['mismatched_objects'].append(source_key)
                    status = "MISMATCH"
            except ClientError:
                results['missing_objects'] += 1
                status = "MISSING"
            
            results['details'].append({
                'key': source_key,
                'status': status
            })
    
    return results

def test_restore(s3_client, source_bucket, test_bucket, sample_keys):
    """Test restoration of sample objects from source to test bucket"""
    print(f"Testing restoration of {len(sample_keys)} sample objects...")
    
    results = {
        'successful_restores': 0,
        'failed_restores': 0,
        'details': []
    }
    
    for key in sample_keys:
        try:
            # Copy object from source to test bucket
            s3_client.copy_object(
                CopySource={'Bucket': source_bucket, 'Key': key},
                Bucket=test_bucket,
                Key=f"restore-test/{key}"
            )
            
            # Verify the restored object
            source_md5 = get_md5(s3_client, source_bucket, key)
            restored_md5 = get_md5(s3_client, test_bucket, f"restore-test/{key}")
            
            if source_md5 == restored_md5:
                results['successful_restores'] += 1
                status = "SUCCESS"
            else:
                results['failed_restores'] += 1
                status = "INTEGRITY_FAILURE"
        except Exception as e:
            results['failed_restores'] += 1
            status = f"ERROR: {str(e)}"
        
        results['details'].append({
            'key': key,
            'status': status
        })
    
    return results

def main():
    parser = argparse.ArgumentParser(description='S3 Backup Validation Tool')
    parser.add_argument('--source', required=True, help='Source S3 bucket name')
    parser.add_argument('--destination', required=True, help='Destination S3 bucket name')
    parser.add_argument('--test-bucket', help='Test bucket for restoration validation')
    parser.add_argument('--prefix', default='', help='Object prefix to validate')
    parser.add_argument('--sample-size', type=int, default=5, help='Number of sample objects to test restore')
    parser.add_argument('--region', default='us-east-1', help='AWS region')
    parser.add_argument('--report-file', default='s3-backup-validation-report.json', help='Report output file')
    
    args = parser.parse_args()
    
    # Initialize S3 client
    s3_client = boto3.client('s3', region_name=args.region)
    
    # Start time
    start_time = datetime.utcnow()
    
    # Compare buckets
    comparison_results = compare_objects(s3_client, args.source, args.destination, args.prefix)
    
    # Test restoration if test bucket is provided
    restore_results = None
    if args.test_bucket:
        # Get sample keys for restore testing
        paginator = s3_client.get_paginator('list_objects_v2')
        pages = paginator.paginate(Bucket=args.source, Prefix=args.prefix, MaxItems=100)
        
        sample_keys = []
        for page in pages:
            if 'Contents' in page:
                sample_keys.extend([obj['Key'] for obj in page['Contents']])
                if len(sample_keys) >= args.sample_size:
                    break
        
        sample_keys = sample_keys[:args.sample_size]
        restore_results = test_restore(s3_client, args.source, args.test_bucket, sample_keys)
    
    # End time
    end_time = datetime.utcnow()
    
    # Generate report
    report = {
        'test_name': 'S3 Backup Validation',
        'start_time': start_time.isoformat(),
        'end_time': end_time.isoformat(),
        'duration_seconds': (end_time - start_time).total_seconds(),
        'source_bucket': args.source,
        'destination_bucket': args.destination,
        'prefix': args.prefix,
        'comparison_results': comparison_results,
        'restore_results': restore_results
    }
    
    # Save report to file
    with open(args.report_file, 'w') as f:
        json.dump(report, f, indent=2)
    
    # Print summary
    print("\nValidation Summary:")
    print(f"Source Bucket: {args.source}")
    print(f"Destination Bucket: {args.destination}")
    print(f"Objects compared: {comparison_results['matching_objects'] + len(comparison_results['mismatched_objects']) + comparison_results['missing_objects']}")
    print(f"Matching objects: {comparison_results['matching_objects']}")
    print(f"Mismatched objects: {len(comparison_results['mismatched_objects'])}")
    print(f"Missing objects: {comparison_results['missing_objects']}")
    
    if restore_results:
        print(f"\nRestore Tests: {restore_results['successful_restores']} successful, {restore_results['failed_restores']} failed")
    
    print(f"\nDetailed report saved to: {args.report_file}")

if __name__ == "__main__":
    main()