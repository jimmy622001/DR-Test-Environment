```mermaid
flowchart TB
    start([Start DR Test]) --> plan[Plan Test]
    plan --> env[Set Up Test Environment]
    
    env --> baseline[Establish Baseline Metrics]
    baseline --> execute[Execute Test Scenario]
    
    execute --> monitor[Monitor & Observe]
    monitor --> decision{Success?}
    
    decision -- Yes --> document[Document Results]
    decision -- No --> remediate[Remediate Issues]
    remediate --> retest[Re-Test]
    retest --> monitor
    
    document --> analyze[Analyze Results]
    analyze --> lessons[Document Lessons]
    lessons --> report[Generate Report]
    report --> review[Review Meeting]
    review --> update[Update Playbooks]
    update --> end([End])
    
    subgraph "Pre-Test Phase"
        plan --> notify[Notify Stakeholders]
        notify --> criteria[Define Success Criteria]
        criteria --> env
    end
    
    subgraph "Test Execution Phase"
        baseline --> backup[Create Backup]
        backup --> execute
        execute --> track[Track Recovery Time]
    end
    
    subgraph "Analysis Phase"
        analyze --> compare[Compare Against Baseline]
        compare --> validate[Validate Success Criteria]
    end
    
    %% Specialized Test Types
    class resilience,security,performance tests
    
    baseline --> resilience[Resilience Test]
    baseline --> security[Security Test] 
    baseline --> performance[Performance Test]
    
    resilience --> monitor
    security --> monitor
    performance --> monitor
    
    resilience:::resilienceTest
    security:::securityTest
    performance:::performanceTest
    
    classDef resilienceTest fill:#f9f,stroke:#333,stroke-width:2px
    classDef securityTest fill:#bbf,stroke:#333,stroke-width:2px
    classDef performanceTest fill:#bfb,stroke:#333,stroke-width:2px
```