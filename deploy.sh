#!/usr/bin/env bash
# =============================================================
#  MASTER DEPLOY SCRIPT - Full DevOps Stack
#
#  Usage:  ./deploy.sh install
#          ./deploy.sh uninstall
#          ./deploy.sh status
#          ./deploy.sh pipeline   (trigger pipeline manually)
#          ./deploy.sh verify     (check all services + db + metrics)
# =============================================================
set -euo pipefail

NAMESPACE="devops"
TRAEFIK_NS="traefik"
MINIKUBE_CPUS=4
MINIKUBE_MEMORY=8192
MINIKUBE_DRIVER="docker"
JENKINS_USER="admin"
GRAFANA_USER="admin"
PG_PASSWORD="CxDevOps2026!"
JENKINS_PASSWORD="CxJenkins2026!"
API_TOKEN_FILE="/tmp/jenkins-api-token.txt"
COOKIE_FILE="/tmp/jenkins-cookies.txt"
CRUMB_FILE="/tmp/jenkins-crumb.json"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()     { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
ok()      { echo -e "${GREEN}  ✅ $*${NC}"; }
fail()    { echo -e "${RED}  ❌ $*${NC}"; }
section() { echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${BLUE}  $*${NC}"; echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }

# ── prerequisite check ────────────────────────────────────────
check_prereqs() {
  info "Checking prerequisites..."
  for cmd in minikube kubectl helm docker terraform curl python3; do
    command -v "$cmd" &>/dev/null || die "$cmd is not installed."
  done
  info "All prerequisites found."
}

# ── helm deploy with retry ────────────────────────────────────
helm_deploy() {
  local release=$1; local chart=$2; local ns=$3; local timeout=${4:-8m}
  shift 4
  local attempt=1
  while [[ $attempt -le 3 ]]; do
    info "Deploying ${release} (attempt ${attempt}/3)..."
    if helm upgrade --install "${release}" "${chart}" \
        --namespace "${ns}" \
        --timeout "${timeout}" \
        --atomic \
        --cleanup-on-fail \
        "$@"; then
      ok "${release} deployed successfully."
      return 0
    fi
    warn "Attempt ${attempt} failed for ${release}."
    attempt=$((attempt + 1))
    [[ $attempt -le 3 ]] && { warn "Retrying in 15 seconds..."; sleep 15; }
  done
  die "Failed to deploy ${release} after 3 attempts."
}

# ── fix stuck helm release ────────────────────────────────────
fix_stuck_release() {
  local release=$1; local ns=$2
  local status
  status=$(helm status "${release}" -n "${ns}" 2>/dev/null | grep STATUS | awk '{print $2}' || echo "not-found")
  if [[ "${status}" == "failed" || "${status}" == "pending-upgrade" || "${status}" == "pending-install" ]]; then
    warn "Release '${release}' is in state '${status}' – uninstalling..."
    helm uninstall "${release}" -n "${ns}" 2>/dev/null || true
    sleep 5
  fi
}

# ── deploy traefik (no --atomic to avoid timeout) ────────────
deploy_traefik() {
  fix_stuck_release traefik "${TRAEFIK_NS}"
  info "Deploying Traefik (no-wait mode)..."
  helm upgrade --install traefik traefik/traefik \
    --namespace "${TRAEFIK_NS}" \
    --values helm/traefik-values.yaml \
    --timeout 10m \
    --cleanup-on-fail 2>/dev/null || true
  info "Waiting for Traefik pod to be ready..."
  kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=traefik \
    -n "${TRAEFIK_NS}" --timeout=5m 2>/dev/null || true
  ok "Traefik deployed."
}

# ── start minikube tunnel ─────────────────────────────────────
start_tunnel() {
  sudo pkill -f "minikube tunnel" 2>/dev/null || true
  sleep 3
  info "Starting minikube tunnel..."
  nohup minikube tunnel > /tmp/minikube-tunnel.log 2>&1 &
  echo $! > /tmp/minikube-tunnel.pid
  ok "Tunnel started (PID: $(cat /tmp/minikube-tunnel.pid))"
  sleep 15
}

# ── configure /etc/hosts ──────────────────────────────────────
configure_hosts() {
  local ip=$1
  sudo sed -i '/devops.local/d' /etc/hosts 2>/dev/null || true
  echo "${ip}  jenkins.devops.local grafana.devops.local traefik.devops.local prometheus.devops.local" | \
    sudo tee -a /etc/hosts > /dev/null
  ok "Hosts configured: ${ip}"
}

# ── get external ip once ──────────────────────────────────────
get_external_ip() {
  local attempts=0
  local ext_ip=""
  info "Waiting for Traefik EXTERNAL-IP..."
  while [[ $attempts -lt 24 ]]; do
    ext_ip=$(kubectl get svc traefik -n "${TRAEFIK_NS}" \
      -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [[ -n "${ext_ip}" && "${ext_ip}" != "null" ]]; then
      echo "${ext_ip}"
      return 0
    fi
    attempts=$((attempts + 1))
    echo -n "."
    sleep 5
  done
  echo ""
  warn "Could not get EXTERNAL-IP, defaulting to 127.0.0.1"
  echo "127.0.0.1"
}

# ── wait for jenkins ──────────────────────────────────────────
wait_for_jenkins() {
  info "Waiting for Jenkins to be ready..."
  local attempts=0
  while [[ $attempts -lt 30 ]]; do
    if curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 \
        -u "${JENKINS_USER}:${JENKINS_PASSWORD}" \
        "http://jenkins.devops.local/api/json" 2>/dev/null | grep -q "200"; then
      ok "Jenkins is ready!"
      return 0
    fi
    attempts=$((attempts + 1))
    echo -n "."
    sleep 10
  done
  echo ""
  warn "Jenkins not ready in time, continuing..."
}

# ── get jenkins api token ─────────────────────────────────────
get_jenkins_token() {
  rm -f "${API_TOKEN_FILE}" "${COOKIE_FILE}" "${CRUMB_FILE}"
  local crumb_json crumb_field crumb_value token
  crumb_json=$(curl -s -u "${JENKINS_USER}:${JENKINS_PASSWORD}"     -c "${COOKIE_FILE}"     "http://jenkins.devops.local/crumbIssuer/api/json")
  crumb_field=$(echo "${crumb_json}" | python3 -c "import sys,json; print(json.load(sys.stdin)['crumbRequestField'])" 2>/dev/null)
  crumb_value=$(echo "${crumb_json}" | python3 -c "import sys,json; print(json.load(sys.stdin)['crumb'])" 2>/dev/null)
  token=$(curl -s     -u "${JENKINS_USER}:${JENKINS_PASSWORD}"     -b "${COOKIE_FILE}"     -c "${COOKIE_FILE}"     -H "${crumb_field}: ${crumb_value}"     -X POST     --data "newTokenName=deploy-script-token"     "http://jenkins.devops.local/me/descriptorByName/jenkins.security.ApiTokenProperty/generateNewToken"     | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['tokenValue'])" 2>/dev/null)
  [[ -n "${token}" ]] || { echo "ERROR: empty token" >&2; exit 1; }
  echo "${token}" > "${API_TOKEN_FILE}"
  echo "${token}"
}

# ── create jenkins pipeline job ───────────────────────────────
create_jenkins_pipeline() {
  local token=$1
  info "Creating Jenkins timestamp-recorder pipeline job..."

  # Delete existing jobs cleanly
  curl -s -X POST -u "${JENKINS_USER}:${token}" \
    "http://jenkins.devops.local/job/timestamp-recorder/doDelete" 2>/dev/null || true
  curl -s -X POST -u "${JENKINS_USER}:${token}" \
    "http://jenkins.devops.local/job/devops-pipeline/doDelete" 2>/dev/null || true
  sleep 3

  # Create job from SCM (uses jenkins/Jenkinsfile from repo)
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    -u "${JENKINS_USER}:${token}" \
    -H "Content-Type: application/xml" \
    "http://jenkins.devops.local/createItem?name=timestamp-recorder" \
    -d '<?xml version="1.1" encoding="UTF-8"?>
<flow-definition plugin="workflow-job">
  <description>Records timestamp to PostgreSQL every 5 mins via K8s worker pod</description>
  <properties>
    <org.jenkinsci.plugins.workflow.job.properties.PipelineTriggersJobProperty>
      <triggers>
        <hudson.triggers.TimerTrigger>
          <spec>H/5 * * * *</spec>
        </hudson.triggers.TimerTrigger>
      </triggers>
    </org.jenkinsci.plugins.workflow.job.properties.PipelineTriggersJobProperty>
  </properties>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition" plugin="workflow-cps">
    <scm class="hudson.plugins.git.GitSCM" plugin="git">
      <configVersion>2</configVersion>
      <userRemoteConfigs>
        <hudson.plugins.git.UserRemoteConfig>
          <url>https://github.com/PrathmeshCICD/devops-assignment-checkmarks.git</url>
        </hudson.plugins.git.UserRemoteConfig>
      </userRemoteConfigs>
      <branches>
        <hudson.plugins.git.BranchSpec>
          <name>*/main</name>
        </hudson.plugins.git.BranchSpec>
      </branches>
    </scm>
    <scriptPath>jenkins/Jenkinsfile</scriptPath>
    <lightweight>true</lightweight>
  </definition>
  <disabled>false</disabled>
</flow-definition>')

  if [[ "${http_code}" == "200" || "${http_code}" == "201" ]]; then
    ok "Pipeline job 'timestamp-recorder' created!"
  elif [[ "${http_code}" == "400" ]]; then
    ok "Pipeline job 'timestamp-recorder' already exists."
  else
    warn "Job creation returned HTTP ${http_code}"
  fi
}

# ── trigger jenkins pipeline ──────────────────────────────────
trigger_pipeline() {
  local token=$1
  info "Triggering Jenkins pipeline..."
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    -u "${JENKINS_USER}:${token}" \
    "http://jenkins.devops.local/job/timestamp-recorder/build")
  if [[ "${http_code}" == "201" ]]; then
    ok "Pipeline triggered!"
  else
    warn "Trigger returned HTTP ${http_code}"
  fi
}

# ── setup grafana ─────────────────────────────────────────────
setup_grafana() {
  local grafana_pass=$1
  info "Configuring Grafana Prometheus datasource..."

  curl -s -X POST \
    -u "${GRAFANA_USER}:${grafana_pass}" \
    -H "Content-Type: application/json" \
    -d '{
      "name":"Prometheus","type":"prometheus",
      "url":"http://prometheus-server.devops.svc.cluster.local",
      "access":"proxy","isDefault":true
    }' \
    "http://grafana.devops.local/api/datasources" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print('Datasource: '+d.get('message','ok'))" 2>/dev/null || \
    warn "Datasource may already exist"

  info "Creating Grafana DevOps dashboard..."
  curl -s -X POST \
    -u "${GRAFANA_USER}:${grafana_pass}" \
    -H "Content-Type: application/json" \
    -d '{
      "dashboard":{
        "title":"DevOps Pipeline Dashboard",
        "tags":["devops","jenkins","prometheus"],
        "panels":[
          {
            "id":1,"title":"Services Up","type":"stat",
            "gridPos":{"h":4,"w":6,"x":0,"y":0},
            "datasource":"Prometheus",
            "targets":[{"expr":"count(up == 1)","legendFormat":"Running Services"}]
          },
          {
            "id":2,"title":"Pod CPU Usage","type":"timeseries",
            "gridPos":{"h":8,"w":12,"x":0,"y":4},
            "datasource":"Prometheus",
            "targets":[{"expr":"sum(rate(container_cpu_usage_seconds_total{namespace=\"devops\"}[5m])) by (pod)","legendFormat":"{{pod}}"}]
          },
          {
            "id":3,"title":"Pod Memory Usage","type":"timeseries",
            "gridPos":{"h":8,"w":12,"x":12,"y":4},
            "datasource":"Prometheus",
            "targets":[{"expr":"sum(container_memory_usage_bytes{namespace=\"devops\"}) by (pod)","legendFormat":"{{pod}}"}]
          },
          {
            "id":4,"title":"Jenkins Build Status","type":"stat",
            "gridPos":{"h":4,"w":6,"x":6,"y":0},
            "datasource":"Prometheus",
            "targets":[{"expr":"jenkins_builds_last_build_result_ordinal","legendFormat":"{{job}}"}]
          },
          {
            "id":5,"title":"PostgreSQL Connections","type":"timeseries",
            "gridPos":{"h":8,"w":12,"x":0,"y":12},
            "datasource":"Prometheus",
            "targets":[{"expr":"pg_stat_activity_count","legendFormat":"DB Connections"}]
          },
          {
            "id":6,"title":"Node CPU","type":"gauge",
            "gridPos":{"h":4,"w":6,"x":12,"y":0},
            "datasource":"Prometheus",
            "targets":[{"expr":"100 - (avg(rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)","legendFormat":"CPU %"}]
          }
        ],
        "refresh":"30s",
        "time":{"from":"now-1h","to":"now"},
        "timezone":"browser"
      },
      "overwrite":true,
      "folderId":0
    }' \
    "http://grafana.devops.local/api/dashboards/db" 2>/dev/null && \
    ok "Grafana dashboard created!" || warn "Dashboard creation failed"
}

# ── show db records ───────────────────────────────────────────
show_db_records() {
  info "PostgreSQL timestamp records:"
  kubectl exec -n "${NAMESPACE}" postgres-postgresql-0 -- \
    env PGPASSWORD="${PG_PASSWORD}" psql -U postgres -d devops \
    -c "SELECT id, timestamp, pod_name, job_name, build_num FROM timestamps ORDER BY id DESC LIMIT 10;" \
    2>/dev/null || warn "No records yet"
}

# ── verify all services ───────────────────────────────────────
verify_all() {
  section "VERIFYING ALL SERVICES"

  info "Pod Status:"
  kubectl get pods -A --no-headers | while read -r ns name ready status restarts age; do
    if [[ "${status}" == "Running" ]]; then
      ok "${ns}/${name} - ${status}"
    else
      fail "${ns}/${name} - ${status}"
    fi
  done

  echo ""
  info "Helm Releases:"
  helm list -A --no-headers | while read -r name ns revision updated1 updated2 status chart appver; do
    if [[ "${status}" == "deployed" ]]; then
      ok "${name} (${ns}) - ${status}"
    else
      fail "${name} (${ns}) - ${status}"
    fi
  done

  echo ""
  info "Service Endpoints:"
  local token
  token=$(cat "${API_TOKEN_FILE}" 2>/dev/null || echo "")

  if curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 \
      "http://jenkins.devops.local" 2>/dev/null | grep -qE "200|403"; then
    ok "Jenkins  → http://jenkins.devops.local"
  else
    fail "Jenkins  → http://jenkins.devops.local (not reachable)"
  fi

  if curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 \
      "http://grafana.devops.local" 2>/dev/null | grep -qE "200|302"; then
    ok "Grafana  → http://grafana.devops.local"
  else
    fail "Grafana  → http://grafana.devops.local (not reachable)"
  fi

  if curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 \
      "http://traefik.devops.local" 2>/dev/null | grep -qE "200|404"; then
    ok "Traefik  → http://traefik.devops.local"
  else
    fail "Traefik  → http://traefik.devops.local (not reachable)"
  fi

  local prom_status
  prom_status=$(kubectl get pods -n devops --no-headers 2>/dev/null | grep prometheus-server | awk '{print $3}')
  if [[ "${prom_status}" == "Running" ]]; then
    ok "Prometheus → Running"
  else
    fail "Prometheus → not running"
  fi

  echo ""
  if [[ -n "${token}" ]]; then
    info "Jenkins Pipeline Status:"
    local build_result
    build_result=$(curl -s -u "${JENKINS_USER}:${token}" \
      "http://jenkins.devops.local/job/timestamp-recorder/lastBuild/api/json?tree=result,number,building" \
      2>/dev/null | python3 -c "
import sys,json
try:
  d=json.load(sys.stdin)
  print(f'Build #{d[\"number\"]} - {d[\"result\"]} - Building: {d[\"building\"]}')
except:
  print('No builds yet')
" 2>/dev/null || echo "Could not fetch")
    if echo "${build_result}" | grep -q "SUCCESS"; then
      ok "Last build: ${build_result}"
    else
      warn "Last build: ${build_result}"
    fi
  fi

  echo ""
  section "DATABASE RECORDS"
  show_db_records

  echo ""
  section "GRAFANA METRICS CHECK"
  local grafana_pass
  grafana_pass=$(kubectl get secret --namespace "${NAMESPACE}" grafana \
    -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 --decode || echo "")
  if [[ -n "${grafana_pass}" ]]; then
    local ds_count
    ds_count=$(curl -s -u "${GRAFANA_USER}:${grafana_pass}" \
      "http://grafana.devops.local/api/datasources" 2>/dev/null | \
      python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
    ok "Grafana datasources: ${ds_count}"

    local dash_count
    dash_count=$(curl -s -u "${GRAFANA_USER}:${grafana_pass}" \
      "http://grafana.devops.local/api/search" 2>/dev/null | \
      python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
    ok "Grafana dashboards: ${dash_count}"
  fi
}

# ── install ───────────────────────────────────────────────────
install() {
  check_prereqs

  section "STEP 1: Starting Minikube"
  if minikube status --format='{{.Host}}' 2>/dev/null | grep -q "Running"; then
    warn "Minikube already running – skipping."
  else
    minikube start \
      --driver="${MINIKUBE_DRIVER}" \
      --cpus="${MINIKUBE_CPUS}" \
      --memory="${MINIKUBE_MEMORY}" \
      --addons=metrics-server
  fi

  section "STEP 2: Creating Namespaces"
  kubectl create namespace "${NAMESPACE}"  --dry-run=client -o yaml | kubectl apply -f -
  kubectl create namespace "${TRAEFIK_NS}" --dry-run=client -o yaml | kubectl apply -f -

  section "STEP 3: Adding Helm Repositories"
  helm repo add bitnami              https://charts.bitnami.com/bitnami                 2>/dev/null || true
  helm repo add jenkins              https://charts.jenkins.io                          2>/dev/null || true
  helm repo add grafana              https://grafana.github.io/helm-charts              2>/dev/null || true
  helm repo add traefik              https://traefik.github.io/charts                   2>/dev/null || true
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
  helm repo update

  section "STEP 4: Creating Secrets"
  kubectl create secret generic postgres-secret \
    --namespace="${NAMESPACE}" \
    --from-literal=postgres-password="${PG_PASSWORD}" \
    --from-literal=password="${PG_PASSWORD}" \
    --dry-run=client -o yaml | kubectl apply -f -

  section "STEP 5: Deploying Traefik"
  deploy_traefik

  section "STEP 6: Starting Minikube Tunnel + Configuring Hosts"
  start_tunnel
  EXTERNAL_IP=$(get_external_ip)
  configure_hosts "${EXTERNAL_IP}"

  section "STEP 7: Deploying PostgreSQL"
  fix_stuck_release postgres "${NAMESPACE}"
  helm_deploy postgres bitnami/postgresql "${NAMESPACE}" 8m \
    --values helm/postgresql-values.yaml

  section "STEP 8: Initialising PostgreSQL Database"
  kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=postgresql \
    -n "${NAMESPACE}" --timeout=3m 2>/dev/null || true
  kubectl exec -n "${NAMESPACE}" postgres-postgresql-0 -- \
    env PGPASSWORD="${PG_PASSWORD}" psql -U postgres \
    -c "CREATE DATABASE devops;" 2>/dev/null || true
  kubectl exec -n "${NAMESPACE}" postgres-postgresql-0 -- \
    env PGPASSWORD="${PG_PASSWORD}" psql -U postgres -d devops \
    -c "CREATE TABLE IF NOT EXISTS timestamps (
          id        SERIAL PRIMARY KEY,
          timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          pod_name  TEXT,
          job_name  TEXT,
          build_num INTEGER
        );" 2>/dev/null || true
  ok "Database and table ready."

  section "STEP 9: Deploying Jenkins"
  kubectl delete serviceaccount jenkins -n "${NAMESPACE}" 2>/dev/null || true
  kubectl delete clusterrole jenkins-role 2>/dev/null || true
  kubectl delete clusterrolebinding jenkins-role-binding 2>/dev/null || true
  fix_stuck_release jenkins "${NAMESPACE}"
  helm_deploy jenkins jenkins/jenkins "${NAMESPACE}" 12m \
    --values helm/jenkins-values.yaml

  section "STEP 10: Deploying Prometheus"
  fix_stuck_release prometheus "${NAMESPACE}"
  helm_deploy prometheus prometheus-community/prometheus "${NAMESPACE}" 8m \
    --set server.service.type=ClusterIP

  section "STEP 11: Deploying Grafana"
  fix_stuck_release grafana "${NAMESPACE}"
  helm_deploy grafana grafana/grafana "${NAMESPACE}" 8m \
    --values helm/grafana-values.yaml

  section "STEP 12: Installing Prometheus CRDs"
  kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/bundle.yaml 2>/dev/null || true
  kubectl wait --for=condition=established \
    crd/servicemonitors.monitoring.coreos.com \
    --timeout=60s 2>/dev/null || true

  section "STEP 13: Applying Kubernetes Manifests"
  kubectl apply -f k8s/jenkins-rbac.yaml 2>/dev/null || true
  # Create postgres-exporter secret with real password
  kubectl create secret generic postgres-exporter-secret     --namespace="${NAMESPACE}"     --from-literal=DATA_SOURCE_NAME="postgres://postgres:${PG_PASSWORD}@postgres-postgresql.devops.svc.cluster.local:5432/devops?sslmode=disable"     --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true
  kubectl apply -f k8s/ 2>/dev/null || true

  section "STEP 14: Terraform Grafana Dashboard"
  GRAFANA_PASS=$(kubectl get secret --namespace "${NAMESPACE}" grafana \
    -o jsonpath="{.data.admin-password}" | base64 --decode)
  export TF_VAR_grafana_password="${GRAFANA_PASS}"
  pushd terraform > /dev/null
    terraform init -upgrade -input=false
    terraform apply -auto-approve -input=false
  popd > /dev/null

  section "STEP 15: Generating Jenkins API Token"
  wait_for_jenkins
  API_TOKEN=$(get_jenkins_token)

  section "STEP 16: Creating Jenkins Pipeline"
  create_jenkins_pipeline "${API_TOKEN}"

  section "STEP 17: Configuring Grafana Datasource + Dashboard"
  setup_grafana "${GRAFANA_PASS}"

  section "STEP 18: Triggering First Pipeline Run"
  trigger_pipeline "${API_TOKEN}"
  info "Waiting 90 seconds for pipeline to complete..."
  sleep 90

  section "STEP 19: Verifying Everything"
  verify_all

  JENKINS_PASS_DISPLAY=$(kubectl get secret --namespace "${NAMESPACE}" jenkins \
    -o jsonpath="{.data.jenkins-admin-password}" | base64 --decode)

  section "ALL DONE!"
  echo -e "${GREEN}"
  echo "  ╔══════════════════════════════════════════════════════════╗"
  echo "  ║           DEVOPS STACK FULLY DEPLOYED & VERIFIED        ║"
  echo "  ╠══════════════════════════════════════════════════════════╣"
  echo "  ║                                                          ║"
  printf "  ║  Jenkins  → http://jenkins.devops.local                 ║\n"
  printf "  ║             admin / %-37s║\n" "${JENKINS_PASS_DISPLAY}"
  echo "  ║                                                          ║"
  printf "  ║  Grafana  → http://grafana.devops.local                 ║\n"
  printf "  ║             admin / %-37s║\n" "${GRAFANA_PASS}"
  echo "  ║                                                          ║"
  echo "  ║  Traefik  → http://traefik.devops.local                  ║"
  echo "  ║                                                          ║"
  echo "  ║  Pipeline → timestamp-recorder (auto every 5 mins)      ║"
  echo "  ║  Database → devops.timestamps (records above)           ║"
  echo "  ║  Metrics  → Grafana DevOps Pipeline Dashboard           ║"
  echo "  ║                                                          ║"
  echo "  ║  ⚠  Keep 'minikube tunnel' running for access!          ║"
  echo "  ║                                                          ║"
  echo "  ║  Commands:                                               ║"
  echo "  ║    ./deploy.sh verify    → check all + DB + metrics      ║"
  echo "  ║    ./deploy.sh pipeline  → trigger pipeline now          ║"
  echo "  ║    ./deploy.sh status    → quick status check            ║"
  echo "  ║    ./deploy.sh uninstall → tear everything down          ║"
  echo "  ╚══════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
}

# ── pipeline (manual trigger) ─────────────────────────────────
pipeline() {
  section "TRIGGERING JENKINS PIPELINE"
  local token
  token=$(get_jenkins_token)
  create_jenkins_pipeline "${token}"
  trigger_pipeline "${token}"
  info "Waiting 90 seconds for pipeline to complete..."
  sleep 90
  show_db_records
}

# ── status ────────────────────────────────────────────────────
status() {
  section "QUICK STATUS"
  kubectl get pods -A
  echo ""
  helm list -A
  echo ""
  show_db_records
  echo ""
  JENKINS_PASS_DISPLAY=$(kubectl get secret --namespace "${NAMESPACE}" jenkins \
    -o jsonpath="{.data.jenkins-admin-password}" 2>/dev/null | base64 --decode || echo "not-ready")
  GRAFANA_PASS=$(kubectl get secret --namespace "${NAMESPACE}" grafana \
    -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 --decode || echo "not-ready")
  EXTERNAL_IP=$(kubectl get svc traefik -n "${TRAEFIK_NS}" \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "run minikube tunnel")
  echo ""
  echo "  External IP : ${EXTERNAL_IP}"
  echo "  Jenkins     : http://jenkins.devops.local  (admin / ${JENKINS_PASS_DISPLAY})"
  echo "  Grafana     : http://grafana.devops.local  (admin / ${GRAFANA_PASS})"
  echo "  Traefik     : http://traefik.devops.local"
  echo "  Tunnel      : $(pgrep -f 'minikube tunnel' > /dev/null 2>&1 && echo 'RUNNING ✅' || echo 'NOT RUNNING ❌ - run: minikube tunnel')"
}

# ── verify ────────────────────────────────────────────────────
verify() {
  verify_all
}

# ── uninstall ─────────────────────────────────────────────────
uninstall() {
  check_prereqs
  warn "Uninstalling all components..."

  if pgrep -f "minikube tunnel" > /dev/null 2>&1; then
    warn "Stopping minikube tunnel..."
    sudo pkill -f "minikube tunnel" 2>/dev/null || true
  fi

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

  sudo sed -i '/devops.local/d' /etc/hosts 2>/dev/null || true
  rm -f "${API_TOKEN_FILE}" "${COOKIE_FILE}" "${CRUMB_FILE}" 2>/dev/null || true

  warn "Stopping Minikube..."
  minikube stop   2>/dev/null || true
  minikube delete 2>/dev/null || true

  ok "Uninstall complete."
}

# ── entrypoint ────────────────────────────────────────────────
case "${1:-}" in
  install)   install   ;;
  uninstall) uninstall ;;
  status)    status    ;;
  pipeline)  pipeline  ;;
  verify)    verify    ;;
  *)         die "Usage: $0 {install|uninstall|status|pipeline|verify}" ;;
esac