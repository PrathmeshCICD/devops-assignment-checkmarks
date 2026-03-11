jenkins/jobdsl.groovy
// Seed job DSL - creates the timestamp-recorder pipeline

pipelineJob('timestamp-recorder') {
    description('Records current timestamp to PostgreSQL every 5 minutes via dynamic K8s worker pod')

    triggers {
        cron('H/5 * * * *')
    }

    definition {
        cpsScmFlowDefinition {
            scm {
                gitSCM {
                    userRemoteConfigs {
                        userRemoteConfig {
                            url('https://github.com/PrathmeshCICD/devops-assignment-checkmarks.git')
                        }
                    }
                    branches {
                        branchSpec { name('*/main') }
                    }
                }
            }
            scriptPath('jenkins/Jenkinsfile')
        }
    }
}
