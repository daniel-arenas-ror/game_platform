resource "random_password" "mongo" {
  length  = 32
  special = false # keeps the password URL-safe inside MONGODB_URI
}

resource "aws_ssm_parameter" "rails_master_key" {
  name  = "/${var.project_name}/rails_master_key"
  type  = "SecureString"
  value = coalesce(var.rails_master_key, trimspace(file("${path.module}/../config/master.key")))
}

resource "aws_ssm_parameter" "mongo_password" {
  name  = "/${var.project_name}/mongo_password"
  type  = "SecureString"
  value = random_password.mongo.result
}
