#!/bin/bash
# Usage: /opt/game_platform/bin/deploy [image-tag]
# Refreshes secrets from SSM, pulls the image from ECR and (re)starts the stack.
set -euo pipefail
source /etc/game_platform/config.env

TAG="${1:-latest}"
cd /opt/game_platform

param() {
  aws ssm get-parameter --region "$AWS_REGION" --name "$1" --with-decryption --query Parameter.Value --output text
}

umask 077
cat > .env <<ENV
IMAGE_REPO=$ECR_REPOSITORY_URL
IMAGE_TAG=$TAG
APP_DOMAIN=$APP_DOMAIN
ACME_EMAIL=$ACME_EMAIL
MONGO_USER=$MONGO_USER
MONGO_PASSWORD=$(param "$SSM_MONGO_PASSWORD")
RAILS_MASTER_KEY=$(param "$SSM_RAILS_MASTER_KEY")
ENV

docker compose up -d mongo caddy

if docker compose pull web; then
  docker compose up -d --remove-orphans
  docker image prune -f
  echo "Deployed $ECR_REPOSITORY_URL:$TAG to https://$APP_DOMAIN"
else
  echo "Image $ECR_REPOSITORY_URL:$TAG not found. Push one with script/aws_deploy.sh." >&2
  exit 1
fi
