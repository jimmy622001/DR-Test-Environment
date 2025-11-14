# encoding: utf-8
# copyright: Your Organization

title 'Security Configuration Checks'

environment = input('environment')

control 'security-cloudtrail-enabled' do
  impact 0.9
  title 'Ensure CloudTrail is enabled and properly configured'
  desc 'CloudTrail should be enabled to log API activity for security analysis and DR investigations'
  
  describe aws_cloudtrail_trails do
    it { should exist }
  end
  
  aws_cloudtrail_trails.trail_arns.each do |trail_arn|
    trail = aws_cloudtrail_trail(trail_arn)
    describe trail do
      it { should exist }
      it { should be_multi_region_trail }
      it { should have_log_file_validation_enabled }
      its('kms_key_id') { should_not be_nil }
    end
    
    trail_name = trail.trail_name
    describe aws_cloudtrail_trail(trail_name) do
      it { should be_encrypted }
    end
  end
end

control 'security-kms-key-rotation' do
  impact 0.8
  title 'Ensure KMS keys have rotation enabled'
  desc 'KMS keys should have rotation enabled to reduce the risk of key compromise'
  
  aws_kms_keys.key_ids.each do |key_id|
    next if aws_kms_key(key_id).key_manager == 'AWS'
    
    describe aws_kms_key(key_id) do
      it { should have_rotation_enabled }
    end
  end
end

control 'security-s3-buckets-encrypted' do
  impact 0.8
  title 'Ensure S3 buckets are encrypted'
  desc 'S3 buckets should have default encryption enabled'
  
  aws_s3_buckets.bucket_names.each do |bucket_name|
    next unless bucket_name.include?(environment)
    
    describe aws_s3_bucket(bucket_name) do
      it { should have_default_encryption_enabled }
    end
  end
end

control 'security-s3-buckets-not-public' do
  impact 0.9
  title 'Ensure S3 buckets are not publicly accessible'
  desc 'S3 buckets should not be configured for public access'
  
  aws_s3_buckets.bucket_names.each do |bucket_name|
    next unless bucket_name.include?(environment)
    
    describe aws_s3_bucket(bucket_name) do
      it { should_not be_public }
    end
  end
end

control 'security-security-groups-no-unrestricted-access' do
  impact 0.9
  title 'Ensure no security groups allow unrestricted access'
  desc 'Security groups should restrict access to necessary sources only'
  
  aws_security_groups.group_ids.each do |sg_id|
    describe aws_security_group(id: sg_id) do
      it { should_not allow_in(port: 22, ipv4_range: '0.0.0.0/0') }
      it { should_not allow_in(port: 3389, ipv4_range: '0.0.0.0/0') }
      it { should_not allow_in(port: 0, ipv4_range: '0.0.0.0/0') }
    end
  end
end

control 'security-iam-root-user-mfa' do
  impact 1.0
  title 'Ensure root user has MFA enabled'
  desc 'The AWS root user should have MFA enabled for increased security'
  
  describe aws_iam_root_user do
    it { should have_mfa_enabled }
  end
end

control 'security-guardduty-enabled' do
  impact 0.7
  title 'Ensure GuardDuty is enabled'
  desc 'GuardDuty should be enabled for threat detection'
  
  describe aws_guardduty_detector.detector_ids.first do
    it { should exist }
    its('status') { should eq 'ENABLED' }
  end if aws_guardduty_detector.exist?
end

control 'security-config-enabled' do
  impact 0.7
  title 'Ensure AWS Config is enabled'
  desc 'AWS Config should be enabled for resource compliance monitoring'
  
  describe aws_config_recorder do
    it { should exist }
    it { should be_recording }
    it { should be_recording_all_resource_types }
  end
end

control 'security-securityhub-enabled' do
  impact 0.7
  title 'Ensure Security Hub is enabled'
  desc 'Security Hub should be enabled for consolidated security findings'
  
  describe aws_security_hub_control.exist? do
    it { should be true }
  end
end