#!/usr/bin/env python3
"""
Log Aggregation Validation Script

This script validates that log aggregation systems are correctly collecting 
logs from all required sources after a DR event.
"""

import argparse
import boto3
import json
import time
import uuid
from datetime import datetime, timedelta
from botocore.exceptions import ClientError

def generate_test_log_event(service_name, instance_id):
    """Generate a unique test log event"""
    test_id = str(uuid.uuid4())
    timestamp = datetime.utcnow().isoformat()
    return {
        "test_id": test_id,
        "message": f"DR TEST LOG - {service_name} - {timestamp}",
        "service": service_name,
        "instance_id": instance_id,
        "timestamp": timestamp
    }

def send_cloudwatch_test_event(logs_client, log_group, log_stream, event):
    """Send a test event to CloudWatch Logs"""
    try:
        # Get the sequence token if needed
        try:
            response = logs_client.describe_log_streams(
                logGroupName=log_group,
                logStreamNamePrefix=log_stream
            )
            
            sequence_token = None
            for stream in response['logStreams']:
                if stream['logStreamName'] == log_stream:
                    sequence_token = stream.get('uploadSequenceToken')
                    
            if sequence_token is None:
                # Create the log stream if it doesn't exist
                try:
                    logs_client.create_log_stream(
                        logGroupName=log_group,
                        logStreamName=log_stream
                    )
                except ClientError as e:
                    if e.response['Error']['Code'] != 'ResourceAlreadyExistsException':
                        raise
        except ClientError as e:
            if e.response['Error']['Code'] == 'ResourceNotFoundException':
                # Create the log group and stream if they don't exist
                logs_client.create_log_group(logGroupName=log_group)
                logs_client.create_log_stream(
                    logGroupName=log_group,
                    logStreamName=log_stream
                )
                sequence_token = None
            else:
                raise

        # Send the log event
        log_event = {
            'timestamp': int(time.time() * 1000),
            'message': json.dumps(event)
        }
        
        kwargs = {
            'logGroupName': log_group,
            'logStreamName': log_stream,
            'logEvents': [log_event]
        }
        
        if sequence_token:
            kwargs['sequenceToken'] = sequence_token
            
        response = logs_client.put_log_events(**kwargs)
        return True
        
    except Exception as e:
        print(f"Error sending CloudWatch log event: {str(e)}")
        return False

def check_log_aggregation(logs_client, log_group, log_stream, test_id, delay=30):
    """Check if the test log event was aggregated properly"""
    print(f"Waiting {delay} seconds for logs to be aggregated...")
    time.sleep(delay)
    
    try:
        # Query for the test event
        end_time = int(time.time() * 1000)
        start_time = end_time - (delay * 2 * 1000)  # Look back twice the delay time
        
        response = logs_client.filter_log_events(
            logGroupName=log_group,
            logStreamNames=[log_stream],
            filterPattern=f'"{test_id}"',
            startTime=start_time,
            endTime=end_time
        )
        
        return len(response.get('events', [])) > 0
        
    except Exception as e:
        print(f"Error checking log aggregation: {str(e)}")
        return False

def test_service_logs(service_config, region):
    """Test log aggregation for a specific service"""
    service_name = service_config['service_name']
    sources = service_config['log_sources']
    log_group = service_config['log_group']
    results = []
    
    logs_client = boto3.client('logs', region_name=region)
    
    print(f"\nTesting log aggregation for {service_name}...")
    
    for source in sources:
        source_id = source['id']
        log_stream = source.get('log_stream', f"{service_name}-{source_id}")
        
        print(f"Testing source: {source_id} (Stream: {log_stream})")
        
        # Generate and send test event
        test_event = generate_test_log_event(service_name, source_id)
        test_id = test_event['test_id']
        
        send_success = send_cloudwatch_test_event(logs_client, log_group, log_stream, test_event)
        
        if not send_success:
            results.append({
                'source': source_id,
                'log_stream': log_stream,
                'status': 'FAILED',
                'error': 'Failed to send test event'
            })
            continue
        
        # Check if log was aggregated
        is_aggregated = check_log_aggregation(logs_client, log_group, log_stream, test_id)
        
        results.append({
            'source': source_id,
            'log_stream': log_stream,
            'status': 'SUCCESS' if is_aggregated else 'FAILED',
            'test_id': test_id,
            'timestamp': test_event['timestamp']
        })
    
    return results

def main():
    parser = argparse.ArgumentParser(description='Log Aggregation Validation Tool')
    parser.add_argument('--config', default='log-sources.json', help='Configuration file with log sources')
    parser.add_argument('--region', default='us-east-1', help='AWS region')
    parser.add_argument('--report-file', default='log-aggregation-report.json', help='Report output file')
    
    args = parser.parse_args()
    
    try:
        # Load configuration
        with open(args.config, 'r') as f:
            config = json.load(f)
    except Exception as e:
        print(f"Error loading configuration: {str(e)}")
        print("Creating sample configuration file...")
        
        sample_config = [
            {
                "service_name": "api-service",
                "log_group": "/dr-test/api-service",
                "log_sources": [
                    {"id": "instance-1", "log_stream": "api-service-instance-1"},
                    {"id": "instance-2", "log_stream": "api-service-instance-2"}
                ]
            },
            {
                "service_name": "database",
                "log_group": "/dr-test/database",
                "log_sources": [
                    {"id": "db-primary", "log_stream": "database-primary"},
                    {"id": "db-replica", "log_stream": "database-replica"}
                ]
            }
        ]
        
        with open(args.config, 'w') as f:
            json.dump(sample_config, f, indent=2)
            
        print(f"Sample configuration created at {args.config}. Please edit it and run again.")
        return
    
    # Start time
    start_time = datetime.utcnow()
    
    # Run tests for each service
    all_results = []
    for service_config in config:
        service_results = test_service_logs(service_config, args.region)
        all_results.append({
            'service': service_config['service_name'],
            'log_group': service_config['log_group'],
            'test_results': service_results
        })
    
    # End time
    end_time = datetime.utcnow()
    
    # Summarize results
    total_sources = 0
    successful_sources = 0
    
    for service in all_results:
        for result in service['test_results']:
            total_sources += 1
            if result['status'] == 'SUCCESS':
                successful_sources += 1
    
    success_rate = (successful_sources / total_sources) * 100 if total_sources > 0 else 0
    
    # Generate report
    report = {
        'test_name': 'Log Aggregation Validation',
        'start_time': start_time.isoformat(),
        'end_time': end_time.isoformat(),
        'duration_seconds': (end_time - start_time).total_seconds(),
        'summary': {
            'total_sources': total_sources,
            'successful_sources': successful_sources,
            'failure_count': total_sources - successful_sources,
            'success_rate_percent': success_rate
        },
        'service_results': all_results
    }
    
    # Save report
    with open(args.report_file, 'w') as f:
        json.dump(report, f, indent=2)
    
    # Print summary
    print("\nLog Aggregation Test Summary:")
    print(f"Total log sources tested: {total_sources}")
    print(f"Successful sources: {successful_sources}")
    print(f"Failed sources: {total_sources - successful_sources}")
    print(f"Success rate: {success_rate:.1f}%")
    print(f"\nDetailed report saved to: {args.report_file}")

if __name__ == "__main__":
    main()