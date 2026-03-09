
  
  #!/bin/bash
#!/bin/bash

# ===================================
# DevOps Assignment Deployment Script
# Usage: ./deploy.sh install | uninstall
# ===================================

set -e

ACTION=$1
NAMESPACE="devops"

if [[ "$ACTION" != "install" && "$ACTION" != "uninstall" ]]; then
  echo "Usage: $0 [install|uninstall]"
  exit 1
fi

echo "Checking Kubernetes cluster..."

if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "Starting Minikube..."
  minikube start --driver=docker
fi

kubectl config use-context minikube >/dev/null 2>&1 || true

kubectl get namespace $NAMESPACE >/dev/null 2>&1 || kubectl create namespace $NAMESPACE

echo "Adding Helm repositories..."

helm repo add jenkinsci https://charts.jenkins.io || true
helm repo add grafana https://grafana.github.io/helm-charts || true
helm repo add bitnami https://charts.bitnami.com/bitnami || true
helm repo add traefik https://helm.traefik.io/traefik || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true

helm repo update

# ================= INSTALL =================

if [[ "$ACTION" == "install" ]]; then

  echo "Installing PostgreSQL..."
  helm upgrade --install postgresql bitnami/postgresql \
    -n $NAMESPACE \
    -f helm/postgresql-values.yaml

  echo "Installing Jenkins..."
  helm upgrade --install jenkins jenkinsci/jenkins \
    -n $NAMESPACE \
    -f helm/jenkins-values.yaml

  echo "Installing Prometheus..."
  helm upgrade --install prometheus prometheus-community/prometheus \
    -n $NAMESPACE

  echo "Installing Grafana..."
  helm upgrade --install grafana grafana/grafana \
    -n $NAMESPACE \
    -f helm/grafana-values.yaml

  echo "Installing Traefik..."
  helm upgrade --install traefik traefik/traefik \
    -n $NAMESPACE \
    -f helm/traefik-values.yaml

  echo "Applying Kubernetes manifests..."
  kubectl apply -f k8s/ -n $NAMESPACE

  echo "Waiting for Grafana to be ready..."
  kubectl rollout status deployment grafana -n $NAMESPACE

  echo "Applying Terraform dashboards..."
  cd terraform
  terraform init
  terraform apply -auto-approve
  cd ..

  echo "Deployment completed successfully!"

fi


# ================= UNINSTALL =================

if [[ "$ACTION" == "uninstall" ]]; then

  echo "Removing Kubernetes manifests..."
  kubectl delete -f k8s/ -n $NAMESPACE || true

  echo "Destroying Terraform dashboards..."
  cd terraform
  terraform init || true
  terraform destroy -auto-approve || true
  cd ..

  echo "Uninstalling Helm releases..."

  helm uninstall traefik -n $NAMESPACE || true
  helm uninstall grafana -n $NAMESPACE || true
  helm uninstall prometheus -n $NAMESPACE || true
  helm uninstall jenkins -n $NAMESPACE || true
  helm uninstall postgresql -n $NAMESPACE || true

  echo "Uninstallation completed."

fi
fi
