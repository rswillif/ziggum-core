#!/bin/bash
set -e

LIB_NAME="libziggum"
# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log() {
    echo -e "[$(date +'%H:%M:%S')] $1"
}

# Check for Zig
if ! command -v zig &> /dev/null; then
    log "${RED}Error: Zig is not installed.${NC}"
    exit 1
fi

log "${GREEN}Building $LIB_NAME...${NC}"

# Build the dynamic library
zig build -Doptimize=ReleaseSafe

if [ -d "zig-out/lib" ]; then
    log "${GREEN}Build successful! Library located in zig-out/lib/$(ls zig-out/lib | grep ziggum)${NC}"
else
    log "${RED}Build failed: zig-out/lib not found.${NC}"
    exit 1
fi
