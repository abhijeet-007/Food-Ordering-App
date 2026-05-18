project    = "food-app"
env        = "prod"
aws_region = "ap-south-1"

vpc_cidr             = "10.2.0.0/16"
public_subnet_cidrs  = ["10.2.1.0/24", "10.2.2.0/24"]
private_subnet_cidrs = ["10.2.10.0/24", "10.2.11.0/24"]
availability_zones   = ["ap-south-1a", "ap-south-1b"]

task_cpu      = 1024
task_memory   = 2048
desired_count = 2
min_capacity  = 2
max_capacity  = 6

log_retention_days = 90
health_check_path  = "/health"
