# DevOps Assignment

## Overview

This project demonstrates a complete DevOps environment deployed on a Kubernetes cluster using **Minikube**. The environment includes:

- **Jenkins** with dynamic Kubernetes agents
- **PostgreSQL** for data storage
- **Grafana** for monitoring
- **Prometheus** for metrics collection
- **Traefik** as the ingress controller

All components are installed automatically using a single Bash script (`deploy.sh`).

---

## Prerequisites

Install the following tools before deployment:

- Docker
- Minikube
- kubectl
- Helm
- Terraform

---

## Deployment

### 1. Clone the Repository

```bash
git clone https://github.com/PrathmeshCICD/devops-assignment-checkmarks.git
cd devops-assignment-checkmarks
```

### 2. Run the Deployment Script

```bash
chmod +x deploy.sh
./deploy.sh install
```

### 3. Update /etc/hosts

Get your Minikube IP:

```bash
minikube ip
```

Add this line to `/etc/hosts` (replace `<MINIKUBE_IP>` with the actual IP):

```
<MINIKUBE_IP>  jenkins.devops.local grafana.devops.local traefik.devops.local
```

Or run this one-liner:

```bash
sudo sh -c "echo \"$(minikube ip) jenkins.devops.local grafana.devops.local traefik.devops.local\" >> /etc/hosts"
```

### 4. Access Services

| Service           | URL                            | Credentials       |
|-------------------|--------------------------------|-------------------|
| Jenkins           | http://jenkins.devops.local    | admin / (printed by script) |
| Grafana           | http://grafana.devops.local    | admin / (printed by script) |
| Traefik Dashboard | http://traefik.devops.local    | -                 |

### 5. Uninstall

```bash
./deploy.sh uninstall
```

---

## Architecture

```
                        +-----------------------+
                        |      User Browser      |
                        |                       |
                        | jenkins.devops.local  |
                        | grafana.devops.local  |
                        +----------+------------+
                                   |
                          +--------v--------+
                          |     Traefik     |
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
            |                                           |
     +------v------+                           +-------v-------+
     |  Worker Pod |                           |  Prometheus   |
     | (Inserts    |                           +-------+-------+
     |  Timestamps)|                                   |
     +------+------+                           +-------v-------+
            |                                  | PG Exporter   |
            | INSERT timestamp                 +---------------+
            |
     +------v------+
     | PostgreSQL  |
     |  Database   |
     +-------------+
```

---

## Components

| Component             | Description                                          |
|-----------------------|------------------------------------------------------|
| Kubernetes (Minikube) | Hosts all services                                   |
| Traefik               | Ingress controller and load balancer                 |
| Jenkins               | CI/CD with dynamic Kubernetes worker pods            |
| PostgreSQL            | Database storing timestamp records                   |
| PostgreSQL Exporter   | Exposes DB metrics to Prometheus                     |
| Prometheus            | Scrapes and stores metrics                           |
| Grafana               | Visualizes metrics via dashboards                    |
| Terraform             | Provisions Grafana datasource and dashboard          |

---

## Project Structure

```
devops-assignment-checkmarks/
│
├── deploy.sh                              # Single-command install / uninstall
├── README.md
│
├── helm/
│   ├── grafana-values.yaml
│   ├── jenkins-values.yaml
│   ├── postgresql-values.yaml
│   └── traefik-values.yaml
│
├── jenkins/
│   ├── Jenkinsfile                        # Pipeline: insert timestamp to PostgreSQL
│   └── jobdsl.groovy                      # Seed job DSL definition
│
├── k8s/
│   ├── ingressroutes.yaml                 # Traefik IngressRoutes for all services
│   ├── jenkins-rbac.yaml                  # ServiceAccount + ClusterRole for Jenkins
│   ├── postgres-exporter-deployment.yaml  # PostgreSQL Exporter deployment
│   ├── postgres-exporter-service.yaml     # Exporter ClusterIP service
│   └── postgres-servicemonitor.yaml       # Prometheus ServiceMonitor
│
└── terraform/
    ├── provider.tf                        # Grafana Terraform provider
    ├── variables.tf                       # Input variables
    └── main.tf                            # Grafana datasource + dashboard
```

---

## Jenkins Pipeline

The pipeline (`jenkins/Jenkinsfile`):

1. Runs on a schedule every **5 minutes** (`H/5 * * * *`)
2. Spins up a **dynamic Kubernetes worker pod** with two containers:
   - `jnlp` – Jenkins agent
   - `postgres-client` – runs `psql` commands
3. Creates the `timestamps` table if it does not exist
4. Inserts the current timestamp, pod name, job name, and build number
5. Prints the last 5 records to verify the insert

### Verify Pipeline Output

```bash
kubectl get pods -n devops
```

You should see short-lived `kube-worker-*` pods appear every 5 minutes.

---

## Monitoring

PostgreSQL metrics are exposed by the **postgres-exporter** sidecar and scraped by **Prometheus**.

Grafana dashboard (provisioned by Terraform) displays:

- Timestamps recorded in the last 1 hour
- Timestamps inserted over time (time series)
- Database size (MB)
- Active DB connections
- Total timestamp records
- Cache hit ratio (%)
- DB throughput (commits and rollbacks)

---

## Secrets Management

Secrets are **never stored in Git**. The `deploy.sh` script creates them at deploy time:

```bash
# PostgreSQL password
kubectl create secret generic postgres-secret \
  --from-literal=postgres-password=DevOps2026!

# PostgreSQL Exporter DSN
kubectl create secret generic postgres-exporter-secret \
  --from-literal=DATA_SOURCE_NAME="postgres://postgres:DevOps2026!@postgres-postgresql.devops.svc.cluster.local:5432/devops?sslmode=disable"
```

---

## Verification

```bash
# Check all pods are running
kubectl get pods -n devops

# Check services
kubectl get svc -n devops

# Check ingress routes
kubectl get ingressroute -n devops

# Check Prometheus targets
kubectl port-forward svc/prometheus-server 9090:80 -n devops
# Then open http://localhost:9090/targets
```

---

## Uninstall

```bash
./deploy.sh uninstall
```

This removes all Helm releases, Kubernetes namespaces, secrets, and the Minikube cluster.

---

## Technologies Used

- Kubernetes (Minikube)
- Jenkins
- PostgreSQL 15
- Grafana
- Prometheus
- Traefik
- Terraform
- Helm
- Bash
