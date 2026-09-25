locals {
  app_dir = "/opt/game_platform"

  # Without a real domain, sslip.io resolves <a-b-c-d>.sslip.io to the Elastic IP so Caddy can still get a TLS cert.
  app_domain = var.domain_name != "" ? var.domain_name : "${replace(aws_eip.app.public_ip, ".", "-")}.sslip.io"

  ecr_registry = split("/", aws_ecr_repository.app.repository_url)[0]

  # Non-secret settings read by the scripts on the instance. Secrets are fetched from SSM at deploy time.
  host_config = <<-EOT
    AWS_REGION=${var.aws_region}
    ECR_REPOSITORY_URL=${aws_ecr_repository.app.repository_url}
    APP_DOMAIN=${local.app_domain}
    ACME_EMAIL=${var.acme_email}
    MONGO_USER=game_platform
    SSM_RAILS_MASTER_KEY=${aws_ssm_parameter.rails_master_key.name}
    SSM_MONGO_PASSWORD=${aws_ssm_parameter.mongo_password.name}
    DATA_VOLUME_ID=${aws_ebs_volume.data.id}
    COMPOSE_VERSION=${var.docker_compose_version}
  EOT

  cloud_init = {
    write_files = [
      { path = "/etc/game_platform/config.env", permissions = "0644", content = local.host_config },
      { path = "${local.app_dir}/docker-compose.yml", permissions = "0644", content = file("${path.module}/files/docker-compose.yml") },
      { path = "${local.app_dir}/Caddyfile", permissions = "0644", content = file("${path.module}/files/Caddyfile") },
      { path = "${local.app_dir}/bin/bootstrap", permissions = "0755", content = file("${path.module}/files/bootstrap.sh") },
      { path = "${local.app_dir}/bin/deploy", permissions = "0755", content = file("${path.module}/files/deploy.sh") },
      { path = "${local.app_dir}/bin/rails", permissions = "0755", content = file("${path.module}/files/rails.sh") },
      { path = "/etc/docker/daemon.json", permissions = "0644", content = jsonencode({ "log-driver" = "json-file", "log-opts" = { "max-size" = "10m", "max-file" = "5" } }) },
      { path = "/root/.docker/config.json", permissions = "0600", content = jsonencode({ credHelpers = { (local.ecr_registry) = "ecr-login" } }) },
    ]
    runcmd = [["${local.app_dir}/bin/bootstrap"]]
  }
}

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-${var.architecture}"
}

resource "aws_eip" "app" {
  domain = "vpc"

  tags = { Name = var.project_name }
}

# Persistent volume for MongoDB data and Caddy certificates. Survives instance replacement.
resource "aws_ebs_volume" "data" {
  availability_zone = local.availability_zone
  size              = var.data_volume_size
  type              = "gp3"
  encrypted         = true

  tags = {
    Name     = "${var.project_name}-data"
    Snapshot = "${var.project_name}-data"
  }
}

resource "aws_instance" "app" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name
  key_name               = var.ssh_key_name

  user_data                   = "#cloud-config\n${yamlencode(local.cloud_init)}"
  user_data_replace_on_change = true

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1 # keeps containers from reaching instance credentials
  }

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = var.project_name }

  lifecycle {
    # Don't replace the server every time AWS publishes a new AMI.
    ignore_changes = [ami]
  }
}

resource "aws_volume_attachment" "data" {
  device_name                    = "/dev/sdf"
  volume_id                      = aws_ebs_volume.data.id
  instance_id                    = aws_instance.app.id
  stop_instance_before_detaching = true
}

resource "aws_eip_association" "app" {
  allocation_id = aws_eip.app.id
  instance_id   = aws_instance.app.id
}
