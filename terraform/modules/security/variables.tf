variable "project" {
  type = string
}
variable "env" {
  type = string
}
variable "vpc_id" {
  type = string
}
variable "container_port" {
  type    = number
  default = 80
}
variable "aws_region" {
  type = string
}
variable "tags" {
  type    = map(string)
  default = {}
}
