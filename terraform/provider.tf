terraform {
  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 1.39"
    }
  }
}

provider "grafana" {
  url  = "http://grafana.devops.local"
  auth = "admin:drow"
}