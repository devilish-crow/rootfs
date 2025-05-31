#!/bin/ash
wget https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/alpine-minirootfs-3.22.0-x86_64.tar.gz
mkdir -p ~/rootfs/alpine
tar -xzf alpine-minirootfs-3.22.0-x86_64.tar.gz -C ~/rootfs/alpine
rm alpine-minirootfs-3.22.0-x86_64.tar.gz
doas apk add bubblewrap fuse3 fuse-overlayfs
echo "alias 'rootfs'='ash ~/rootfs/main.sh'" >> ~/.profile
