DevOps Assignment
Overview

This project demonstrates a complete DevOps environment deployed on a Kubernetes cluster (Minikube). The environment includes:

Jenkins with dynamic Kubernetes agents

PostgreSQL for data storage

Grafana for monitoring

Prometheus for metrics collection

Traefik as the ingress controller

All components are installed automatically using the deploy.sh Bash script.

Prerequisites

Before deployment, ensure the following tools are installed:

Docker

Minikube

kubectl

Helm

Terraform

Start Minikube:

minikube start
Deployment Instructions

Clone the repository:

git clone <your-repository-url>
cd devops-assignment

Make the deployment script executable and run it:

chmod +x deploy.sh
./deploy.sh install

Update your /etc/hosts file with Minikube IP:

<MINIKUBE_IP> jenkins.devops.local
<MINIKUBE_IP> grafana.devops.local

Access services via your browser:

Jenkins: http://jenkins.devops.local

Grafana: http://grafana.devops.local

To uninstall the environment:

./deploy.sh uninstall
Architecture
                        +-----------------------+
                        |      User Browser      |
                        |                       |
                        | jenkins.devops.local  |
                        | grafana.devops.local  |
                        +----------+------------+
                                   |
                          +--------v--------+
                          |      Traefik     |
                          | Ingress Controller|
                          +--------+--------+
                                   |
            ---------------------------------------------
            |                                           |
     +------v-------+                           +-------v-------+
     |    Jenkins   |                           |    Grafana    |
     |     CI/CD    |                           |  Monitoring   |
     +------+-------+                           +-------+-------+
            |                                           |
            | Creates Dynamic Worker Pods               | Displays Metrics
            |                                           | from Prometheus
     +------v------+                           +-------v-------+
     |  Worker Pod |                           |  Prometheus   |
     | (Inserts    |                           |               |
     |  Timestamps)|                           +---------------+
     +-------------+
            |
     +------v------+
     | PostgreSQL  |
     |  Database   |
     +-------------+
Components

Kubernetes Cluster (Minikube) – Hosts all services

Traefik – Ingress controller & load balancer

Jenkins – CI/CD automation with dynamic Kubernetes worker pods

PostgreSQL – Database storing timestamp records

PostgreSQL Exporter – Exposes database metrics to Prometheus

Prometheus – Metrics collection

Grafana – Monitoring dashboards

Terraform – Automates Grafana dashboard provisioning

Services Access
Service	URL	Default Credentials
Jenkins	http://jenkins.devops.local
	admin / password
Grafana	http://grafana.devops.local
	admin / admin
Traefik Dashboard	Via LoadBalancer IP	-
Jenkins Pipeline

Runs every 5 minutes

Creates dynamic Kubernetes worker pods

Worker pods insert timestamps into PostgreSQL

Job definition: jenkins/jobdsl.groovy

Monitoring

PostgreSQL metrics are scraped by Prometheus

Grafana dashboards visualize:

CPU usage

Memory usage

Query throughput

Database connections

Dashboards are automatically provisioned using Terraform (terraform/dashboards)

Project Structure
devops-assignment
│
├── deploy.sh                 # Deployment script
├── README.md
│
├── jenkins
│   └── Jenkinsfile           # CI/CD pipeline
│
├── k8s                       # Kubernetes manifests
│   ├── grafana-ingress.yaml
│   ├── jenkins-ingress.yaml
│   ├── postgres-exporter-deployment.yaml
│   ├── postgres-exporter-secret.yaml
│   ├── postgres-exporter-service.yaml
│   └── postgres-servicemonitor.yaml
│
└── terraform                  # Grafana dashboards provisioning
    ├── provider.tf
    └── dashboards
        ├── postgres.json
        └── postgres_dashboard.tf
Verification

Check pods:

kubectl get pods

Check services:

kubectl get svc

Check ingress:

kubectl get ingress
Uninstall

Remove the environment completely:

./deploy.sh uninstall
Technologies Used

Kubernetes (Minikube)

Jenkins

PostgreSQL

Grafana

Traefik

Terraform

Helm

Bash
