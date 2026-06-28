output "monitoring_instance_id" {
  description = "Instance ID - connect with: aws ssm start-session --target <id>"
  value       = aws_instance.monitoring.id
}
