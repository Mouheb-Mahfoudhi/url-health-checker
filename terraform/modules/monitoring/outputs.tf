output "instance_id" {
  description = "Monitoring instance ID"
  value       = aws_instance.monitoring.id
}

output "public_ip" {
  description = "Monitoring instance public IP (for SSH)"
  value       = aws_instance.monitoring.public_ip
}