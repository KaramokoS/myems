#!/usr/bin/env bash
# ==============================================================================
# MyEMS Docker Image Build Script
# 
# Builds and tags MyEMS services for Linux deployment (default: linux/amd64).
# Designed for building on macOS (Apple Silicon/Intel) for Linux Portainer hosts.
# ==============================================================================

set -euo pipefail

# Default Configuration
TAG="${TAG:-v6.9.0}"
PREFIX="${PREFIX:-myems}"
PLATFORM="${PLATFORM:-linux/amd64}"
DO_PUSH=false
DO_GZIP=false
INCLUDE_ALL=false
OUTPUT_FILE=""
SINGLE_SERVICE=""

# Color definitions for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Base directory (repository root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Builds and tags MyEMS Docker images for a target Linux platform.

Options:
  -s, --service <name>     Build only a specific service (e.g. myems-web)
  -t, --tag <tag>          Tag for the images (default: v6.9.0)
  -p, --prefix <prefix>    Repository prefix (default: myems)
      --platform <arch>    Target platform (default: linux/amd64)
  -g, --gzip               Automatically package images into a .tar.gz archive
  -o, --output <file>      Custom output path for the gzip archive
      --all                Also build optional protocol drivers (opc-ua, bacnet, s7)
      --push               Push images to registry after building (default: false)
  -h, --help               Show this help message

Examples:
  $(basename "$0")                               # Build core services for linux/amd64
  $(basename "$0") --gzip                        # Build and package directly into a .tar.gz
  $(basename "$0") --platform linux/arm64        # Build for ARM64 Linux (e.g. Raspberry Pi / Graviton)
  $(basename "$0") --tag v6.9.0 --prefix myreg   # Build with custom prefix and tag
EOF
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--service)
            SINGLE_SERVICE="$2"
            shift 2
            ;;
        -t|--tag)
            TAG="$2"
            shift 2
            ;;
        -p|--prefix)
            PREFIX="$2"
            shift 2
            ;;
        --platform)
            PLATFORM="$2"
            shift 2
            ;;
        -g|--gzip)
            DO_GZIP=true
            shift
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            DO_GZIP=true
            shift 2
            ;;
        --all)
            INCLUDE_ALL=true
            shift
            ;;
        --push)
            DO_PUSH=true
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

echo -e "${CYAN}====================================================${NC}"
echo -e "${CYAN}           MyEMS Docker Build System               ${NC}"
echo -e "${CYAN}====================================================${NC}"
echo -e "${BLUE}Target Platform :${NC} ${YELLOW}${PLATFORM}${NC}"
echo -e "${BLUE}Image Prefix    :${NC} ${YELLOW}${PREFIX}${NC}"
echo -e "${BLUE}Tag             :${NC} ${YELLOW}${TAG}${NC} (and latest)"
echo -e "${BLUE}Push to registry:${NC} ${YELLOW}${DO_PUSH}${NC}"
echo -e "${BLUE}Gzip archive    :${NC} ${YELLOW}${DO_GZIP}${NC}"
echo -e "${CYAN}----------------------------------------------------${NC}"

# Core services used in docker-compose.portainer.yml
# Format: "service_name:context_directory:dockerfile"
SERVICES=(
    "myems-api:myems-api:Dockerfile"
    "myems-admin:myems-admin:Dockerfile"
    "myems-web:myems-web:Dockerfile"
    "myems-aggregation:myems-aggregation:Dockerfile"
    "myems-cleaning:myems-cleaning:Dockerfile"
    "myems-normalization:myems-normalization:Dockerfile"
    "myems-modbus-tcp:myems-modbus-tcp:Dockerfile"
)

# Optional protocol drivers
if [ "$INCLUDE_ALL" = true ]; then
    SERVICES+=(
        "myems-opc-ua:myems-opc-ua:Dockerfile"
        "myems-bacnet:myems-bacnet:Dockerfile"
        "myems-s7:myems-s7:Dockerfile"
    )
fi

# Filter if single service is requested
if [ -n "$SINGLE_SERVICE" ]; then
    FILTERED_SERVICES=()
    for entry in "${SERVICES[@]}"; do
        IFS=":" read -r name context_dir dockerfile <<< "$entry"
        if [ "$name" = "$SINGLE_SERVICE" ] || [ "$context_dir" = "$SINGLE_SERVICE" ]; then
            FILTERED_SERVICES+=("$entry")
        fi
    done
    if [ ${#FILTERED_SERVICES[@]} -eq 0 ]; then
        echo -e "${RED}Error: Service '$SINGLE_SERVICE' not recognized.${NC}"
        echo "Available services: myems-api, myems-admin, myems-web, myems-aggregation, myems-cleaning, myems-normalization, myems-modbus-tcp"
        exit 1
    fi
    SERVICES=("${FILTERED_SERVICES[@]}")
fi

# Track successfully built images
BUILT_IMAGES=()

# Determine builder tool (buildx or standard build)
BUILD_CMD=()
if docker buildx version >/dev/null 2>&1; then
    BUILD_CMD=(docker buildx build --platform "$PLATFORM" --load)
else
    BUILD_CMD=(docker build --platform "$PLATFORM")
fi

echo -e "\n${BLUE}[1/2] Building images for ${PLATFORM}...${NC}"

for entry in "${SERVICES[@]}"; do
    IFS=":" read -r name context_dir dockerfile <<< "$entry"
    FULL_TAG="${PREFIX}/${name}:${TAG}"
    LATEST_TAG="${PREFIX}/${name}:latest"
    
    echo -e "\n${YELLOW}===> Building ${name} from ./${context_dir}...${NC}"
    
    if [ ! -d "$context_dir" ]; then
        echo -e "${RED}Error: Directory ${context_dir} not found! Skipping.${NC}"
        continue
    fi
    
    "${BUILD_CMD[@]}" \
        -f "${context_dir}/${dockerfile}" \
        -t "$FULL_TAG" \
        -t "$LATEST_TAG" \
        "$context_dir"
        
    echo -e "${GREEN}✓ Successfully built ${FULL_TAG} and ${LATEST_TAG}${NC}"
    BUILT_IMAGES+=("$FULL_TAG")
done

echo -e "\n${GREEN}====================================================${NC}"
echo -e "${GREEN}✓ All ${#BUILT_IMAGES[@]} images successfully built for ${PLATFORM}!${NC}"
echo -e "${GREEN}====================================================${NC}"

for img in "${BUILT_IMAGES[@]}"; do
    echo "  - $img"
done

# Optional push
if [ "$DO_PUSH" = true ]; then
    echo -e "\n${BLUE}Pushing images to registry...${NC}"
    for img in "${BUILT_IMAGES[@]}"; do
        echo -e "${YELLOW}===> Pushing $img...${NC}"
        docker push "$img"
        # also push latest
        latest="${img%:*}:latest"
        docker push "$latest"
    done
    echo -e "${GREEN}✓ All images pushed successfully!${NC}"
fi

# Gzip archive packaging
if [ "$DO_GZIP" = true ]; then
    echo -e "\n${BLUE}[2/2] Packaging images into gzip archive...${NC}"
    GZIP_ARGS=("-t" "$TAG" "-p" "$PREFIX")
    if [ "$INCLUDE_ALL" = true ]; then
        GZIP_ARGS+=("--all")
    fi
    if [ -n "$OUTPUT_FILE" ]; then
        GZIP_ARGS+=("-o" "$OUTPUT_FILE")
    fi
    "$SCRIPT_DIR/package-images.sh" "${GZIP_ARGS[@]}"
else
    echo -e "\n${CYAN}Tip: To package these images into a .tar.gz for Portainer, run:${NC}"
    echo -e "  ${YELLOW}./package-images.sh --tag ${TAG} --prefix ${PREFIX}${NC}"
fi
