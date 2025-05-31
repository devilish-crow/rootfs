#!/bin/ash
COMMAND="$1"
ARG="$2"

if [ -z "$COMMAND" ]; then
    echo "Usage: $0 create <rootfs> | login <sandbox-name> | clean <sandbox-name|all>"
    exit 1
fi

ROOTFS_BASE="/home/$USER/rootfs"
create_sandbox() {
    REL_PATH="$1"
    ROOTFS="$ROOTFS_BASE/$REL_PATH"
    ROOTFS_NAME=$(basename "$ROOTFS")

    if [ ! -d "$ROOTFS" ]; then
        echo "Error: rootfs '$ROOTFS' does not exist. You can look into ~/rootfs to see all your installed rootfs."
        exit 1
    fi

    SANDBOX_NAME="${ROOTFS_NAME}-$(head /dev/urandom | tr -dc a-z0-9 | head -c6)"
    STATE_DIR="/tmp/bwrap_sandbox_$SANDBOX_NAME"
    UPPER_DIR="$STATE_DIR/upper"
    WORK_DIR="$STATE_DIR/work"
    MERGED_DIR="$STATE_DIR/merged"
    mkdir -p "$UPPER_DIR" "$WORK_DIR" "$MERGED_DIR"

    fuse-overlayfs -o lowerdir="$ROOTFS",upperdir="$UPPER_DIR",workdir="$WORK_DIR" "$MERGED_DIR"
    if [ $? -ne 0 ]; then
        echo "Fuse-overlayfs failed to mount. How did we even get here?"
        exit 1
    fi

    cat <<EOF > "$STATE_DIR/env"
SANDBOX_NAME=$SANDBOX_NAME
SANDBOX_LOWER=$ROOTFS
SANDBOX_STATE_DIR=$STATE_DIR
EOF

    echo "$SANDBOX_NAME"
}

login_sandbox() {
    SANDBOX_NAME="$1"
    STATE_DIR="/tmp/bwrap_sandbox_$SANDBOX_NAME"
    ENV_FILE="$STATE_DIR/env"

    if [ ! -f "$ENV_FILE" ]; then
        echo "Sandbox '$SANDBOX_NAME' not found. Please use the full name of the sandbox (eg: alpine-mbwl0d)!"
        exit 1
    fi

    . "$ENV_FILE"
    MERGED_DIR="$STATE_DIR/merged"

    bwrap \
      --unshare-user --uid 0 --gid 0 \
      --unshare-pid --unshare-ipc --unshare-uts --unshare-cgroup \
      --hostname "$SANDBOX_NAME" \
      --die-with-parent \
      --bind "$MERGED_DIR" / \
      --tmpfs /tmp \
      --proc /proc \
      --dev /dev \
      --chdir / \
      /bin/ash
}

clean_sandbox() {
    ARG="$1"
    if [ "$ARG" = "all" ] || [ "$ARG" = "*" ]; then
        echo "Cleaning all sandboxes..."
        for STATE_DIR in /tmp/bwrap_sandbox_*; do
            [ -f "$STATE_DIR/env" ] || continue
            fusermount3 -u "$STATE_DIR/merged" 2>/dev/null
            rm -rf "$STATE_DIR"
        done
        exit 0
    fi

    SANDBOX_NAME="$ARG"
    STATE_DIR="/tmp/bwrap_sandbox_$SANDBOX_NAME"
    ENV_FILE="$STATE_DIR/env"

    if [ ! -f "$ENV_FILE" ]; then
        echo "Sandbox '$SANDBOX_NAME' not found. Please use the full name of the sandbox (eg: alpine-mbwl0d)!"
        exit 1
    fi

    fusermount3 -u "$STATE_DIR/merged" 2>/dev/null
    rm -rf "$STATE_DIR"
}

case "$COMMAND" in
    create)
        if [ -z "$ARG" ]; then
            echo "Usage: $0 create <relative/rootfs>"
            exit 1
        fi
        create_sandbox "$ARG"
        ;;
    login)
        if [ -z "$ARG" ]; then
            echo "Usage: $0 login <sandbox-name>"
            exit 1
        fi
        login_sandbox "$ARG"
        ;;
    clean)
        if [ -z "$ARG" ]; then
            echo "Usage: $0 clean <sandbox-name|all>"
            exit 1
        fi
        clean_sandbox "$ARG"
        ;;
    *)
        echo "Unknown command: $COMMAND"
        echo "Usage: $0 create <rootfs> | login <sandbox-name> | clean <sandbox-name|all>"
        exit 1
        ;;
esac
