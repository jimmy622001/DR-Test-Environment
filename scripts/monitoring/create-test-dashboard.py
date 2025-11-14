#!/usr/bin/env python3

import argparse
import boto3
import json
import uuid
from datetime import datetime

def parse_arguments():
    parser = argparse.ArgumentParser(description='Create CloudWatch dashboard for DR testing')
    parser.add_argument('--env', required=True, help='Environment name (e.g., dr-test)')
    parser.add_argument('--region', default=None, help='AWS region (defaults to AWS_PROFILE region)')
    parser.add_argument('--profile', default='dr-testing', help='AWS profile to use')
    parser.add_argument('--output', default=None, help='Output file for dashboard JSON')
    return parser.parse_args()

def create_dashboard(env_name, region, profile):
    """Create a CloudWatch dashboard for DR testing monitoring"""
    # Initialize boto3 clients
    session = boto3.Session(profile_name=profile, region_name=region)
    cloudwatch = session.client('cloudwatch')
    ec2 = session.client('ec2')
    rds = session.client('rds')
    elbv2 = session.client('elbv2')
    
    # Get resources with environment tag
    print(f"Finding resources in {env_name} environment...")
    
    # Find EC2 instances
    instances = ec2.describe_instances(
        Filters=[{'Name': 'tag:Environment', 'Values': [env_name]}]
    )
    instance_ids = []
    for reservation in instances.get('Reservations', []):
        for instance in reservation.get('Instances', []):
            if instance['State']['Name'] == 'running':
                instance_ids.append(instance['InstanceId'])
    
    print(f"Found {len(instance_ids)} EC2 instances")
    
    # Find RDS instances
    db_instances = rds.describe_db_instances()
    db_instance_ids = []
    for db in db_instances.get('DBInstances', []):
        for tag in db.get('TagList', []):
            if tag['Key'] == 'Environment' and tag['Value'] == env_name:
                db_instance_ids.append(db['DBInstanceIdentifier'])
                break
    
    print(f"Found {len(db_instance_ids)} RDS instances")
    
    # Find load balancers
    load_balancers = elbv2.describe_load_balancers()
    lb_arns = []
    for lb in load_balancers.get('LoadBalancers', []):
        lb_tags = elbv2.describe_tags(ResourceArns=[lb['LoadBalancerArn']])
        for tag_desc in lb_tags.get('TagDescriptions', []):
            for tag in tag_desc.get('Tags', []):
                if tag['Key'] == 'Environment' and tag['Value'] == env_name:
                    lb_arns.append(lb['LoadBalancerArn'])
                    break
    
    print(f"Found {len(lb_arns)} load balancers")
    
    # Create dashboard widgets
    widgets = []
    
    # Header text widget
    widgets.append({
        "type": "text",
        "x": 0,
        "y": 0,
        "width": 24,
        "height": 2,
        "properties": {
            "markdown": f"# Disaster Recovery Test Dashboard - {env_name}\n**Last updated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}**"
        }
    })
    
    y_position = 2
    
    # EC2 instance metrics
    if instance_ids:
        # CPU utilization
        widgets.append({
            "type": "metric",
            "x": 0,
            "y": y_position,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/EC2", "CPUUtilization", "InstanceId", id ] for id in instance_ids
                ],
                "view": "timeSeries",
                "stacked": False,
                "region": region,
                "title": "EC2 CPU Utilization",
                "period": 60,
                "stat": "Average"
            }
        })
        
        # Network In/Out
        widgets.append({
            "type": "metric",
            "x": 12,
            "y": y_position,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/EC2", "NetworkIn", "InstanceId", id ] for id in instance_ids
                ] + [
                    [ "AWS/EC2", "NetworkOut", "InstanceId", id ] for id in instance_ids
                ],
                "view": "timeSeries",
                "stacked": False,
                "region": region,
                "title": "EC2 Network Traffic",
                "period": 60,
                "stat": "Average"
            }
        })
        
        y_position += 6
    
    # RDS instance metrics
    if db_instance_ids:
        # CPU utilization
        widgets.append({
            "type": "metric",
            "x": 0,
            "y": y_position,
            "width": 8,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", id ] for id in db_instance_ids
                ],
                "view": "timeSeries",
                "stacked": False,
                "region": region,
                "title": "RDS CPU Utilization",
                "period": 60,
                "stat": "Average"
            }
        })
        
        # Connection count
        widgets.append({
            "type": "metric",
            "x": 8,
            "y": y_position,
            "width": 8,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", id ] for id in db_instance_ids
                ],
                "view": "timeSeries",
                "stacked": False,
                "region": region,
                "title": "RDS Connections",
                "period": 60,
                "stat": "Average"
            }
        })
        
        # Read/Write IOPS
        widgets.append({
            "type": "metric",
            "x": 16,
            "y": y_position,
            "width": 8,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/RDS", "ReadIOPS", "DBInstanceIdentifier", id ] for id in db_instance_ids
                ] + [
                    [ "AWS/RDS", "WriteIOPS", "DBInstanceIdentifier", id ] for id in db_instance_ids
                ],
                "view": "timeSeries",
                "stacked": False,
                "region": region,
                "title": "RDS IOPS",
                "period": 60,
                "stat": "Average"
            }
        })
        
        y_position += 6
    
    # Load balancer metrics
    if lb_arns:
        lb_names = [arn.split('/')[-1] for arn in lb_arns]
        
        # Request count
        widgets.append({
            "type": "metric",
            "x": 0,
            "y": y_position,
            "width": 8,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/ApplicationELB", "RequestCount", "LoadBalancer", name ] for name in lb_names
                ],
                "view": "timeSeries",
                "stacked": False,
                "region": region,
                "title": "ELB Request Count",
                "period": 60,
                "stat": "Sum"
            }
        })
        
        # Target response time
        widgets.append({
            "type": "metric",
            "x": 8,
            "y": y_position,
            "width": 8,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", name ] for name in lb_names
                ],
                "view": "timeSeries",
                "stacked": False,
                "region": region,
                "title": "ELB Response Time",
                "period": 60,
                "stat": "Average"
            }
        })
        
        # HTTP errors
        widgets.append({
            "type": "metric",
            "x": 16,
            "y": y_position,
            "width": 8,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", name ] for name in lb_names
                ] + [
                    [ "AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", "LoadBalancer", name ] for name in lb_names
                ],
                "view": "timeSeries",
                "stacked": False,
                "region": region,
                "title": "ELB HTTP Errors",
                "period": 60,
                "stat": "Sum"
            }
        })
        
        y_position += 6
    
    # Add custom DR test metrics section
    widgets.append({
        "type": "text",
        "x": 0,
        "y": y_position,
        "width": 24,
        "height": 1,
        "properties": {
            "markdown": "## DR Test Metrics"
        }
    })
    
    y_position += 1
    
    # Add DR test metrics (these are placeholders - assumes you'll publish custom metrics)
    widgets.append({
        "type": "metric",
        "x": 0,
        "y": y_position,
        "width": 8,
        "height": 6,
        "properties": {
            "metrics": [
                [ "DRTest", "RecoveryTime", "TestId", "latest" ],
            ],
            "view": "gauge",
            "region": region,
            "title": "Recovery Time (seconds)",
            "period": 60,
            "stat": "Maximum",
            "yAxis": {
                "left": {
                    "min": 0,
                    "max": 1800
                }
            }
        }
    })
    
    widgets.append({
        "type": "metric",
        "x": 8,
        "y": y_position,
        "width": 8,
        "height": 6,
        "properties": {
            "metrics": [
                [ "DRTest", "DataLoss", "TestId", "latest" ],
            ],
            "view": "gauge",
            "region": region,
            "title": "Data Loss (seconds)",
            "period": 60,
            "stat": "Maximum",
            "yAxis": {
                "left": {
                    "min": 0,
                    "max": 900
                }
            }
        }
    })
    
    widgets.append({
        "type": "metric",
        "x": 16,
        "y": y_position,
        "width": 8,
        "height": 6,
        "properties": {
            "metrics": [
                [ "DRTest", "SuccessRate", "TestId", "latest" ],
            ],
            "view": "gauge",
            "region": region,
            "title": "Test Success Rate (%)",
            "period": 60,
            "stat": "Average",
            "yAxis": {
                "left": {
                    "min": 0,
                    "max": 100
                }
            }
        }
    })
    
    # Create the dashboard JSON
    dashboard_body = {
        "widgets": widgets
    }
    
    dashboard_name = f"dr-test-dashboard-{env_name}"
    
    print(f"Creating dashboard: {dashboard_name}")
    response = cloudwatch.put_dashboard(
        DashboardName=dashboard_name,
        DashboardBody=json.dumps(dashboard_body)
    )
    
    print(f"Dashboard created: https://{region}.console.aws.amazon.com/cloudwatch/home?region={region}#dashboards:name={dashboard_name}")
    return dashboard_name, dashboard_body

if __name__ == "__main__":
    args = parse_arguments()
    
    dashboard_name, dashboard_body = create_dashboard(args.env, args.region, args.profile)
    
    if args.output:
        with open(args.output, 'w') as f:
            json.dump(dashboard_body, f, indent=2)
        print(f"Dashboard JSON saved to {args.output}")