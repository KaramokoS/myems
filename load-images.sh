#!/usr/bin/env bash
# ==============================================================================
# Helper script to load packaged MyEMS images on the Linux Portainer host
# Usage: ./load-images.sh [path-to-archive.tar.gz]
# ==============================================================================

set -euo pipefail

ARCHIVE="${1:-}"

if [ -z "$ARCHIVE" ]; then
    # Try finding an archive in current directory or /tmp
    FOUND=$(find . /tmp -maxdepth 1 -name "myems-images-*.tar.gz" 2>/dev/null | head -n 1 || true)
    if [ -n "$FOUND" ]; then
        ARCHIVE="$FOUND"
    else
        echo "Usage: $0 <path-to-myems-images.tar.gz>"
        exit 1
    fi
fi

if [ ! -f "$ARCHIVE" ]; then
    echo "Error: File '$ARCHIVE' does not exist."
    exit 1
fi

echo "===> Loading Docker images from $ARCHIVE..."
docker load < "$ARCHIVE"

echo "===> Verification: Loaded MyEMS images:"
docker images | grep -E "myems/(myems-api|myems-web|myems-admin|myems-aggregation|myems-cleaning|myems-normalization|myems-modbus-tcp)" || docker images | grep myems

echo "===> Done! Images are ready for Portainer stack deployment."
