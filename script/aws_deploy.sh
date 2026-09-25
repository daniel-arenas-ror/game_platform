#!/usr/bin/env bash
# Build the Docker image, push it to ECR and restart the app on the EC2 instance.
# Usage: script/aws_deploy.sh [tag]   (defaults to the current git short SHA)
set -euo pipefail
cd "$(dirname "$0")/.."

tf() { terraform -chdir=terraform output -raw "$1"; }
REGION=$(tf aws_region)
REPO=$(tf ecr_repository_url)
INSTANCE_ID=$(tf instance_id)
PLATFORM=$(tf docker_platform)
TAG="${1:-$(git rev-parse --short HEAD)}"

echo "==> Building $REPO:$TAG ($PLATFORM)"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "${REPO%%/*}"
docker build --platform "$PLATFORM" -t "$REPO:$TAG" -t "$REPO:latest" .
docker push "$REPO:$TAG"
docker push "$REPO:latest"

echo "==> Deploying on $INSTANCE_ID"
script/aws_run.sh "/opt/game_platform/bin/deploy $TAG"
