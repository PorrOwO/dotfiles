#!/bin/bash

# program parameters
NPROC=$1
RAM=$2

# usage prompt
if [[ -z "$NPROC" || -z "$RAM" ]]; then
    echo "Usage: $0 <num_cpus> <ram_memory>"
    echo "Example: $0 2 2G"
    exit 1
fi

# base URL where all images of v2 are found
BASE_URL="https://www.cs.unibo.it/~renzo/virtualsquare/daily_brewed/daily/"

# the latest images will be downloaded in the /images directory
DOWNLOAD_DIR="./images"
mkdir -p "$DOWNLOAD_DIR"

echo "Getting latest image..."
LATEST_FILE=$(wget -qO- "$BASE_URL" | grep -oE 'debian-sid-v2-amd64-daily-[0-9]{8}-[0-9]{4}\.qcow2\.bz2' | sort -r | head -n1)

if [[ -z "$LATEST_FILE" ]]; then
    echo "Could not find a matching image."
    exit 1
fi

LOCAL_BZ2="$DOWNLOAD_DIR/$LATEST_FILE"
QCOW2_FILE="$(realpath "${LOCAL_BZ2%.bz2}")"

# download and decompress if needed
if [[ -f "$QCOW2_FILE" ]]; then 
    echo "Latest image already exists: $QCOW2_FILE"
else 
    echo "Downloading $LATEST_FILE ..."
    wget -c "$BASE_URL$LATEST_FILE" -O "$LOCAL_BZ2"

    echo "Decompressing image ..."
    bunzip2 -f "$LOCAL_BZ2"
    
    if [[ ! -f "$QCOW2_FILE" ]]; then
        echo "Error: Decompression failed, $QCOW2_FILE not found."
        exit 1
    fi

    echo "Image is now ready: $QCOW2_FILE"
fi

echo "Cleaning up older images ..."
find "$DOWNLOAD_DIR" -type f -name "debian-sid-v2-amd64-daily-*.qcow2" ! -name "$(basename "$QCOW2_FILE")" -exec rm -f {} +

# Persistent overlay file
OVERLAY_FILE="$(realpath "$DOWNLOAD_DIR/persistent_overlay.qcow2")"

# If overlay doesn’t exist, create it
if [[ ! -f "$OVERLAY_FILE" ]]; then
    echo "Creating persistent overlay disk..."
    qemu-img create -f qcow2 -b "$QCOW2_FILE" -F qcow2 "$OVERLAY_FILE"
else
    echo "Rebasing overlay to new base image..."
    qemu-img rebase -u -b "$QCOW2_FILE" "$OVERLAY_FILE"
fi

echo "Starting QEMU virtual machine"
qemu-system-x86_64 -enable-kvm -smp "$NPROC" -m "$RAM" -monitor stdio -cpu host \
    -netdev type=user,id=net,hostfwd=tcp::2222-:22 -device virtio-net-pci,netdev=net \
    -drive file="$OVERLAY_FILE",format=qcow2,if=virtio
