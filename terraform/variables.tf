# terraform/variables.tf
variable "grafana_url" {
  description = "Grafana base URL"
  type        = string
  default     = "http://grafana.devops.local"
}

variable "grafana_password" {
  description = "Grafana admin password (set via TF_VAR_grafana_password env var)"
  type        = string
  sensitive   = true
  # ✅ No default - deploy.sh sets TF_VAR_grafana_password automatically
}
