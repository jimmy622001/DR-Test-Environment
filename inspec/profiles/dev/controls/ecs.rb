# encoding: utf-8
# copyright: Your Organization

title 'ECS Configuration Checks'

environment = input('environment')

control 'ecs-clusters-healthy' do
  impact 0.8
  title 'Ensure ECS clusters are healthy'
  desc 'ECS clusters should be properly configured and healthy'
  
  aws_ecs_clusters.cluster_names.each do |cluster_name|
    next unless cluster_name.include?(environment)
    
    describe aws_ecs_cluster(cluster_name: cluster_name) do
      it { should exist }
      its('status') { should eq 'ACTIVE' }
    end
  end
end

control 'ecs-services-high-availability' do
  impact 0.9
  title 'Ensure ECS services are configured for high availability'
  desc 'ECS services should be configured with multiple tasks for redundancy'
  
  aws_ecs_clusters.cluster_names.each do |cluster_name|
    next unless cluster_name.include?(environment)
    
    aws_ecs_services(cluster: cluster_name).service_names.each do |service_name|
      service = aws_ecs_service(cluster: cluster_name, service: service_name)
      
      describe service do
        it { should exist }
        its('desired_count') { should be >= 2 }
      end
      
      describe "ECS service #{service_name} deployment configuration" do
        subject { service.deployments.first }
        its(['desiredCount']) { should be >= 2 }
        its(['minimumHealthyPercent']) { should be >= 50 }
      end
    end
  end
end

control 'ecs-tasks-logging-configured' do
  impact 0.6
  title 'Ensure ECS tasks have logging configured'
  desc 'ECS tasks should log to CloudWatch Logs for observability during DR'
  
  aws_ecs_clusters.cluster_names.each do |cluster_name|
    next unless cluster_name.include?(environment)
    
    aws_ecs_task_definitions.family_names.each do |family_name|
      next unless family_name.include?(environment)
      
      task_def = aws_ecs_task_definition(family: family_name)
      
      describe "Task definition #{family_name}" do
        container_defs = task_def.container_definitions
        has_logging = container_defs.any? do |container|
          container['logConfiguration']&.dig('logDriver') == 'awslogs'
        end
        
        it "should have CloudWatch logging configured" do
          expect(has_logging).to be true
        end
      end
    end
  end
end

control 'ecs-tasks-secrets-management' do
  impact 0.8
  title 'Ensure ECS tasks use proper secrets management'
  desc 'ECS tasks should use Secrets Manager or SSM Parameter Store, not environment variables'
  
  aws_ecs_task_definitions.family_names.each do |family_name|
    next unless family_name.include?(environment)
    
    task_def = aws_ecs_task_definition(family: family_name)
    
    describe "Task definition #{family_name}" do
      container_defs = task_def.container_definitions
      no_sensitive_env_vars = container_defs.all? do |container|
        sensitive_keys = ["API_KEY", "SECRET", "PASSWORD", "TOKEN", "AUTH"]
        
        container['environment']&.all? do |env|
          !sensitive_keys.any? { |key| env['name'].upcase.include?(key) }
        end || true
      end
      
      it "should not have sensitive data in environment variables" do
        expect(no_sensitive_env_vars).to be true
      end
      
      uses_secrets = container_defs.any? do |container|
        container['secrets']&.any? || false
      end
      
      it "should use secrets for sensitive information" do
        expect(uses_secrets).to be true
      end
    end
  end
end

control 'ecs-service-discovery' do
  impact 0.7
  title 'Ensure ECS services use service discovery'
  desc 'Service discovery helps with resilience in failover scenarios'
  
  aws_ecs_clusters.cluster_names.each do |cluster_name|
    next unless cluster_name.include?(environment)
    
    aws_ecs_services(cluster: cluster_name).service_names.each do |service_name|
      service = aws_ecs_service(cluster: cluster_name, service: service_name)
      
      describe "ECS service #{service_name} service discovery" do
        it "should use service discovery" do
          expect(service.service_registries.length).to be > 0
        end if service.respond_to?(:service_registries)
      end
    end
  end
end