#!/bin/bash
# First-boot setup (run by cloud-init): Docker, swap, persistent data volume, then start the stack.
set -euxo pipefail
source /etc/game_platform/config.env

dnf install -y docker amazon-ecr-credential-helper

mkdir -p /usr/local/lib/docker/cli-plugins
curl -fsSL "https://github.com/docker/compose/releases/download/$COMPOSE_VERSION/docker-compose-linux-$(uname -m)" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

systemctl enable --now docker

# 2 GiB swap: gives Mongo + Rails headroom on small instances.
if [ ! -f /swapfile ]; then
  dd if=/dev/zero of=/swapfile bs=1M count=2048
  chmod 600 /swapfile
  mkswap /swapfile
  echo "/swapfile none swap defaults 0 0" >> /etc/fstab
fi
swapon -a

# The EBS data volume is attached after the instance boots; wait for it by volume id.
DEVICE="/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_${DATA_VOLUME_ID/-/}"
for _ in $(seq 1 60); do
  [ -e "$DEVICE" ] && break
  sleep 5
done
[ -e "$DEVICE" ] || { echo "Data volume $DATA_VOLUME_ID never attached" >&2; exit 1; }

blkid "$DEVICE" || mkfs.xfs "$DEVICE"
UUID=$(blkid -s UUID -o value "$DEVICE")
grep -q "$UUID" /etc/fstab || echo "UUID=$UUID /data xfs defaults,nofail 0 2" >> /etc/fstab
mkdir -p /data
mount -a
mkdir -p /data/mongo /data/caddy

# On the very first boot no image has been pushed yet; script/aws_deploy.sh will start the app.
/opt/game_platform/bin/deploy latest || true
