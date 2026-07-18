variable "name_prefix" {
  type        = string
  description = "Name prefix for resources"
}

variable "tags" {
  type        = map(string)
  description = "Common tags"
}

variable "aws_region" {
  type        = string
  description = "AWS region"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type"
}

variable "public_subnet_id" {
  type        = string
  description = "Public subnet ID for the monitoring instance"
}

variable "monitoring_sg_id" {
  type        = string
  description = "Security group ID for the monitoring instance"
}

variable "key_name" {
  type        = string
  description = "Existing EC2 key pair name for SSH access"
}

variable "discovery_tag_key" {
  type        = string
  description = "Tag key YACE uses to discover resources"
}

variable "discovery_tag_value" {
  type        = string
  description = "Tag value YACE uses to discover resources"
}

variable "grafana_target_group_arn" {
  type        = string
  description = "ALB target group ARN for Grafana"
}

variable "prometheus_target_group_arn" {
  type        = string
  description = "ALB target group ARN for Prometheus"
}

variable "alb_dns_name" {
  type        = string
  description = "ALB DNS name, used for Graylog's external URI"
}

variable "graylog_target_group_arn" {
  type        = string
  description = "ALB target group ARN for Graylog web UI"
}

variable "graylog_root_password_sha2" {
  type        = string
  description = "SHA256 hash of the Graylog admin password"
  sensitive   = true
}

variable "graylog_password_secret" {
  type        = string
  description = "Graylog password secret (random string, min 16 chars)"
  sensitive   = true
}

variable "graylog_smtp_username" {
  type      = string
  sensitive = true
}

variable "graylog_smtp_password" {
  type      = string
  sensitive = true
}