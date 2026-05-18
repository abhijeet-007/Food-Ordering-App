terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

locals {
  common_tags = {
    Project     = var.project
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

module "networking" {
  source = "../../modules/networking"

  project              = var.project
  env                  = var.env
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
  tags                 = local.common_tags
}

module "security" {
  source = "../../modules/security"

  project        = var.project
  env            = var.env
  vpc_id         = module.networking.vpc_id
  container_port = var.container_port
  aws_region     = var.aws_region
  tags           = local.common_tags
}

module "monitoring" {
  source = "../../modules/monitoring"

  project            = var.project
  env                = var.env
  ecs_cluster_name   = module.compute.ecs_cluster_name
  ecs_service_name   = module.compute.ecs_service_name
  alb_arn_suffix     = module.compute.alb_arn_suffix
  log_retention_days = var.log_retention_days
  alarm_actions      = var.alarm_actions
  tags               = local.common_tags
}

module "compute" {
  source = "../../modules/compute"

  project                = var.project
  env                    = var.env
  aws_region             = var.aws_region
  vpc_id                 = module.networking.vpc_id
  public_subnet_ids      = module.networking.public_subnet_ids
  private_subnet_ids     = module.networking.private_subnet_ids
  alb_sg_id              = module.security.alb_sg_id
  ecs_sg_id              = module.security.ecs_sg_id
  ecs_execution_role_arn = module.security.ecs_execution_role_arn
  ecs_task_role_arn      = module.security.ecs_task_role_arn
  log_group_name         = module.monitoring.log_group_name
  image_tag              = var.image_tag
  container_port         = var.container_port
  health_check_path      = var.health_check_path
  task_cpu               = var.task_cpu
  task_memory            = var.task_memory
  desired_count          = var.desired_count
  min_capacity           = var.min_capacity
  max_capacity           = var.max_capacity
  container_environment  = var.container_environment
  container_secrets      = var.container_secrets
  tags                   = local.common_tags
}
