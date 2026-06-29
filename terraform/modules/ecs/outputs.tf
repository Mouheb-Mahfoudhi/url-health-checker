output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.app.name
}
output "log_group_name" {
  description = "CloudWatch log group name for ECS task logs"
  value       = aws_cloudwatch_log_group.app.name
}