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

output "monitoring_instance_id" {
  description = "SSM target - aws ssm start-session --target <this>"
  value       = module.monitoring.monitoring_instance_id
}

output "ecs_log_group_name" {
  description = "Paste this into Grafana's CloudWatch Logs Explore"
  value       = module.ecs.log_group_name
}