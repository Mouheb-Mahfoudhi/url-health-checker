variable "name_prefix" {
  type        = string
  description = "Name prefix for resources"
}

variable "tags" {
  type        = map(string)
  description = "Common tags"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID"
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Public subnet IDs"
}

variable "alb_sg_id" {
  type        = string
  description = "ALB security group ID"
}

variable "container_port" {
  type        = number
  description = "Container port"
}

variable "health_check_path" {
  type        = string
  description = "Health check path"
  default     = "/ping"
}
