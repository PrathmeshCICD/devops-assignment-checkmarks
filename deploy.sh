#!/usr/bin/env bash
# =============================================================
#  CxDevOps – Full Stack Installer (Minikube / Linux)
#  Usage:  ./deploy.sh install
#          ./deploy.sh uninstall
# =============================================================
set -euo pipefail

NAMESPACE="devops"
TRAEFIK_NS="traefik"
MINIKUBE_CPUS=4
MINIKUBE_MEMORY=8192
MINIKUBE_DRIVER="docker"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── prerequisite check ───────────────────────────────────────
check_prereqs() {
  info "Checking prerequisites..."
  for cmd in minikube kubectl helm docker terraform; do
    command -v "$cmd" &>/dev/null || die "$cmd is not installed. Please install it first."
  done
  info "All prerequisites found."
}

# ── install ──────────────────────────────────────────────────
install() {
  check_prereqs

  # 1. Start Minikube
  info "Starting Minikube..."
  if minikube status --format='{{.Host}}' 2>/dev/null | grep -q "Running"; then
    warn "Minikube already running – skipping."
  else
    minikube start \
      --driver="${MINIKUBE_DRIVER}" \
      --cpus="${MINIKUBE_CPUS}" \
      --memory="${MINIKUBE_MEMORY}" \
      --addons=metrics-server
  fi

  # 2. Namespaces
  info "Creating namespaces..."
  kubectl create namespace "${NAMESPACE}"  --dry-run=client -o yaml | kubectl apply -f -
  kubectl create namespace "${TRAEFIK_NS}" --dry-run=client -o yaml | kubectl apply -f -

  # 3. Helm repos
  info "Adding Helm repositories..."
  helm repo add bitnami   https://charts.bitnami.com/bitnami    2>/dev/null || true
  helm repo add jenkins   https://charts.jenkins.io             2>/dev/null || true
  helm repo add grafana   https://grafana.github.io/helm-charts 2>/dev/null || true
  helm repo add traefik   https://traefik.github.io/charts      2>/dev/null || true
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
  helm repo update

  # 4. Kubernetes Secret for PostgreSQL (Bonus requirement)
  info "Creating PostgreSQL Kubernetes Secret..."
  kubectl create secret generic postgres-secret \
    --namespace="${NAMESPACE}" \
    --from-literal=postgres-password=CxDevOps2026! \
    --from-literal=password=CxDevOps2026! \
    --dry-run=client -o yaml | kubectl apply -f -

  # 5. Deploy Traefik (Load Balancer + Ingress)
  info "Deploying Traefik..."
  helm upgrade --install traefik traefik/traefik \
    --namespace "${TRAEFIK_NS}" \
    --values helm/traefik-values.yaml \
    --wait --timeout 5m

  # 6. Deploy PostgreSQL with persistent storage
  info "Deploying PostgreSQL..."
  helm upgrade --install postgres bitnami/postgresql \
    --namespace "${NAMESPACE}" \
    --values helm/postgresql-values.yaml \
    --wait --timeout 5m

  # 7. Create DB and table
  info "Initialising PostgreSQL database..."
  kubectl exec -n "${NAMESPACE}" postgres-postgresql-0 -- \
    psql -U postgres -c "CREATE DATABASE devops;" 2>/dev/null || true
  kubectl exec -n "${NAMESPACE}" postgres-postgresql-0 -- \
    psql -U postgres -d devops \
    -c "CREATE TABLE IF NOT EXISTS timestamps (
          id         SERIAL PRIMARY KEY,
          timestamp  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          pod_name   TEXT,
          job_name   TEXT,
          build_num  INTEGER
        );" 2>/dev/null || true

  # 8. Deploy Jenkins (HA)
  info "Deploying Jenkins in HA mode..."
  kubectl apply -f k8s/jenkins-rbac.yaml
  helm upgrade --install jenkins jenkins/jenkins \
    --namespace "${NAMESPACE}" \
    --values helm/jenkins-values.yaml \
    --wait --timeout 10m

  # 9. Deploy Prometheus
  info "Deploying Prometheus..."
  helm upgrade --install prometheus prometheus-community/prometheus \
    --namespace "${NAMESPACE}" \
    --set server.service.type=ClusterIP \
    --wait --timeout 5m

  # 10. Deploy Grafana
  info "Deploying Grafana..."
  helm upgrade --install grafana grafana/grafana \
    --namespace "${NAMESPACE}" \
    --values helm/grafana-values.yaml \
    --wait --timeout 5m

  # 11. Apply K8s manifests
  info "Applying Kubernetes manifests..."
  kubectl apply -f k8s/

  # 12. Terraform – Grafana dashboard
  info "Applying Terraform Grafana dashboard..."
  GRAFANA_PASS=$(kubectl get secret --namespace "${NAMESPACE}" grafana \
    -o jsonpath="{.data.admin-password}" | base64 --decode)
  export TF_VAR_grafana_password="${GRAFANA_PASS}"
  pushd terraform > /dev/null
    terraform init -upgrade
    terraform apply -auto-approve
  popd > /dev/null

  # 13. Print access info
  MINIKUBE_IP=$(minikube ip)
  JENKINS_PASS=$(kubectl get secret --namespace "${NAMESPACE}" jenkins \
    -o jsonpath="{.data.jenkins-admin-password}" | base64 --decode)

  info "========================================================"
  info " Deployment complete!"
  info ""
  info "  Add to /etc/hosts:"
  info "  ${MINIKUBE_IP}  jenkins.devops.local grafana.devops.local traefik.devops.local"
  info ""
  info "  sudo sh -c 'echo \"${MINIKUBE_IP} jenkins.devops.local grafana.devops.local traefik.devops.local\" >> /etc/hosts'"
  info ""
  info "  Jenkins  -> http://jenkins.devops.local  (admin / ${JENKINS_PASS})"
  info "  Grafana  -> http://grafana.devops.local  (admin / ${GRAFANA_PASS})"
  info "  Traefik  -> http://traefik.devops.local"
  info "========================================================"
}

# ── uninstall ────────────────────────────────────────────────
uninstall() {
  check_prereqs
  warn "Uninstalling all components..."

  pushd terraform > /dev/null
    terraform destroy -auto-approve 2>/dev/null || true
  popd > /dev/null

  kubectl delete -f k8s/ 2>/dev/null || true

  helm uninstall grafana    --namespace "${NAMESPACE}"  2>/dev/null || true
  helm uninstall prometheus --namespace "${NAMESPACE}"  2>/dev/null || true
  helm uninstall jenkins    --namespace "${NAMESPACE}"  2>/dev/null || true
  helm uninstall postgres   --namespace "${NAMESPACE}"  2>/dev/null || true
  helm uninstall traefik    --namespace "${TRAEFIK_NS}" 2>/dev/null || true

  kubectl delete secret postgres-secret --namespace "${NAMESPACE}" 2>/dev/null || true
  kubectl delete namespace "${NAMESPACE}"  2>/dev/null || true
  kubectl delete namespace "${TRAEFIK_NS}" 2>/dev/null || true

  warn "Stopping Minikube..."
  minikube stop   2>/dev/null || true
  minikube delete 2>/dev/null || true

  info "Uninstall complete."
}

# ── entrypoint ───────────────────────────────────────────────
case "${1:-}" in
  install)   install   ;;
  uninstall) uninstall ;;
  *)         die "Usage: $0 {install|uninstall}" ;;
esac
