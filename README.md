# AWS Disaster Recovery Testing Framework

This repository contains a comprehensive framework for testing disaster recovery procedures in AWS environments. It provides structured playbooks, runbooks, and automated testing tools to validate the resilience, security, and performance of AWS infrastructures.

## Purpose

- Validate AWS infrastructure resilience during failures
- Test recovery procedures and ensure they meet RTO/RPO requirements
- Verify security controls remain effective during disaster scenarios
- Measure performance under various failure conditions

## Repository Structure

- **playbooks/**: Detailed procedures for different types of testing
- **runbooks/**: Step-by-step execution guides for test operations
- **inspec/**: Infrastructure compliance testing profiles
- **scripts/**: Automation scripts for test operations
- **test-reports/**: Templates and structure for documenting test results
- **config/**: Configuration files for test environments
- **docs/**: Documentation for the testing project

## Getting Started

1. Review the test strategy in `docs/test-strategy.md`
2. Set up your test environment using `runbooks/test-environment-setup.md`
3. Execute tests following the appropriate playbook
4. Document results using the templates in `test-reports/templates/`

## Prerequisites

- AWS CLI configured with appropriate permissions
- InSpec installed (see `scripts/setup/inspec-setup.sh`)
- Appropriate AWS service permissions for FIS experiments

## Contributing

1. Fork the repository
2. Create a feature branch
3. Submit a pull request with detailed description of changes

## License

[Specify your license]