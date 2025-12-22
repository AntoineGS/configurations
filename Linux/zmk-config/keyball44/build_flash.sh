#!/bin/zsh
set -e

# Check if side argument is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <left|right|reset|update> [debug]"
    echo "Examples:"
    echo "  $0 left              - Build and flash left side"
    echo "  $0 right debug       - Build and flash right side with USB logging"
    echo "  $0 reset             - Flash settings reset firmware"
    echo "  $0 update            - Update west dependencies"
    exit 1
fi

SIDE=$1
DEBUG_MODE=$2

# Validate side argument
if [ "$SIDE" != "left" ] && [ "$SIDE" != "right" ] && [ "$SIDE" != "reset" ] && [ "$SIDE" != "update" ]; then
    echo "Error: Side must be 'left', 'right', 'reset', or 'update'"
    echo "Usage: $0 <left|right|reset|update> [debug]"
    exit 1
fi

# Set side-specific variables
if [ "$SIDE" = "left" ]; then
    SHIELD="keyball44_left nice_view_adapter nice_view_custom"
    # SHIELD="keyball44_left nice_view_adapter nice_view"
elif [ "$SIDE" = "right" ]; then
    SHIELD="keyball44_right nice_view_adapter nice_view"
elif [ "$SIDE" = "reset" ]; then
    SHIELD="settings_reset"
fi

# Workspace is in the keyball44 config directory
WORKSPACE_DIR="/home/antoinegs/gits/configurations/Linux/zmk-config/keyball44"
BUILD_DIR="build/$SIDE"
WEST="/home/antoinegs/gits/configurations/Linux/zmk-config/keyball44/zmk/.venv/bin/west"

echo "========================================"
echo "Building firmware for $SIDE side"
echo "Shield: $SHIELD"
echo "========================================"

# Navigate to workspace
cd "$WORKSPACE_DIR"

if [ "$SIDE" = "update" ]; then
    echo "Updating west and submodules..."
    $WEST update
    echo ""
    echo "========================================"
    echo "Update completed successfully!"
    echo "========================================"
    exit 0
fi

# Build firmware
SNIPPET_FLAGS=""
if [ "$DEBUG_MODE" = "debug" ]; then
    echo "USB logging enabled"
    SNIPPET_FLAGS="-S zmk-usb-logging"
fi

$WEST build -s zmk/app -d "$BUILD_DIR" -p -b nice_nano $SNIPPET_FLAGS -- -DSHIELD="$SHIELD" -DZMK_CONFIG="$WORKSPACE_DIR"

if [ $? -ne 0 ]; then
    echo "Build failed!"
    exit 1
fi

echo ""
echo "========================================"
echo "Build successful! Starting flash process..."
echo "========================================"

# Flash firmware
UF2_FILE="$BUILD_DIR/zephyr/zmk.uf2"

if [ ! -f "$UF2_FILE" ]; then
    echo "Error: Firmware file not found at $UF2_FILE"
    exit 1
fi

echo "Flashing $UF2_FILE to $SIDE nice_nano_v2"
echo "Please double-tap reset button on Nice Nano to enter bootloader mode..."

# Wait for the device to appear (not the mount, the block device)
DEVICE=""
for i in {1..60}; do
    # Look for the NICENANO device by label (it's a disk, not a partition)
    DEVICE=$(lsblk -o NAME,LABEL,TYPE | grep NICENANO | grep disk | awk '{print "/dev/" $1}')
    if [ -n "$DEVICE" ]; then
        echo "Found device: $DEVICE"
        break
    else
        echo "Waiting for NICENANO device to appear... ($i/60)"
        sleep 2
    fi
done

if [ -z "$DEVICE" ]; then
    echo "Error: NICENANO device not found after waiting"
    exit 1
fi

# Mount the device using udisksctl (this triggers the same mount as Files app)
echo "Mounting $DEVICE..."
MOUNT_POINT=$(udisksctl mount -b $DEVICE 2>&1 | grep -oP 'Mounted .* at \K.*' | tr -d '.')

if [ -z "$MOUNT_POINT" ]; then
    # Device might already be mounted, try to find it
    MOUNT_POINT=$(lsblk -o NAME,LABEL,MOUNTPOINT | grep NICENANO | awk '{print $3}')
    if [ -z "$MOUNT_POINT" ]; then
        echo "Error: Failed to mount device"
        exit 1
    fi
    echo "Device already mounted at: $MOUNT_POINT"
else
    echo "Mounted at: $MOUNT_POINT"
fi

# Copy firmware
echo "Copying firmware..."
cp "$UF2_FILE" "$MOUNT_POINT/"

# Sync to ensure write completes
sync

echo ""
echo "========================================"
echo "Firmware flashed successfully!"
echo "Device will automatically unmount and reboot."
echo "========================================"
