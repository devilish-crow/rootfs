#!/bin/ash
# Just to add a default
wget https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/alpine-minirootfs-3.23.2-x86_64.tar.gz
mkdir -p ~/.config/rootfs/alpine
tar -xzf alpine-minirootfs-3.23.2-x86_64.tar.gz -C ~/.config/rootfs/alpine
rm alpine-minirootfs-3.23.2-x86_64.tar.gz

doas apk add bubblewrap fuse3 fuse-overlayfs
cp main.sh ~/.config/rootfs/main.sh
echo "alias 'rootfs'='ash ~/.config/rootfs/main.sh'" >> ~/.profile
