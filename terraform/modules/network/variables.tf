variable "name_prefix" {
  type        = string
  description = "Name prefix for resources"
}

variable "tags" {
  type        = map(string)
  description = "Common tags"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "Public subnet CIDR blocks"
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "Private subnet CIDR blocks"
}

variable "availability_zones" {
  type        = list(string)
  description = "Availability zones"
}
