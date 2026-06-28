variable "aws_region" {
  type        = string
  description = "AWS region"
  default     = "eu-west-1"
}

variable "project_name" {
  type        = string
  description = "Project name prefix"
  default     = "url_health_checker"
}

variable "environment" {
  type        = string
  description = "Environment name"
  default     = "prod"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "Public subnet CIDR blocks"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "Private subnet CIDR blocks"
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "availability_zones" {
  type        = list(string)
  description = "Availability zones to use"
  default     = ["eu-west-1a", "eu-west-1b"]
}

variable "container_port" {
  type        = number
  description = "Container port"
  default     = 8000
}

variable "task_cpu" {
  type        = string
  description = "Fargate CPU units"
  default     = "256"
}

variable "task_memory" {
  type        = string
  description = "Fargate memory (MiB)"
  default     = "512"
}

variable "desired_count" {
  type        = number
  description = "Number of running tasks"
  default     = 1
}

variable "health_check_timeout" {
  type        = number
  description = "Health check timeout in seconds"
  default     = 10
}

variable "image_tag" {
  type        = string
  description = "Container image tag"
  default     = "latest"
}

variable "monitoring_instance_type" {
  type        = string
  description = "EC2 instance type for the Prometheus/YACE/Grafana box"
  default     = "t3.small"
}
