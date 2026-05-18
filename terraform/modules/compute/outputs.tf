output "ecr_repository_url" { value = aws_ecr_repository.main.repository_url }
output "ecr_repository_name" { value = aws_ecr_repository.main.name }
output "ecs_cluster_name" { value = aws_ecs_cluster.main.name }
output "ecs_service_name" { value = aws_ecs_service.main.name }
output "alb_dns_name" { value = aws_lb.main.dns_name }
output "alb_arn_suffix" { value = aws_lb.main.arn_suffix }
output "target_group_arn" { value = aws_lb_target_group.main.arn }
