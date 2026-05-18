project    = "food-app"
env        = "staging"
aws_region = "ap-south-1"

vpc_cidr             = "10.1.0.0/16"
public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24"]
private_subnet_cidrs = ["10.1.10.0/24", "10.1.11.0/24"]
availability_zones   = ["ap-south-1a", "ap-south-1b"]

task_cpu      = 512
task_memory   = 1024
desired_count = 2
min_capacity  = 2
max_capacity  = 4

log_retention_days = 14
health_check_path  = "/health"
