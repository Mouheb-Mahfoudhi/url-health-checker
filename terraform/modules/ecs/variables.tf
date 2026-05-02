variable "name_prefix" {
  type        = string
  description = "Name prefix for resources"
}

variable "project_name" {
  type        = string
  description = "Project name"
}

variable "tags" {
  type        = map(string)
  description = "Common tags"
}

variable "task_cpu" {
  type        = string
  description = "Fargate CPU units"
}

variable "task_memory" {
  type        = string
  description = "Fargate memory (MiB)"
}

variable "desired_count" {
  type        = number
  description = "Number of running tasks"
}

variable "container_port" {
  type        = number
  description = "Container port"
}

variable "image_tag" {
  type        = string
  description = "Container image tag"
}

variable "health_check_timeout" {
  type        = number
  description = "Health check timeout in seconds"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs"
}

variable "ecs_sg_id" {
  type        = string
  description = "ECS security group ID"
}

variable "target_group_arn" {
  type        = string
  description = "Target group ARN"
}

variable "ecr_repository_url" {
  type        = string
  description = "ECR repository URL"
}

variable "ecr_repository_arn" {
  type        = string
  description = "ECR repository ARN"
}
