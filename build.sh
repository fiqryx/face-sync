#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

CWD=$(pwd)
TARGET_DIR="../sources"
BUILD_DIR="$CWD/build"
VERSION_JSON="$CWD/version.json"

case "$1" in
    --cuda)     PARAM="cuda" ;;
    --directml) PARAM="directml" ;;
    --openvino) PARAM="openvino" ;;
    --cpu|*)    PARAM="cpu" ;;
esac

echo "🚀 [START] Starting Automated Dynamic Build & Packing Process..."
if [ ! -d "$TARGET_DIR" ]; then
    echo "❌ Error: Target directory '$TARGET_DIR' not found!"
    echo "Please verify that the relative path  exists."
    exit 1
fi

if [ ! -f "$VERSION_JSON" ]; then
    echo "❌ Error: File version.json not found at $VERSION_JSON!"
    exit 1
fi

# Dynamically parse "version": "x.x.x" using pure Bash grep + sed (cross-platform friendly)
BACKEND_VER=$(jq -r '.backend.version' "$VERSION_JSON")

if [ -z "$BACKEND_VER" ]; then
    echo "⚠️  Warning: Failed to detect version from JSON. Falling back to default: 1.0.0"
    BACKEND_VER="1.0.0"
else
    echo "🏷️  Successfully detected project version: v$BACKEND_VER"
fi

# Clean up any existing build directory and create a fresh one
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "📦 [1/4] Processing Backend..."
cd "$TARGET_DIR/backend"

echo "🛠️  Compiling Go binary for Linux AMD64..."
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -ldflags="-w -s" -o backend main.go

echo "🤐 Compressing Backend to .tar.gz..."
tar -czf "$BUILD_DIR/backend_${BACKEND_VER}_linux_amd64.tar.gz" backend --transform 's|^./packages/models|models|' ./packages/models/

# Clean up the local temporary binary after packing
rm backend
echo "✅ Backend successfully compressed."

echo "📦 [2/4] Processing Worker..."
cd "$CWD"
cd "$TARGET_DIR/worker"
WORKER_VER=$(jq -r '.worker.version' "$VERSION_JSON")

echo "🤐 Compressing Worker binary & Models folder to .tar.gz..."
tar -czf "$BUILD_DIR/worker_${WORKER_VER}_${PARAM}_linux_amd64.tar.gz" main.bin models
echo "✅ Worker successfully compressed."

echo "📦 [3/4] Processing Updater..."
cd "$CWD"
cd "$TARGET_DIR/updater"
UPDATER_VER=$(jq -r '.updater.version' "$VERSION_JSON")

echo "🛠️  Compiling Updater binary for Linux AMD64..."
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -ldflags="-w -s" -o updater main.go

echo "🤐 Compressing Updater to .tar.gz..."
tar -czf "$BUILD_DIR/updater_${UPDATER_VER}_linux_amd64.tar.gz" updater

# Clean up the local temporary binary after packing
rm updater
echo "✅ Updater successfully compressed."

echo "📦 [4/4] Processing WebUI..."
cd "$CWD"
cd "$TARGET_DIR/web-ui"
WEBUI_VER=$(jq -r '.webui.version' "$VERSION_JSON")

echo "🛠️  Running Next.js production build in standalone mode..."
bun run build

echo "📁 Injecting required static assets directly into the standalone directory..."
# Inject static assets into the standalone directory structure
if [ -d ".next/static" ]; then
    mkdir -p .next/standalone/.next
    cp -r .next/static .next/standalone/.next/
fi

if [ -d "public" ]; then
    cp -r public .next/standalone/
fi

# Navigate directly into the built standalone directory for isolated compression
cd .next/standalone

echo "🤐 Compressing WebUI Complete Standalone structure to .tar.gz..."
tar -czf "$BUILD_DIR/webui_${WEBUI_VER}_linux_amd64.tar.gz" .

# Return to the initial working directory
cd "$CWD"
echo "✅ WebUI successfully compressed."

# =====================================================================
# FINISHING
# =====================================================================
echo "--------------------------------------------------------"
echo "🏁 [SUCCESS] Full dynamic build and packing complete!"
echo "📂 All 4 artifacts located in: $BUILD_DIR"
echo "--------------------------------------------------------"
ls -lh "$BUILD_DIR"