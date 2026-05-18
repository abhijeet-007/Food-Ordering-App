project    = "food-app"
env        = "dev"
aws_region = "ap-south-1"

vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
availability_zones   = ["ap-south-1a", "ap-south-1b"]

task_cpu      = 256
task_memory   = 512
desired_count = 1
min_capacity  = 1
max_capacity  = 2

log_retention_days = 7
health_check_path  = "/health"
