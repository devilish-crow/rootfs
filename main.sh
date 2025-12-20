#!/bin/ash
set -e
if [ -z "$1" ]; then
    echo "Usage: $0 create [-p] <rootfs> [name] | login <sandbox-name> | clean <sandbox-name|all> | list | rename <old-name> <new-name>"
    exit 1
fi
ROOTFS_BASE="/home/$USER/.config/rootfs"

create() {
    if [ "$1" = "-p" ]; then
        PERSISTENT=1
        shift
    fi
    ROOTFS="$ROOTFS_BASE/$1"
    ROOTFS_NAME=$(basename "$ROOTFS")
    if [ ! -d "$ROOTFS" ]; then
        echo "Error: rootfs '$ROOTFS' does not exist."
        exit 1
    fi
    if [ -n "$2" ]; then
        SANDBOX_NAME="$2"
    else
        SANDBOX_NAME="${ROOTFS_NAME}-$(head /dev/urandom | tr -dc a-z0-9 | head -c6)"
    fi
    if [ "$PERSISTENT" = "1" ]; then
        SANDBOX_BASE="/home/$USER/.config/rootfs/sandboxes/internals"
    else
        SANDBOX_BASE="/tmp/rootfs/sandboxes"
    fi
    STATE_DIR="$SANDBOX_BASE/$SANDBOX_NAME"
    UPPER_DIR="$STATE_DIR/upper"
    WORK_DIR="$STATE_DIR/work"
    MERGED_DIR="$STATE_DIR/merged"
    mkdir -p "$UPPER_DIR" "$WORK_DIR" "$MERGED_DIR"
    
    # Copy host's resolv.conf to upper layer
    mkdir -p "$UPPER_DIR/etc"
    cp /etc/resolv.conf "$UPPER_DIR/etc/resolv.conf" 2>/dev/null || true
    
    fuse-overlayfs -o lowerdir="$ROOTFS",upperdir="$UPPER_DIR",workdir="$WORK_DIR" "$MERGED_DIR"
    if [ $? -ne 0 ]; then
        echo "Fuse-overlayfs failed to mount."
        exit 1
    fi
    cat <<EOF > "$STATE_DIR/env"
SANDBOX_NAME=$SANDBOX_NAME
SANDBOX_LOWER=$ROOTFS
SANDBOX_STATE_DIR=$STATE_DIR
EOF
    
    # Create symlink for persistent sandboxes
    if [ "$PERSISTENT" = "1" ]; then
        ln -s "$STATE_DIR" "/home/$USER/.config/rootfs/sandboxes/$SANDBOX_NAME"
    fi
    
    echo "Created $SANDBOX_NAME"
}

login() {
    # Try persistent location first (follow symlink)
    STATE_DIR="/home/$USER/.config/rootfs/sandboxes/$1"
    if [ -L "$STATE_DIR" ]; then
        STATE_DIR=$(readlink -f "$STATE_DIR")
    fi
    if [ ! -f "$STATE_DIR/env" ]; then
        # Fall back to ephemeral location
        STATE_DIR="/tmp/rootfs/sandboxes/$1"
    fi
    if [ ! -f "$STATE_DIR/env" ]; then
        echo "Sandbox '$1' not found. Please use the full name of the sandbox (eg: alpine-mbwl0d)!"
        exit 1
    fi
    . "$STATE_DIR/env"
    bwrap \
      --unshare-user --uid 0 --gid 0 \
      --unshare-pid --unshare-ipc --unshare-uts --unshare-cgroup \
      --hostname "$SANDBOX_NAME" \
      --die-with-parent \
      --bind "$STATE_DIR/merged" / \
      --tmpfs /tmp \
      --proc /proc \
      --dev /dev \
      --chdir / \
      /bin/ash
}

list() {
    echo "Ephemeral sandboxes:"
    if [ -d "/tmp/rootfs/sandboxes" ]; then
        for STATE_DIR in /tmp/rootfs/sandboxes/*; do
            [ -d "$STATE_DIR" ] || continue
            echo "  $(basename "$STATE_DIR")"
        done
    fi
    echo "Persistent sandboxes:"
    if [ -d "/home/$USER/.config/rootfs/sandboxes" ]; then
        for STATE_DIR in /home/$USER/.config/rootfs/sandboxes/*; do
            [ -L "$STATE_DIR" ] || continue
            echo "  $(basename "$STATE_DIR")"
        done
    fi
}

rename_sandbox() {
    # Check persistent location (follow symlink)
    OLD_LINK="/home/$USER/.config/rootfs/sandboxes/$1"
    if [ -L "$OLD_LINK" ]; then
        OLD_DIR=$(readlink -f "$OLD_LINK")
        PERSISTENT=1
    else
        OLD_DIR="/tmp/rootfs/sandboxes/$1"
    fi
    if [ ! -d "$OLD_DIR" ]; then
        echo "Sandbox '$1' not found."
        exit 1
    fi
    NEW_DIR="$(dirname "$OLD_DIR")/$2"
    if [ -d "$NEW_DIR" ]; then
        echo "Sandbox '$2' already exists."
        exit 1
    fi
    mv "$OLD_DIR" "$NEW_DIR"
    sed -i "s/SANDBOX_NAME=.*/SANDBOX_NAME=$2/" "$NEW_DIR/env"
    sed -i "s|SANDBOX_STATE_DIR=.*|SANDBOX_STATE_DIR=$NEW_DIR|" "$NEW_DIR/env"
    
    # Update symlink for persistent sandboxes
    if [ "$PERSISTENT" = "1" ]; then
        rm "$OLD_LINK"
        ln -s "$NEW_DIR" "/home/$USER/.config/rootfs/sandboxes/$2"
    fi
    
    echo "Renamed $1 to $2"
}

clean() {
    if [ "$1" = "all" ] || [ "$1" = "*" ]; then
        echo "Cleaning all sandboxes..."
        # Clean ephemeral
        for STATE_DIR in /tmp/rootfs/sandboxes/*; do
            [ -f "$STATE_DIR/env" ] || continue
            fusermount3 -u "$STATE_DIR/merged" 2>/dev/null
            rm -rf "$STATE_DIR"
        done
        # Clean persistent (follow symlinks and remove them)
        for LINK in /home/$USER/.config/rootfs/sandboxes/*; do
            [ -L "$LINK" ] || continue
            STATE_DIR=$(readlink -f "$LINK")
            [ -f "$STATE_DIR/env" ] || continue
            fusermount3 -u "$STATE_DIR/merged" 2>/dev/null
            rm -rf "$STATE_DIR"
            rm "$LINK"
        done
        exit 0
    fi
    # Try persistent location first (follow symlink)
    LINK="/home/$USER/.config/rootfs/sandboxes/$1"
    if [ -L "$LINK" ]; then
        STATE_DIR=$(readlink -f "$LINK")
        PERSISTENT=1
    else
        STATE_DIR="/tmp/rootfs/sandboxes/$1"
    fi
    if [ ! -f "$STATE_DIR/env" ]; then
        echo "Sandbox '$1' not found. Please use the full name of the sandbox (eg: alpine-mbwl0d)!"
        exit 1
    fi
    fusermount3 -u "$STATE_DIR/merged" 2>/dev/null
    rm -rf "$STATE_DIR"
    
    # Remove symlink for persistent sandboxes
    if [ "$PERSISTENT" = "1" ]; then
        rm "$LINK"
    fi
}

case "$1" in
    create)
        if [ "$2" = "-p" ]; then
            if [ -z "$3" ]; then
                echo "Usage: $0 create [-p] <relative/rootfs> [name]"
                exit 1
            fi
            create "$2" "$3" "$4"
        else
            if [ -z "$2" ]; then
                echo "Usage: $0 create [-p] <relative/rootfs> [name]"
                exit 1
            fi
            create "$2" "$3"
        fi
        ;;
    login)
        if [ -z "$2" ]; then
            echo "Usage: $0 login <instance-name>"
            exit 1
        fi
        login "$2"
        ;;
    list)
        list
        ;;
    rename)
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "Usage: $0 rename <old-name> <new-name>"
            exit 1
        fi
        rename_sandbox "$2" "$3"
        ;;
    clean)
        if [ -z "$2" ]; then
            echo "Usage: $0 clean <instance-name|all>"
            exit 1
        fi
        clean "$2"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Usage: $0 create [-p] <rootfs> [name] | login <instance-name> | list | rename <old-name> <new-name> | clean <instance-name|all>"
        exit 1
        ;;
esac
