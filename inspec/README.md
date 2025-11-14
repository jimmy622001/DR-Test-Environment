# InSpec Profiles for AWS DR Testing

This directory contains InSpec profiles for validating AWS infrastructure compliance during DR testing scenarios.

## Profile Organization

Profiles are organized by environment:

- **dev/**: Development environment compliance checks
- **prod/**: Production environment compliance checks
- **dr/**: Disaster recovery environment compliance checks

Each profile contains controls targeting specific AWS services:

- VPC configuration validation
- ECS/EKS configuration validation
- Security controls validation
- Database configuration validation

## Getting Started

### Prerequisites

1. Install InSpec:
   ```bash
   curl https://omnitruck.chef.io/install.sh | sudo bash -s -- -P inspec
   ```

2. Configure AWS credentials:
   ```bash
   aws configure --profile inspec-test
   ```

### Running Profiles

To run a complete profile:

```bash
inspec exec profiles/dev -t aws://us-east-1
```

To run specific controls:

```bash
inspec exec profiles/dev/controls/vpc.rb -t aws://us-east-1
```

To output results in multiple formats:

```bash
inspec exec profiles/dev -t aws://us-east-1 --reporter cli json:results.json html:results.html
```

## Profile Development

### Adding New Controls

1. Identify the AWS service to target
2. Create a new file in the appropriate profile's `controls` directory
3. Develop controls following InSpec best practices
4. Test controls against a non-production environment

### Example Control Structure

```ruby
control 'vpc-1' do
  impact 1.0
  title 'Ensure VPC has flow logs enabled'
  desc 'VPC flow logs provide visibility into network traffic'
  
  describe aws_vpc(vpc_id: input('primary_vpc_id')) do
    it { should exist }
    it { should have_flow_log }
  end
end
```

### Inputs

Each profile uses inputs to parameterize controls:

- Environment-specific values in `inputs/[env].yml`
- Service-specific values in `inputs/[service].yml`

Reference these inputs in controls using the `input()` method.

## Testing DR Scenarios

Special profiles for DR testing are available in the `dr` directory:

- **failover_validation**: Validates environment after failover
- **data_consistency**: Checks data consistency across regions
- **performance_regression**: Checks for performance degradation

Run these profiles after executing DR tests to validate recovery.

## Contributing

1. Fork the repository
2. Create a feature branch for your controls
3. Submit a pull request with detailed description
4. Ensure all existing controls still pass