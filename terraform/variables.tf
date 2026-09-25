variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix used for resource names and tags."
  type        = string
  default     = "game-platform"
}

variable "instance_type" {
  description = "EC2 instance type. Must match `architecture` (t4g/m7g = arm64, t3/m7i = x86_64)."
  type        = string
  default     = "t4g.small"
}

variable "architecture" {
  description = "CPU architecture of the instance: arm64 or x86_64. Images are built for this platform."
  type        = string
  default     = "arm64"

  validation {
    condition     = contains(["arm64", "x86_64"], var.architecture)
    error_message = "architecture must be arm64 or x86_64."
  }
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB (OS + Docker images)."
  type        = number
  default     = 20
}

variable "data_volume_size" {
  description = "Size in GiB of the persistent EBS volume holding MongoDB data and TLS certificates."
  type        = number
  default     = 20
}

variable "domain_name" {
  description = "Public hostname for the app (e.g. games.example.com). Leave empty to use <ip>.sslip.io."
  type        = string
  default     = ""
}

variable "route53_zone_name" {
  description = "Existing Route 53 hosted zone (e.g. example.com). If set, an A record for domain_name is created."
  type        = string
  default     = ""
}

variable "acme_email" {
  description = "Email used for Let's Encrypt certificate registration and expiry notices."
  type        = string
}

variable "rails_master_key" {
  description = "Contents of config/master.key. If null, read from ../config/master.key."
  type        = string
  default     = null
  sensitive   = true
}

variable "ssh_key_name" {
  description = "Optional EC2 key pair name for SSH. Access through SSM Session Manager works without it."
  type        = string
  default     = null
}

variable "ssh_allowed_cidrs" {
  description = "CIDR blocks allowed to SSH (only used when ssh_key_name is set)."
  type        = list(string)
  default     = []
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.40.0.0/16"
}

variable "enable_backups" {
  description = "Take daily EBS snapshots of the data volume."
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of daily snapshots to keep."
  type        = number
  default     = 7
}

variable "docker_compose_version" {
  description = "Docker Compose plugin release installed on the instance."
  type        = string
  default     = "v2.29.7"
}
