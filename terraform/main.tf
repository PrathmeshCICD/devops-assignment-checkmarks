resource "grafana_dashboard" "postgres" {
  config_json = file("${path.module}/postgres.json")
}