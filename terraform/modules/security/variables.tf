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

variable "container_port" {
  type        = number
  description = "Container port"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block, for allowing GELF UDP from ECS tasks"
}