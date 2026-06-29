variable "name_prefix" {
  type        = string
  description = "Name prefix for resources"
}

variable "tags" {
  type        = map(string)
  description = "Common tags"
}

variable "private_subnet_id" {
  type        = string
  description = "Private subnet ID to launch the monitoring instance in (reuses an existing ECS private subnet - no new networking required, NAT gateway already gives it egress)"
}

variable "monitoring_sg_id" {
  type        = string
  description = "Security group ID for the monitoring instance"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type for the monitoring box (Prometheus + YACE + Grafana all run here)"
  default     = "t3.small"
}

variable "aws_region" {
  type        = string
  description = "AWS region - passed into the YACE config and Grafana's CloudWatch datasource"
}

variable "discovery_tag_key" {
  type        = string
  description = "Tag key YACE uses to discover the ECS service / ALB / target group"
  default     = "Project"
}

variable "discovery_tag_value" {
  type        = string
  description = "Tag value YACE filters on - should match local.tags.Project in root main.tf"
}

variable "grafana_target_group_arn" {
  type        = string
  description = "ALB target group ARN for Grafana"
}

variable "prometheus_target_group_arn" {
  type        = string
  description = "ALB target group ARN for Prometheus"
}
