# DR Test Reports

This directory contains test report templates and generated test reports for AWS DR testing.

## Report Structure

Each test report should follow the structure defined in the templates:

### Resilience Testing
Reports for infrastructure and service resilience tests. These test how well the system recovers from component failures.

### Security Testing
Reports for security control validation. These test whether security controls remain effective during DR scenarios.

### Performance Testing
Reports for performance validation. These test whether performance meets SLAs during and after recovery.

## Report Naming Convention

Use the following naming convention for test reports:

```
YYYY-MM-DD_[test-type]_[test-id].md
```

Example:
```
2023-06-15_resilience_rds-failover-001.md
```

## Report Organization

Completed reports are organized by:

1. **Date** - Year and month directories
2. **Type** - Resilience, security, or performance
3. **Environment** - Development, production, or DR

Example:
```
2023/
├── 06-June/
│   ├── resilience/
│   │   ├── dev/
│   │   │   └── 2023-06-15_resilience_ec2-failure-001.md
│   │   └── prod/
│   │       └── 2023-06-20_resilience_rds-failover-001.md
│   └── security/
│       └── dev/
│           └── 2023-06-18_security_iam-validation-001.md
└── 07-July/
    └── performance/
        └── dr/
            └── 2023-07-05_performance_load-test-001.md
```

## Report Templates

Templates for each test type are available in the `templates/` directory:

- `resilience-test-report.md` - For infrastructure resilience tests
- `security-test-report.md` - For security control validation
- `performance-test-report.md` - For performance testing

## Metrics Attachments

Where possible, attach or link to the following artifacts:

- CloudWatch metric screenshots
- InSpec test results JSON
- Custom metric exports