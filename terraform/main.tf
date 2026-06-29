terraform {
  backend "s3" {
    bucket       = "url-health-checker-backend-22"
    key          = "state/url_health_checker/terraform.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true
  }
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  name_prefix = replace(var.project_name, "_", "-")
  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}
module "network" {
  source               = "./modules/network"
  name_prefix          = local.name_prefix
  tags                 = local.tags
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
}

module "security" {
  source         = "./modules/security"
  name_prefix    = local.name_prefix
  tags           = local.tags
  vpc_id         = module.network.vpc_id
  container_port = var.container_port
}

module "ecr" {
  source = "./modules/ecr"
  name   = var.project_name
  tags   = local.tags
}

module "alb" {
  source            = "./modules/alb"
  name_prefix       = local.name_prefix
  tags              = local.tags
  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids
  alb_sg_id         = module.security.alb_sg_id
  container_port    = var.container_port
}

module "ecs" {
  source              = "./modules/ecs"
  name_prefix         = local.name_prefix
  project_name        = var.project_name
  tags                = local.tags
  task_cpu            = var.task_cpu
  task_memory         = var.task_memory
  desired_count       = var.desired_count
  container_port      = var.container_port
  image_tag           = var.image_tag
  health_check_timeout = var.health_check_timeout
  private_subnet_ids  = module.network.private_subnet_ids
  ecs_sg_id           = module.security.ecs_sg_id
  target_group_arn    = module.alb.target_group_arn
  ecr_repository_url  = module.ecr.repository_url
  ecr_repository_arn  = module.ecr.repository_arn
}

module "monitoring" {
  source               = "./modules/monitoring"
  name_prefix          = local.name_prefix
  tags                 = local.tags
  private_subnet_id    = module.network.private_subnet_ids[0]
  monitoring_sg_id     = module.security.monitoring_sg_id
  grafana_target_group_arn     = module.alb.grafana_target_group_arn
  prometheus_target_group_arn  = module.alb.prometheus_target_group_arn
  instance_type        = var.monitoring_instance_type
  aws_region           = var.aws_region
  discovery_tag_key    = "Project"
  discovery_tag_value  = var.project_name
}
