# terraform/main.tf
# FIX: removed duplicate grafana_dashboard resource (was also in grafana-dashboard.tf)
# Single file now owns the dashboard — delete grafana-dashboard.tf from your repo

resource "grafana_dashboard" "postgres" {
  config_json = file("${path.module}/postgres.json")
}
