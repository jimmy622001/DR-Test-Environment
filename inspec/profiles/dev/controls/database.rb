# encoding: utf-8
# copyright: Your Organization

title 'Database Configuration Checks'

environment = input('environment')
rds_db_instance_identifier = input('rds_db_instance_identifier', value: nil)

control 'db-rds-multi-az' do
  impact 0.8
  title 'Ensure RDS instances are Multi-AZ'
  desc 'RDS instances should be configured for Multi-AZ for high availability'
  
  only_if do
    rds_db_instance_identifier != nil
  end
  
  describe aws_rds_instance(db_instance_identifier: rds_db_instance_identifier) do
    it { should be_multi_az }
  end
end

control 'db-rds-encrypted' do
  impact 0.7
  title 'Ensure RDS instances are encrypted'
  desc 'RDS instances should have encryption enabled'
  
  aws_rds_instances.db_instance_identifiers.each do |db_identifier|
    next unless db_identifier.include?(environment)
    
    describe aws_rds_instance(db_instance_identifier: db_identifier) do
      it { should be_encrypted }
    end
  end
end

control 'db-rds-automatic-backup' do
  impact 0.7
  title 'Ensure RDS instances have automated backups enabled'
  desc 'RDS instances should have automated backups enabled with a sufficient retention period'
  
  aws_rds_instances.db_instance_identifiers.each do |db_identifier|
    next unless db_identifier.include?(environment)
    
    describe aws_rds_instance(db_instance_identifier: db_identifier) do
      its('backup_retention_period') { should be >= 7 }
      it { should have_automated_backup }
    end
  end
end

control 'db-rds-public-access' do
  impact 0.9
  title 'Ensure RDS instances are not publicly accessible'
  desc 'RDS instances should not be publicly accessible'
  
  aws_rds_instances.db_instance_identifiers.each do |db_identifier|
    next unless db_identifier.include?(environment)
    
    describe aws_rds_instance(db_instance_identifier: db_identifier) do
      it { should_not be_publicly_accessible }
    end
  end
end

control 'db-rds-enhanced-monitoring' do
  impact 0.6
  title 'Ensure RDS instances have enhanced monitoring enabled'
  desc 'RDS instances should have enhanced monitoring enabled for better visibility'
  
  aws_rds_instances.db_instance_identifiers.each do |db_identifier|
    next unless db_identifier.include?(environment)
    
    describe aws_rds_instance(db_instance_identifier: db_identifier) do
      its('monitoring_interval') { should be > 0 }
    end
  end
end

control 'db-dynamodb-point-in-time-recovery' do
  impact 0.7
  title 'Ensure DynamoDB tables have point-in-time recovery enabled'
  desc 'DynamoDB tables should have point-in-time recovery enabled for data protection'
  
  aws_dynamodb_tables.table_names.each do |table_name|
    next unless table_name.include?(environment)
    
    describe aws_dynamodb_table(table_name) do
      it { should have_point_in_time_recovery_enabled }
    end
  end
end

control 'db-dynamodb-encrypted' do
  impact 0.7
  title 'Ensure DynamoDB tables are encrypted'
  desc 'DynamoDB tables should be encrypted'
  
  aws_dynamodb_tables.table_names.each do |table_name|
    next unless table_name.include?(environment)
    
    describe aws_dynamodb_table(table_name) do
      it { should be_encrypted }
    end
  end
end

control 'db-dynamodb-autoscaling' do
  impact 0.6
  title 'Ensure DynamoDB tables have auto-scaling configured'
  desc 'DynamoDB tables should have auto-scaling configured for read and write capacity'
  
  aws_dynamodb_tables.table_names.each do |table_name|
    next unless table_name.include?(environment)
    
    table = aws_dynamodb_table(table_name)
    
    if table.billing_mode_summary.billing_mode == 'PROVISIONED'
      describe "DynamoDB table #{table_name}" do
        it "should have auto scaling configured" do
          has_scaling = false
          
          begin
            autoscaling_client = Aws::ApplicationAutoScaling::Client.new
            
            read_targets = autoscaling_client.describe_scalable_targets({
              service_namespace: "dynamodb",
              resource_ids: ["table/#{table_name}"],
              scalable_dimension: "dynamodb:table:ReadCapacityUnits"
            }).scalable_targets
            
            write_targets = autoscaling_client.describe_scalable_targets({
              service_namespace: "dynamodb",
              resource_ids: ["table/#{table_name}"],
              scalable_dimension: "dynamodb:table:WriteCapacityUnits"
            }).scalable_targets
            
            has_scaling = !read_targets.empty? && !write_targets.empty?
          rescue StandardError => e
            # Handle errors or permissions issues
            has_scaling = false
          end
          
          expect(has_scaling).to be true
        end
      end
    end
  end
end