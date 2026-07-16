output "alb_dns_name" {
  description = "Public ALB DNS name"
  value       = module.alb.alb_dns_name
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = module.ecr.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs.ecs_cluster_name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = module.ecs.ecs_service_name
}

output "grafana_url" {
  description = "Grafana URL via ALB"
  value       = "http://${module.alb.alb_dns_name}:3000"
}

output "prometheus_url" {
  description = "Prometheus URL via ALB"
  value       = "http://${module.alb.alb_dns_name}:9090"
}

output "graylog_url" {
  value = "http://${module.alb.alb_dns_name}:9000"
}

output "monitoring_public_ip" {
  description = "Monitoring instance public IP (for SSH)"
  value       = module.monitoring.public_ip
}

output "monitoring_private_ip" {
  description = "Private IP of the monitoring instance, used by ECS tasks for GELF log shipping"
  value       = aws_instance.monitoring.private_ip
}

