output "alb_dns_name" {
  value = module.compute.alb_dns_name
}
output "ecr_repository_url" {
  value = module.compute.ecr_repository_url
}
output "ecs_cluster_name" {
  value = module.compute.ecs_cluster_name
}
output "ecs_service_name" {
  value = module.compute.ecs_service_name
}
