#!/usr/bin/env bash
# ==============================================================================
# MyEMS Docker Image Packaging Script (Gzip)
# 
# Exports and compresses MyEMS Docker images into a single .tar.gz archive.
# Can be transferred via scp/rsync to a Linux machine and loaded into Docker.
# ==============================================================================

set -euo pipefail

# Default Configuration
TAG="${TAG:-v6.9.0}"
PREFIX="${PREFIX:-myems}"
OUTPUT_FILE=""
INCLUDE_ALL=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Exports MyEMS images and compresses them into a single .tar.gz archive.

Options:
  -t, --tag <tag>          Tag of images to package (default: v6.9.0)
  -p, --prefix <prefix>    Repository prefix (default: myems)
  -o, --output <file>      Output .tar.gz file path (default: dist/myems-images-<tag>.tar.gz)
      --all                Also package optional protocol drivers (opc-ua, bacnet, s7)
  -h, --help               Show this help message

Examples:
  $(basename "$0")                               # Package core services for tag v6.9.0
  $(basename "$0") -t v6.9.0 -o ./my-images.tar.gz
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -t|--tag)
            TAG="$2"
            shift 2
            ;;
        -p|--prefix)
            PREFIX="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --all)
            INCLUDE_ALL=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            ;;
    esac
done

# Default output file in dist/
if [ -z "$OUTPUT_FILE" ]; then
    mkdir -p "$SCRIPT_DIR/dist"
    OUTPUT_FILE="$SCRIPT_DIR/dist/myems-images-${TAG}.tar.gz"
else
    mkdir -p "$(dirname "$OUTPUT_FILE")"
fi

# List of service names to package
CORE_SERVICES=(
    "myems-api"
    "myems-admin"
    "myems-web"
    "myems-aggregation"
    "myems-cleaning"
    "myems-normalization"
    "myems-modbus-tcp"
)

if [ "$INCLUDE_ALL" = true ]; then
    CORE_SERVICES+=(
        "myems-opc-ua"
        "myems-bacnet"
        "myems-s7"
    )
fi

TARGET_IMAGES=()
echo -e "${CYAN}Checking available local images...${NC}"

for s in "${CORE_SERVICES[@]}"; do
    IMAGE_NAME="${PREFIX}/${s}:${TAG}"
    if docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
        TARGET_IMAGES+=("$IMAGE_NAME")
        echo -e "  ${GREEN}✓ Found:${NC} $IMAGE_NAME"
    else
        echo -e "  ${RED}✗ Missing:${NC} $IMAGE_NAME (Build it first with ./build-and-push.sh)"
    fi
done

if [ ${#TARGET_IMAGES[@]} -eq 0 ]; then
    echo -e "\n${RED}Error: No matching images found in local Docker daemon.${NC}"
    echo -e "Please run ${YELLOW}./build-and-push.sh --tag ${TAG}${NC} first."
    exit 1
fi

echo -e "\n${BLUE}====================================================${NC}"
echo -e "${BLUE}Saving and compressing ${#TARGET_IMAGES[@]} images...${NC}"
echo -e "${BLUE}Target File:${NC} ${YELLOW}${OUTPUT_FILE}${NC}"
echo -e "${BLUE}====================================================${NC}"

# Choose pigz (parallel gzip) if available, otherwise regular gzip
COMPRESS_CMD="gzip"
if command -v pigz >/dev/null 2>&1; then
    COMPRESS_CMD="pigz"
    echo -e "${CYAN}Using multi-threaded 'pigz' for faster compression.${NC}"
fi

# Save and gzip
docker save "${TARGET_IMAGES[@]}" | $COMPRESS_CMD > "$OUTPUT_FILE"

FILE_SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
echo -e "\n${GREEN}====================================================${NC}"
echo -e "${GREEN}✓ Archive created successfully!${NC}"
echo -e "  ${BLUE}File:${NC} $OUTPUT_FILE"
echo -e "  ${BLUE}Size:${NC} $FILE_SIZE"
echo -e "${GREEN}====================================================${NC}"

# Compute checksum if sha256sum / shasum exists
if command -v shasum >/dev/null 2>&1; then
    (cd "$(dirname "$OUTPUT_FILE")" && shasum -a 256 "$(basename "$OUTPUT_FILE")" > "$(basename "$OUTPUT_FILE").sha256")
    echo -e "  ${BLUE}SHA256:${NC} $(cat "${OUTPUT_FILE}.sha256")"
fi

cat << EOF

${CYAN}----------------------------------------------------${NC}
${YELLOW}How to load these images onto your Linux / Portainer host:${NC}
${CYAN}----------------------------------------------------${NC}

1. Copy the archive to your Linux host:
   scp "$OUTPUT_FILE" user@linux-host:/tmp/

2. On the Linux host, unpack and load into Docker:
   docker load < /tmp/$(basename "$OUTPUT_FILE")

3. Verify images are loaded:
   docker images | grep "${PREFIX}"

4. Deploy your Portainer stack using the pre-built image tags!
EOF
