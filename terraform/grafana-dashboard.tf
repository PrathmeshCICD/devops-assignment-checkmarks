resource "grafana_dashboard" "postgres_dashboard" {
  config_json = jsonencode({
    title = "PostgreSQL Metrics"
    panels = [
      {
        type = "graph"
        title = "CPU Usage"
        datasource = "Prometheus"
        targets = [
          {
            expr = "rate(container_cpu_usage_seconds_total[5m])"
          }
        ]
      },
      {
        type = "graph"
        title = "Memory Usage"
        datasource = "Prometheus"
        targets = [
          {
            expr = "container_memory_usage_bytes"
          }
        ]
      },
      {
        type = "graph"
        title = "PostgreSQL Throughput"
        datasource = "Prometheus"
        targets = [
          {
            expr = "pg_stat_database_xact_commit"
          }
        ]
      }
    ]
  })
}
