project    = "food-app"
env        = "prod"
aws_region = "ap-south-1"

vpc_cidr             = "10.2.0.0/16"
public_subnet_cidrs  = ["10.2.1.0/24", "10.2.2.0/24"]
private_subnet_cidrs = ["10.2.10.0/24", "10.2.11.0/24"]
availability_zones   = ["ap-south-1a", "ap-south-1b"]

task_cpu      = 512
task_memory   = 1024
desired_count = 1
min_capacity  = 1
max_capacity  = 3

log_retention_days = 30
health_check_path  = "/health"
