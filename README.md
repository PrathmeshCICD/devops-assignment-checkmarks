# DevOps Assignment

## Overview

This project demonstrates a complete DevOps environment deployed on a Kubernetes cluster using **Minikube**. The environment includes **Jenkins with dynamic Kubernetes agents, PostgreSQL for data storage, Grafana for monitoring, Prometheus for metrics collection, and Traefik as the ingress controller**.

All components are installed automatically using a **single Bash deployment script** (`deploy.sh`).

---

## Prerequisites
- Docker
- kubectl
- Helm
- Minikube
- Terraform

## Deployment
1. Clone the repository.
2. Run `./deploy.sh install` to deploy all components.
3. Update `/etc/hosts` with Minikube IP for `jenkins.devops.local` and `grafana.devops.local`.
4. Access services via Traefik ingress.
5. Run `./deploy.sh uninstall` to clean up.

---

# Architecture

The solution contains the following components:

* **Kubernetes Cluster (Minikube)**
* **Traefik** – Ingress Controller and Load Balancer
* **Jenkins** – CI/CD automation with dynamic Kubernetes worker pods
* **PostgreSQL** – Database storing timestamp records
* **PostgreSQL Exporter** – Exposes database metrics
* **Prometheus** – Metrics collection
* **Grafana** – Monitoring dashboards with PostgreSQL metrics
* **Terraform** – Automated Grafana dashboard provisioning

---

# Architecture Diagram

```
                        +-----------------------+
                        |       User Browser     |
                        |                       |
                        |  jenkins.devops.local |
                        |  grafana.devops.local |
                        +----------+------------+
                                   |
                          +--------v--------+
                          |     Traefik     |
                          | Ingress Controller |
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
     | Database    |
     +-------------+
```

---

## Services Access
- **Jenkins**: http://jenkins.devops.local (admin/password)
- **Grafana**: http://grafana.devops.local (admin/password)
- **Traefik Dashboard**: Accessible via LoadBalancer IP

## Jenkins DSL Job
The `jenkins/jobdsl.groovy` defines a job that runs every 5 minutes, launching K8s worker pods to insert timestamps into PostgreSQL.

## Monitoring
- PostgreSQL metrics are scraped by Prometheus via the exporter.
- Grafana dashboard is provisioned by Terraform to visualize CPU, memory, and throughput metrics.
     |  Pipeline   |
     +------+------+
            |
            | Insert Timestamp
            |
     +------v------+
     | PostgreSQL  |
     |  Database   |
     +------+------+
            |
            | Metrics
            |
     +------v------------------+
     | PostgreSQL Exporter     |
     +-------------------------+
```

---

# Workflow

1. Jenkins runs a scheduled job every **5 minutes**
2. Jenkins creates **dynamic Kubernetes worker pods**
3. Worker pods insert the **current timestamp into PostgreSQL**
4. PostgreSQL metrics are exposed using **Postgres Exporter**
5. Grafana dashboards visualize database metrics

---

# Project Structure

```
devops-assignment
│
├── deploy.sh
├── README.md
│
├── jenkins
│   └── Jenkinsfile
│
├── k8s
│   ├── grafana-ingress.yaml
│   ├── jenkins-ingress.yaml
│   ├── postgres-exporter-deployment.yaml
│   ├── postgres-exporter-secret.yaml
│   ├── postgres-exporter-service.yaml
│   └── postgres-servicemonitor.yaml
│
└── terraform
    ├── provider.tf
    └── dashboards
        ├── postgres.json
        └── postgres_dashboard.tf
```

---

# Prerequisites

Install the following tools:

* Docker
* Minikube
* kubectl
* Helm
* Terraform

Start Minikube:

```
minikube start
```

---

# Installation

## 1. Clone the Repository

```
git clone <your-repository-url>
cd devops-assignment
```

## 2. Run the Deployment Script

```
chmod +x deploy.sh
./deploy.sh install
```

The script automatically installs:

* Traefik Ingress Controller
* PostgreSQL
* Jenkins
* Grafana
* Kubernetes manifests
* Grafana dashboards using Terraform

---

# Accessing Services

## Get the Minikube IP

Run:

```
minikube ip
```

Example output:

```
<MINIKUBE_IP>
```

## Update Hosts File

Add the following entries to your `/etc/hosts` file using your Minikube IP:

```
<MINIKUBE_IP external > jenkins.devops.local
<MINIKUBE_IP external > grafana.devops.local
```

Example:

```
192.168.X.X jenkins.devops local
192.168.X.X grafana.devops local
```

---

# Open in Browser

Jenkins

```
http://jenkins.devops.local
```

Grafana

```
http://grafana.devops.local
```

Default Grafana login:

```
username: admin
password: admin
```

---

# Verify Deployment

Check running pods:

```
kubectl get pods
```

Check services:

```
kubectl get svc
```

Check ingress:

```
kubectl get ingress
```

---

# Jenkins Pipeline

The Jenkins pipeline:

* Runs every **5 minutes**
* Creates **dynamic Kubernetes worker pods**
* Inserts **timestamp records into PostgreSQL**

---

# Monitoring

Grafana dashboards visualize PostgreSQL metrics:

* CPU usage
* Memory usage
* Query throughput
* Database connections

Dashboards are automatically provisioned using **Terraform**.

---

# Uninstall

To remove the entire environment:

```
./deploy.sh uninstall
```

---

# Technologies Used

* Kubernetes (Minikube)
* Jenkins
* PostgreSQL
* Grafana
* Traefik
* Terraform
* Helm
* Bash
