terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    grafana = {
      source  = "grafana/grafana"
      version = "~> 1.39"
    }
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "grafana" {
  url  = "http://grafana.devops.local"
  auth = "admin:b39IED5Lf73fxXWBRnWTNJ0F2Ghf7cYu5c150An1"
}