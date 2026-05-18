variable "project" {
  type = string
}
variable "env" {
  type = string
}
variable "aws_region" {
  type = string
}
variable "vpc_cidr" {
  type = string
}
variable "public_subnet_cidrs" {
  type = list(string)
}
variable "private_subnet_cidrs" {
  type = list(string)
}
variable "availability_zones" {
  type = list(string)
}
variable "container_port" {
  type    = number
  default = 80
}
variable "health_check_path" {
  type    = string
  default = "/"
}
variable "task_cpu" {
  type    = number
  default = 256
}
variable "task_memory" {
  type    = number
  default = 512
}
variable "desired_count" {
  type    = number
  default = 2
}
variable "min_capacity" {
  type    = number
  default = 2
}
variable "max_capacity" {
  type    = number
  default = 6
}
variable "log_retention_days" {
  type    = number
  default = 30
}
variable "alarm_actions" {
  type    = list(string)
  default = []
}
variable "image_tag" {
  type    = string
  default = "latest"
}
variable "container_environment" {
  type    = list(object({ name = string, value = string }))
  default = []
}
variable "container_secrets" {
  type    = list(object({ name = string, valueFrom = string }))
  default = []
}
