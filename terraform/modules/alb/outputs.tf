output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.app.dns_name
}

output "target_group_arn" {
  description = "Target group ARN"
  value       = aws_lb_target_group.app.arn
}

output "listener_arn" {
  description = "Listener ARN"
  value       = aws_lb_listener.http.arn
}

output "alb_arn" {
  description = "ALB ARN"
  value       = aws_lb.app.arn
}

output "grafana_target_group_arn" {
  value = aws_lb_target_group.grafana.arn
}

output "prometheus_target_group_arn" {
  value = aws_lb_target_group.prometheus.arn
}
