# DR-Test-Environment Implementation Guide

This guide outlines how to implement the DR-Test-Environment project on existing AWS infrastructure that has been deployed with Terraform and CI/CD pipelines.

## Table of Contents
- [Overview](#overview)
- [Resource Inventory for Testing](#resource-inventory-for-testing)
  - [Why You Need a Resource Inventory](#why-you-need-a-resource-inventory)
  - [Creating Your Resource Inventory](#creating-your-resource-inventory)
  - [Integrating Your Inventory with DR Tests](#integrating-your-inventory-with-dr-tests)
- [Implementation Approach](#implementation-approach)
  - [Non-Intrusive Integration](#1-non-intrusive-integration)
  - [Configuration-Based Integration](#2-configuration-based-integration)
  - [IAM Integration](#3-iam-integration)
  - [Standalone DR Test Pipeline](#4-standalone-dr-test-pipeline)
  - [Testing in Non-Production Environments](#5-testing-in-non-production-environments)
  - [Practical Implementation Steps](#6-practical-implementation-steps)
- [Example Implementation Plan](#example-implementation-plan)
  - [Initial Setup (Week 1)](#1-initial-setup-week-1)
  - [Configuration (Week 1-2)](#2-configuration-week-1-2)
  - [Simple Tests (Week 2-3)](#3-simple-tests-week-2-3)
  - [Basic Resilience Tests (Week 3-4)](#4-basic-resilience-tests-week-3-4)
  - [Full DR Testing (Week 4-6)](#5-full-dr-testing-week-4-6)
- [Testing Environments and Progressive Implementation](#testing-environments-and-progressive-implementation)
  - [Progressive Testing Strategy](#progressive-testing-strategy)
  - [Environment-Specific Test Suites](#environment-specific-test-suites)
- [Key Benefits of This Approach](#key-benefits-of-this-approach)
- [Conclusion](#conclusion)

## Overview

The DR-Test-Environment project is a comprehensive framework for testing disaster recovery procedures in AWS environments. It includes tools for resilience testing, security validation, and performance measurement during DR scenarios.

## Resource Inventory for Testing

### Why You Need a Resource Inventory

A comprehensive inventory of AWS resources is essential for effective DR testing for several reasons:

- **Test Coverage**: Ensures all critical components are included in DR scenarios
- **Dependency Mapping**: Identifies relationships between resources for comprehensive testing
- **Resource Prioritization**: Helps focus testing on business-critical components first
- **Avoiding Production Impact**: Clearly delineates which resources can be tested in which environments

### Creating Your Resource Inventory

#### Option 1: Automated Discovery

```bash
# Script to extract resources from Terraform state
python scripts/inventory/terraform-state-parser.py --state-file path/to/terraform.tfstate --output inventory.json

# Alternative: Use AWS CLI to discover resources
python scripts/inventory/aws-resource-discovery.py --region us-east-1 --resource-types "ec2,rds,s3" --output inventory.json
```

#### Option 2: Configuration-Based Inventory

Create a structured inventory file that maps to your existing resources:

```json
{
  "environment": "production",
  "regions": ["us-east-1", "us-west-2"],
  "components": {
    "compute": {
      "ec2_instances": ["i-0abc123", "i-0def456"],
      "auto_scaling_groups": ["web-asg", "app-asg"],
      "lambda_functions": ["data-processor", "notification-sender"]
    },
    "storage": {
      "s3_buckets": ["company-data", "company-logs"],
      "ebs_volumes": ["vol-0abc123", "vol-0def456"],
      "rds_instances": ["db-primary", "db-replica"]
    },
    "networking": {
      "vpcs": ["vpc-0abc123"],
      "subnets": ["subnet-0abc123", "subnet-0def456"],
      "route_tables": ["rtb-0abc123"],
      "security_groups": ["sg-0abc123", "sg-0def456"]
    },
    "load_balancing": {
      "albs": ["app-balancer"],
      "nlbs": ["network-balancer"]
    }
  },
  "dependencies": [
    {"from": "app-asg", "to": "db-primary", "type": "database_connection"},
    {"from": "web-asg", "to": "app-balancer", "type": "load_balanced"}
  ]
}
```

### Integrating Your Inventory with DR Tests

1. **Tag resources** in your inventory with testing attributes:
   - `dr-test-eligible: true|false`
   - `dr-test-priority: high|medium|low`
   - `dr-test-environment: prod|staging|dev`

2. **Reference resources in test configurations** using their IDs from the inventory

3. **Create test subsets** based on priority or component types

## Implementation Approach

### 1. Non-Intrusive Integration

**Recommendation:** Implement the DR-Test-Environment as a separate "testing layer" that connects to but doesn't modify your existing infrastructure.

```
Existing AWS Infrastructure <---- DR Testing Framework
(Managed by Terraform)       (Add-on testing capabilities)
```

**Benefits:**
- No modifications required to existing Terraform code
- Can be deployed/removed without disrupting production
- Clear separation of concerns between infrastructure and testing

### 2. Configuration-Based Integration

**Steps:**
1. Create configuration files that describe your existing infrastructure
2. Use these configurations to point the testing tools at your resources
3. No need to redeploy infrastructure, just configure tests

**Example Configuration:**
```json
{
  "productionEnvironment": {
    "vpcId": "vpc-12345",
    "subnets": ["subnet-1", "subnet-2"],
    "rdsInstances": ["db-prod"],
    "ecsServices": ["service-1", "service-2"],
    "regions": ["us-east-1", "us-west-2"]
  }
}
```

### 3. IAM Integration

**Recommendation:** Create a dedicated IAM role for DR testing with appropriate permissions:

```terraform
resource "aws_iam_role" "dr_testing_role" {
  name = "dr-testing-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "fis.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "dr_testing_policy" {
  role       = aws_iam_role.dr_testing_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorEC2Access"
}
```

This can be added to your existing Terraform code without modifying existing resources.

### 4. Standalone DR Test Pipeline

**Recommendation:** Instead of integrating with your infrastructure CI/CD pipeline (which could slow it down), create a dedicated DR testing pipeline:

#### GitHub Actions Example

```yaml
name: DR Testing Pipeline

on:
  schedule:
    # Run weekly on Sunday at 1 AM
    - cron: '0 1 * * 0'
  workflow_dispatch:
    inputs:
      environment:
        description: 'Environment to test (dev/staging/prod)'
        required: true
        default: 'dev'
      test_suite:
        description: 'Test suite to run (basic/comprehensive/full)'
        required: true
        default: 'basic'

jobs:
  prepare:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Setup environment
        run: ./scripts/setup/environment-setup.sh
      - name: Load resource inventory
        run: python scripts/inventory/load-inventory.py --env ${{ github.event.inputs.environment || 'dev' }}

  run_dr_tests:
    needs: prepare
    runs-on: ubuntu-latest
    steps:
      - name: Run configuration validation
        run: ./scripts/tests/validate-configurations.sh
      - name: Run DR tests
        run: python scripts/tests/run-dr-tests.py --suite ${{ github.event.inputs.test_suite || 'basic' }}

  generate_reports:
    needs: run_dr_tests
    runs-on: ubuntu-latest
    steps:
      - name: Generate test reports
        run: python scripts/reporting/generate-report.py
      - name: Archive test results
        uses: actions/upload-artifact@v2
        with:
          name: dr-test-reports
          path: reports/
```

#### AWS CodePipeline Example

```json
{
  "name": "DR-Testing-Pipeline",
  "roleArn": "arn:aws:iam::123456789012:role/service-role/AWSCodePipelineServiceRole",
  "artifactStore": {
    "type": "S3",
    "location": "dr-test-pipeline-artifacts"
  },
  "stages": [
    {
      "name": "Source",
      "actions": [
        {
          "name": "Source",
          "actionTypeId": {
            "category": "Source",
            "owner": "AWS",
            "provider": "CodeStarSourceConnection",
            "version": "1"
          },
          "configuration": {
            "ConnectionArn": "arn:aws:codestar-connections:us-east-1:123456789012:connection/example",
            "FullRepositoryId": "your-org/DR-Test-Environment",
            "BranchName": "main"
          },
          "outputArtifacts": [
            {
              "name": "SourceCode"
            }
          ]
        }
      ]
    },
    {
      "name": "PrepareTests",
      "actions": [
        {
          "name": "LoadInventory",
          "actionTypeId": {
            "category": "Build",
            "owner": "AWS",
            "provider": "CodeBuild",
            "version": "1"
          },
          "configuration": {
            "ProjectName": "DR-Test-Inventory-Builder"
          },
          "inputArtifacts": [
            {
              "name": "SourceCode"
            }
          ],
          "outputArtifacts": [
            {
              "name": "InventoryConfig"
            }
          ]
        }
      ]
    },
    {
      "name": "RunTests",
      "actions": [
        {
          "name": "ExecuteDRTests",
          "actionTypeId": {
            "category": "Build",
            "owner": "AWS",
            "provider": "CodeBuild",
            "version": "1"
          },
          "configuration": {
            "ProjectName": "DR-Test-Executor"
          },
          "inputArtifacts": [
            {
              "name": "SourceCode"
            },
            {
              "name": "InventoryConfig"
            }
          ],
          "outputArtifacts": [
            {
              "name": "TestResults"
            }
          ]
        }
      ]
    },
    {
      "name": "ReportResults",
      "actions": [
        {
          "name": "GenerateReports",
          "actionTypeId": {
            "category": "Build",
            "owner": "AWS",
            "provider": "CodeBuild",
            "version": "1"
          },
          "configuration": {
            "ProjectName": "DR-Test-Reporter"
          },
          "inputArtifacts": [
            {
              "name": "TestResults"
            }
          ]
        }
      ]
    }
  ]
}
```

**Benefits of a Standalone Pipeline:**
- Can be scheduled independently from infrastructure deployments
- No risk of slowing down application deployment pipelines
- Can target different environments (dev/test) without affecting production
- Can be run with different scopes and intensity levels
- Dedicated resources for processing test results

### 5. Testing in Non-Production Environments

**Recommendation:** Configure your DR testing framework to primarily target non-production environments:

#### Environment Strategy

1. **Development Testing**
   - Full freedom to test all failure scenarios
   - Frequent testing (daily/weekly)
   - All resources can be targeted

2. **Staging/QA Testing**
   - Moderate disruption allowed
   - Regular testing (weekly/bi-weekly)
   - Most resources can be targeted

3. **Production Testing**
   - Limited to non-disruptive tests initially
   - Scheduled during maintenance windows
   - Only specific pre-approved resources
   - Full tests only after extensive validation in non-prod

#### Configuration Example

```json
{
  "test_environments": {
    "dev": {
      "aws_account_id": "123456789012",
      "aws_region": "us-east-1",
      "allowed_test_types": ["all"],
      "exempt_resources": [],
      "test_schedule": "weekly",
      "notification_channels": ["email:dev-team@example.com", "slack:dev-channel"]
    },
    "staging": {
      "aws_account_id": "234567890123",
      "aws_region": "us-east-1",
      "allowed_test_types": ["network", "compute", "storage"],
      "exempt_resources": ["db-staging-primary"],
      "test_schedule": "bi-weekly",
      "notification_channels": ["email:qa-team@example.com", "slack:staging-alerts"]
    },
    "production": {
      "aws_account_id": "345678901234",
      "aws_region": "us-east-1",
      "allowed_test_types": ["monitoring", "read-only"],
      "exempt_resources": ["db-prod-primary", "payment-processor"],
      "test_schedule": "monthly",
      "notification_channels": ["email:ops-team@example.com", "pagerduty:dr-oncall"]
    }
  }
}
```

### 6. Practical Implementation Steps

1. **Assessment Phase**
   - Map your existing AWS resources and regions
   - Create a comprehensive resource inventory
   - Identify critical components for DR testing
   - Define your RTO/RPO requirements

2. **Setup Phase** 
   - Set up the DR-Test-Environment repository in your organization
   - Configure the `config/test-environments.json` to point to your existing infrastructure
   - Create the necessary IAM roles and permissions
   - Set up the standalone pipeline

3. **Test Development**
   - Customize the InSpec profiles to match your infrastructure
   - Adapt the FIS experiment templates to test your specific services
   - Create specific test scenarios relevant to your applications

4. **Integration Phase**
   - Add DR testing to your CI/CD pipeline as an optional/scheduled stage
   - Start with read-only tests before moving to actual fault injection
   - Gradually increase test coverage and complexity

5. **Monitoring Integration**
   - Connect the testing framework to your existing monitoring tools
   - Ensure alerts are properly routed during tests
   - Set up dedicated test dashboards

## Example Implementation Plan

### 1. Initial Setup (Week 1)

```bash
# Clone the DR-Test-Environment repository
git clone https://github.com/your-org/DR-Test-Environment.git

# Configure AWS profiles for testing
aws configure --profile dr-testing

# Install required dependencies
bash scripts/setup/inspec-setup.sh
```

### 2. Configuration (Week 1-2)

```bash
# Edit configuration to point to your environment
vi config/test-environments.json
vi config/test-parameters.json
```

### 3. Simple Tests (Week 2-3)

Start with non-intrusive tests:

```bash
# Run InSpec compliance checks against your environment
inspec exec inspec/profiles/dev -t aws://us-east-1 --reporter cli json:output.json

# Create test dashboard
python scripts/monitoring/create-test-dashboard.py --env production
```

### 4. Basic Resilience Tests (Week 3-4)

```bash
# Execute read-only resilience tests
bash scripts/fis/run-fis-experiment.sh --experiment scripts/fis/network-latency.json --dry-run

# Analyze results
python scripts/analysis/evaluate-test.py --test-data test-metrics-latest.json
```

### 5. Full DR Testing (Week 4-6)

```bash
# Execute complete DR testing playbook
# Follow runbooks/test-execution.md
```

## Testing Environments and Progressive Implementation

### Progressive Testing Strategy

1. **Start with Read-Only Tests**
   - Begin with observability tests that don't modify infrastructure
   - Focus on validating monitoring and alerting systems
   - Validate that metric collection works across regions

2. **Progress to Limited-Impact Tests**
   - Introduce network latency tests on non-critical paths
   - Test failover mechanisms with minimal user impact
   - Run backup/restore validations in isolated environments

3. **Graduate to Full DR Tests**
   - Simulate complete region failure scenarios
   - Test full application stack recovery
   - Measure actual RTO/RPO against business requirements

### Environment-Specific Test Suites

```yaml
test_suites:
  # Safe for all environments including production
  read_only:
    - name: "Configuration Validation"
      script: "scripts/tests/validate-config.py"
    - name: "Monitoring Check"
      script: "scripts/tests/verify-monitoring.py"
    - name: "Backup Inventory"
      script: "scripts/tests/backup-inventory.py"

  # Safe for dev/staging, limited use in production
  limited_impact:
    - name: "Database Failover Validation"
      script: "scripts/tests/db-failover-test.py"
    - name: "Network Latency Test"
      script: "scripts/tests/network-latency.py"
    - name: "Load Balancer Failover"
      script: "scripts/tests/lb-failover.py"

  # For dev/staging only until well-proven
  full_disruption:
    - name: "Region Evacuation"
      script: "scripts/tests/region-evacuation.py"
    - name: "Complete Infrastructure Recovery"
      script: "scripts/tests/full-recovery.py"
    - name: "Multi-Region Failover"
      script: "scripts/tests/multi-region-test.py"
```

## Key Benefits of This Approach

1. **Non-Disruptive:** Can be implemented without changing your existing infrastructure
2. **Incremental:** Start small and expand testing coverage over time
3. **Flexible:** Works with any infrastructure deployed by Terraform
4. **Independent:** Runs as a standalone pipeline without affecting your main CI/CD
5. **Environment-Aware:** Can be configured differently for dev, staging, and production
6. **Inventory-Based:** Uses a comprehensive resource inventory for targeted testing
7. **Valuable Insights:** Provides concrete data on your DR capabilities

## Conclusion

The DR-Test-Environment project can be implemented as an add-on to existing AWS infrastructure deployed with Terraform and CI/CD pipelines. By following this approach, you can:

1. Run DR testing as a completely separate pipeline, avoiding any slowdown of your infrastructure deployment processes
2. Create and maintain a comprehensive resource inventory of resources to be tested
3. Safely run tests in development and staging environments before considering production testing
4. Gradually increase test coverage and complexity as your confidence grows

This implementation strategy gives you full control over what gets tested, when testing occurs, and how intensive the tests are. It also allows you to validate your DR capabilities without risking your production environment until you're fully confident in the testing framework.