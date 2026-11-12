#!/bin/bash
# =============================================================================
# Project 05 - configure-web.sh
# Run INSIDE vm-web1 by the Custom Script Extension (as root).
#
# What it does (the "contractor's instructions"):
#   1. Finds the data disk attached at LUN 0, partitions, formats and mounts it
#      at /data (and adds it to /etc/fstab so it survives reboots)
#   2. Installs Nginx (needs outbound internet - provided by the NAT Gateway)
#   3. Publishes a web page, stored on the data disk, showing the server name
#
# Safe to run more than once (idempotent).
# Log file inside the VM: /var/log/configure-web.log
# =============================================================================
set -euo pipefail
exec > >(tee -a /var/log/configure-web.log) 2>&1
echo "=== configure-web.sh started $(date -u) ==="

# ----------------------------- 1. Data disk ----------------------------------
# Azure creates stable links for data disks by LUN number
DISK=""
for LINK in /dev/disk/azure/data/by-lun/0 /dev/disk/azure/scsi1/lun0; do
  if [ -e "$LINK" ]; then
    DISK=$(readlink -f "$LINK")
    break
  fi
done
if [ -z "$DISK" ]; then
  echo "ERROR: no data disk found at LUN 0. Attach a data disk to the VM first."
  exit 1
fi
echo "Data disk found: $DISK"

case "$DISK" in
  *nvme*) PART="${DISK}p1" ;;
  *)      PART="${DISK}1" ;;
esac

if mountpoint -q /data; then
  echo "/data is already mounted - skipping disk setup"
else
  if [ ! -b "$PART" ]; then
    echo "Creating partition and ext4 file system on $DISK..."
    parted -s "$DISK" mklabel gpt mkpart primary ext4 0% 100%
    partprobe "$DISK"
    udevadm settle
    mkfs.ext4 -q -L datadisk "$PART"
  fi
  mkdir -p /data
  UUID=$(blkid -s UUID -o value "$PART")
  # nofail = the VM still boots if the disk is ever detached
  grep -q "$UUID" /etc/fstab || echo "UUID=$UUID /data ext4 defaults,nofail 0 2" >> /etc/fstab
  mount /data
  echo "Mounted $PART at /data"
fi

# ----------------------------- 2. Nginx --------------------------------------
export DEBIAN_FRONTEND=noninteractive
echo "Installing Nginx..."
apt-get update -y -q
apt-get install -y -q nginx

# ----------------------------- 3. Web page on the data disk ------------------
mkdir -p /data/www
cat > /data/www/index.html <<EOF
<!DOCTYPE html>
<html>
<head><title>AZ-104 Project 05</title></head>
<body style="font-family: sans-serif; margin: 40px;">
  <h1>AZ-104 Project 05 - $(hostname)</h1>
  <p>Private IP: $(hostname -I | awk '{print $1}')</p>
  <p>Configured by the Custom Script Extension at $(date -u) UTC</p>
  <p>This page is served from the data disk mounted at /data.</p>
</body>
</html>
EOF

# Point Nginx at the data disk instead of the OS disk
sed -i 's#root /var/www/html;#root /data/www;#' /etc/nginx/sites-available/default
systemctl enable nginx
systemctl restart nginx

# ----------------------------- Summary ---------------------------------------
echo ""
echo "=== Disks ==="
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
echo ""
echo "=== /data ==="
df -h /data
echo ""
echo "=== Nginx ==="
systemctl is-active nginx
echo "=== configure-web.sh finished $(date -u) ==="
