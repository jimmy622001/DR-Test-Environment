```mermaid
graph TB
    subgraph "Primary Region (us-east-1)"
        subgraph "VPC"
            subgraph "Availability Zone 1"
                web1[Web Server 1]
                app1[App Server 1]
                
                subgraph "RDS Multi-AZ"
                    db_primary[RDS Primary]
                end
            end
            
            subgraph "Availability Zone 2"
                web2[Web Server 2]
                app2[App Server 2]
                
                subgraph "RDS Multi-AZ 2"
                    db_standby[RDS Standby]
                end
            end
            
            ALB[Application Load Balancer]
            s3_primary[S3 Bucket]
            dynamodb_primary[DynamoDB Table]
            
            ALB --> web1
            ALB --> web2
            web1 --> app1
            web2 --> app2
            app1 --> db_primary
            app1 --> dynamodb_primary
            app2 --> db_primary
            app2 --> dynamodb_primary
            app1 --> s3_primary
            app2 --> s3_primary
            
            db_primary -.Replication.-> db_standby
        end
    end
    
    subgraph "DR Region (us-west-2)"
        subgraph "DR VPC"
            subgraph "DR Availability Zone 1"
                dr_web1[Web Server 1]
                dr_app1[App Server 1]
                
                subgraph "DR RDS Multi-AZ"
                    dr_db_primary[RDS Primary]
                end
            end
            
            subgraph "DR Availability Zone 2"
                dr_web2[Web Server 2]
                dr_app2[App Server 2]
                
                subgraph "DR RDS Multi-AZ 2"
                    dr_db_standby[RDS Standby]
                end
            end
            
            dr_ALB[Application Load Balancer]
            s3_dr[S3 Bucket]
            dynamodb_dr[DynamoDB Table]
            
            dr_ALB --> dr_web1
            dr_ALB --> dr_web2
            dr_web1 --> dr_app1
            dr_web2 --> dr_app2
            dr_app1 --> dr_db_primary
            dr_app1 --> dynamodb_dr
            dr_app2 --> dr_db_primary
            dr_app2 --> dynamodb_dr
            dr_app1 --> s3_dr
            dr_app2 --> s3_dr
            
            dr_db_primary -.Replication.-> dr_db_standby
        end
    end
    
    %% Cross-Region Connections
    route53[Route 53]
    route53 --> ALB
    route53 -.Failover.-> dr_ALB
    
    db_primary -.Cross-Region Replication.-> dr_db_primary
    s3_primary -.Cross-Region Replication.-> s3_dr
    dynamodb_primary -.Global Table.-> dynamodb_dr
    
    %% Testing Components
    subgraph "Testing Infrastructure"
        inspec[InSpec Tests]
        fis[FIS Experiments]
        cloudwatch[CloudWatch]
        lambda_tests[Test Lambdas]
        
        inspec --> Primary Region
        inspec --> DR Region
        fis --> Primary Region
        fis --> DR Region
        cloudwatch --> Primary Region
        cloudwatch --> DR Region
        lambda_tests --> route53
    end
    
    %% Style Classes
    classDef primary fill:#f9f,stroke:#333,stroke-width:1px
    classDef dr fill:#bbf,stroke:#333,stroke-width:1px
    classDef testing fill:#bfb,stroke:#333,stroke-width:1px
    classDef global fill:#fffbc0,stroke:#333,stroke-width:1px
    
    class web1,web2,app1,app2,db_primary,db_standby,ALB,s3_primary,dynamodb_primary primary
    class dr_web1,dr_web2,dr_app1,dr_app2,dr_db_primary,dr_db_standby,dr_ALB,s3_dr,dynamodb_dr dr
    class inspec,fis,cloudwatch,lambda_tests testing
    class route53 global
```