variable "project" {
  type = string
}
variable "env" {
  type = string
}
variable "ecs_cluster_name" {
  type = string
}
variable "ecs_service_name" {
  type = string
}
variable "alb_arn_suffix" {
  type = string
}
variable "log_retention_days" {
  type    = number
  default = 30
}
variable "alarm_actions" {
  type    = list(string)
  default = []
}
variable "tags" {
  type    = map(string)
  default = {}
}
