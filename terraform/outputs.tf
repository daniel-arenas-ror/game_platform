output "app_url" {
  value = "https://${local.app_domain}"
}

output "public_ip" {
  value = aws_eip.app.public_ip
}

output "instance_id" {
  value = aws_instance.app.id
}

output "aws_region" {
  value = var.aws_region
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "docker_platform" {
  value = var.architecture == "arm64" ? "linux/arm64" : "linux/amd64"
}

output "shell_command" {
  description = "Open a root shell on the instance via Session Manager."
  value       = "aws ssm start-session --region ${var.aws_region} --target ${aws_instance.app.id}"
}
