variable "project"                { type = string }
variable "env"                    { type = string }
variable "aws_region"             { type = string }
variable "vpc_id"                 { type = string }
variable "public_subnet_ids"      { type = list(string) }
variable "private_subnet_ids"     { type = list(string) }
variable "alb_sg_id"              { type = string }
variable "ecs_sg_id"              { type = string }
variable "ecs_execution_role_arn" { type = string }
variable "ecs_task_role_arn"      { type = string }
variable "log_group_name"         { type = string }
variable "image_tag"              { type = string; default = "latest" }
variable "container_port"         { type = number; default = 80 }
variable "health_check_path"      { type = string; default = "/" }
variable "task_cpu"               { type = number; default = 256 }
variable "task_memory"            { type = number; default = 512 }
variable "desired_count"          { type = number; default = 2 }
variable "min_capacity"           { type = number; default = 2 }
variable "max_capacity"           { type = number; default = 6 }
variable "container_environment"  { type = list(object({ name = string, value = string })); default = [] }
variable "container_secrets"      { type = list(object({ name = string, valueFrom = string })); default = [] }
variable "tags"                   { type = map(string); default = {} }
