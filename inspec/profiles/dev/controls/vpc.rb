# encoding: utf-8
# copyright: Your Organization

title 'VPC Configuration Checks'

vpc_id = input('vpc_id')

control 'vpc-flow-logs-enabled' do
  impact 0.7
  title 'Ensure VPC Flow Logs are enabled'
  desc 'VPC Flow Logs provide network traffic visibility, which is essential for DR testing and security analysis'
  
  describe aws_vpc(vpc_id: vpc_id) do
    it { should exist }
    it { should have_flow_log }
  end
end

control 'vpc-subnets-multiple-azs' do
  impact 0.8
  title 'Ensure VPC has subnets spanning multiple availability zones'
  desc 'Multiple AZ subnets are required for high availability and disaster recovery'
  
  az_count = aws_subnets.where(vpc_id: vpc_id).availability_zones.count
  
  describe 'Number of availability zones' do
    subject { az_count }
    it { should be >= 2 }
  end
end

control 'vpc-network-acls-restrict-traffic' do
  impact 0.6
  title 'Ensure Network ACLs restrict traffic appropriately'
  desc 'Network ACLs should be configured to restrict traffic as per security requirements'
  
  aws_subnets.where(vpc_id: vpc_id).subnet_ids.each do |subnet_id|
    describe aws_network_acl(subnet_id: subnet_id) do
      it { should exist }
      its('inbound_rules.count') { should be > 0 }
      its('outbound_rules.count') { should be > 0 }
    end
  end
end

control 'vpc-igw-restricted' do
  impact 0.7
  title 'Ensure Internet Gateway access is limited'
  desc 'Public subnets should be limited and controlled'
  
  public_subnets = aws_subnets.where(vpc_id: vpc_id).where { 
    subnet = it
    routes = aws_subnet(subnet_id: subnet.subnet_id).route_table
    routes.routes.any? { |r| r.gateway_id =~ /^igw-/ }
  }.subnet_ids
  
  describe 'Number of public subnets' do
    subject { public_subnets.count }
    it { should be <= 2 }
  end
end

control 'vpc-security-groups-restrict-traffic' do
  impact 0.8
  title 'Ensure Security Groups restrict traffic appropriately'
  desc 'Security groups should not allow unrestricted access'
  
  aws_security_groups.where(vpc_id: vpc_id).group_ids.each do |sg_id|
    describe aws_security_group(id: sg_id) do
      it { should exist }
      it { should_not allow_in(port: 22, ipv4_range: '0.0.0.0/0') }
      it { should_not allow_in(port: 3389, ipv4_range: '0.0.0.0/0') }
    end
  end
end

control 'vpc-peering-connections-encrypted' do
  impact 0.7
  title 'Ensure VPC peering connections are properly secured'
  desc 'VPC peering connections should be properly secured and documented'

  aws_vpc_peering_connections.where(accepter_vpc_id: vpc_id).or(aws_vpc_peering_connections.where(requester_vpc_id: vpc_id)).connection_ids.each do |pcx_id|
    describe aws_vpc_peering_connection(vpc_peering_connection_id: pcx_id) do
      it { should exist }
      its('status') { should eq 'active' }
      it { should have_tag('Name') }
      it { should have_tag('Purpose') }
    end
  end
end