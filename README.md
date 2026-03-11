# DevOps Assignment — Kubernetes Stack with Jenkins, PostgreSQL, Grafana & Traefik

## Overview

Full DevOps environment deployed on a local Kubernetes cluster (Minikube) using a **single bash script**.

| Component | Description |
|---|---|
| **Minikube** | Local Kubernetes cluster |
| **Traefik** | Ingress controller + Load Balancer (no port forwarding) |
| **Jenkins** | CI/CD — dynamic Kubernetes worker pods, runs every 5 mins |
| **PostgreSQL** | Database with persistent storage + K8s Secrets |
| **Prometheus** | Metrics collection + PostgreSQL exporter |
| **Grafana** | Monitoring dashboards (provisioned via Terraform) |

---

## Architecture

```
  Browser / curl
       │
       ▼
┌─────────────────────┐
│       Traefik        │  ← LoadBalancer Ingress (127.0.0.1 via minikube tunnel)
│  (traefik namespace) │
└──────────┬──────────┘
           │  Routes by hostname
     ┌─────┼──────────────┐
     ▼     ▼              ▼
 Jenkins  Grafana     Prometheus
     │       │
     │       └── Datasource: Prometheus
     │                    ▲
     │                    │ scrapes
     │             PG Exporter
     │                    │
     ▼                    ▼
 K8s Worker Pod ──► PostgreSQL DB
 (postgres-client)   (timestamps table)
```

---

## Prerequisites

Install these tools before deploying:

```bash
# Docker
sudo apt install docker.io

# Minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install kubectl /usr/local/bin/kubectl

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Terraform
sudo apt install terraform
```

---

## Quick Start

```bash
git clone https://github.com/PrathmeshCICD/devops-assignment-checkmarks.git
cd devops-assignment-checkmarks
chmod +x deploy.sh
./deploy.sh install
```

> ⚠️ The script will prompt for your **sudo password** once (for `minikube tunnel` and `/etc/hosts`). Keep the terminal open — tunnel must stay running.

---

## Service Access

After install completes, access all services via Traefik ingress (no port forwarding):

| Service | URL | Credentials |
|---|---|---|
| **Jenkins** | http://jenkins.devops.local | `admin` / `CxJenkins2026!` |
| **Grafana** | http://grafana.devops.local | `admin` / `drow` |
| **Traefik Dashboard** | http://traefik.devops.local | — |
| **Prometheus** | http://prometheus.devops.local | — |

> All hostnames are automatically added to `/etc/hosts` by the install script.

---

## Deploy Script Commands

```bash
./deploy.sh install    # Deploy full stack (Traefik, PostgreSQL, Jenkins, Prometheus, Grafana)
./deploy.sh uninstall  # Tear down everything including Minikube
./deploy.sh status     # Show pod status, helm releases, DB records
./deploy.sh pipeline   # Manually trigger Jenkins pipeline + show DB records
./deploy.sh verify     # Full health check: pods, endpoints, DB, Grafana metrics
```

---

## Jenkins Pipeline

The pipeline (`jenkins/Jenkinsfile`):

- Runs **automatically every 5 minutes** via cron (`H/5 * * * *`)
- Spins up a **dynamic Kubernetes worker pod** with:
  - `jnlp` — Jenkins agent container
  - `postgres-client` — PostgreSQL 15 Alpine container
- Reads DB password from `postgres-secret` Kubernetes Secret
- Connects to PostgreSQL via internal service DNS
- Inserts current timestamp, pod name, job name, build number
- Verifies the insert by printing last 5 records

### Verify Pipeline is Running

```bash
# Watch worker pods spin up every 5 mins
kubectl get pods -n devops -w

# Check DB records directly
kubectl exec -n devops postgres-postgresql-0 -- \
  env PGPASSWORD=CxDevOps2026! psql -U postgres -d devops \
  -c "SELECT * FROM timestamps ORDER BY id DESC LIMIT 10;"
```

---

## Grafana Dashboards

Two dashboards are available:

1. **PostgreSQL Metrics** (provisioned by Terraform via `terraform/postgres.json`)
   - DB size, active connections, cache hit ratio, throughput

2. **DevOps Pipeline Dashboard** (created by deploy script)
   - Services up, Pod CPU/Memory, Jenkins build status, Node CPU

### Access Grafana

1. Open http://grafana.devops.local
2. Login: `admin` / `drow`
3. Go to **Dashboards** → select dashboard

---

## Secrets Management

Secrets are **never hardcoded in Git**. Created at deploy time by `deploy.sh`:

```bash
# PostgreSQL password
kubectl create secret generic postgres-secret \
  --from-literal=postgres-password=CxDevOps2026!

# PostgreSQL Exporter DSN (with real password injected)
kubectl create secret generic postgres-exporter-secret \
  --from-literal=DATA_SOURCE_NAME="postgres://postgres:CxDevOps2026!@postgres-postgresql.devops.svc.cluster.local:5432/devops?sslmode=disable"
```

---

## Project Structure

```
devops-assignment-checkmarks/
│
├── deploy.sh                              # Single-command install/uninstall/verify/pipeline
├── README.md
├── .gitignore
│
├── helm/
│   ├── traefik-values.yaml                # Traefik LoadBalancer + Ingress config
│   ├── jenkins-values.yaml                # Jenkins HA + K8s cloud + worker pod templates
│   ├── postgresql-values.yaml             # PostgreSQL with persistent storage + secret ref
│   └── grafana-values.yaml                # Grafana with Traefik ingress
│
├── jenkins/
│   ├── Jenkinsfile                        # Pipeline: K8s worker pod → insert timestamp to PostgreSQL
│   └── jobdsl.groovy                      # Seed job DSL definition
│
├── k8s/
│   ├── jenkins-rbac.yaml                  # ServiceAccount + ClusterRole for Jenkins
│   ├── jenkins-ingress.yaml               # Traefik ingress for Jenkins
│   ├── grafana-ingress.yaml               # Traefik ingress for Grafana
│   ├── prometheus-ingress.yaml            # Traefik ingress for Prometheus
│   ├── postgres-exporter-deployment.yaml  # PostgreSQL Exporter deployment
│   ├── postgres-exporter-service.yaml     # Exporter ClusterIP service
│   ├── postgres-exporter-secret.yaml      # Secret template (real secret created by deploy.sh)
│   └── postgres-servicemonitor.yaml       # Prometheus ServiceMonitor for PG Exporter
│
└── terraform/
    ├── provider.tf                        # Grafana Terraform provider config
    ├── variables.tf                       # grafana_url + grafana_password variables
    ├── main.tf                            # Grafana dashboard resource
    └── postgres.json                      # Grafana dashboard JSON definition
```

---

## Monitoring Stack

```
PostgreSQL
    └── postgres-exporter (port 9187)
            └── ServiceMonitor → Prometheus scrapes every 15s
                    └── Grafana datasource → Dashboard panels
```

Metrics available in Grafana:
- `pg_stat_activity_count` — active connections
- `pg_database_size_bytes` — database size
- `pg_stat_bgwriter_*` — cache hit ratio, throughput
- `container_cpu_usage_seconds_total` — pod CPU
- `container_memory_usage_bytes` — pod memory

---

## Uninstall

```bash
./deploy.sh uninstall
```

Removes: all Helm releases, namespaces, secrets, `/etc/hosts` entries, Minikube cluster.

---

## Technologies

- Kubernetes (Minikube v1.35)
- Traefik v3 (Helm)
- Jenkins (Helm, HA mode, dynamic K8s agents)
- PostgreSQL 15 (Bitnami Helm chart)
- Prometheus (prometheus-community Helm chart)
- Grafana (Helm + Terraform provisioning)
- Terraform (Grafana provider ~1.39)
- Helm 3
- Bash

---

## ⏱️ Installation Time Estimates

The `./deploy.sh install` command runs fully automatically but each component takes time to pull images and start. **Do not interrupt the script.**

| Step | Component | Typical Wait |
|---|---|---|
| Step 1 | Minikube start | 2–4 min |
| Step 5 | Traefik | 1–3 min (image cached after first run) |
| Step 6 | Minikube tunnel + hosts | 30 sec (enter sudo password when prompted) |
| Step 7 | PostgreSQL | 2–4 min |
| Step 9 | Jenkins | 5–10 min (large image, HA mode) |
| Step 10 | Prometheus | 2–4 min |
| Step 11 | Grafana | 2–3 min |
| Step 14 | Terraform | 30 sec (requires Grafana to be reachable) |
| Step 15–18 | Jenkins pipeline + first run | 2–3 min |
| **Total** | **Full fresh install** | **~25–40 min** |

> ⚠️ **Jenkins takes the longest** (~5–10 min) because it pulls a large image and starts 2 replicas (HA mode).

> ⚠️ **Keep `minikube tunnel` running** in a separate terminal if the script fails to start it automatically. The tunnel is required for all services to be accessible via Traefik ingress.

> ℹ️ On **second run** (images already cached), total time drops to ~10–15 min.
