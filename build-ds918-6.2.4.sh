
#!/usr/bin/env bash
set -Eeuo pipefail

echo "======================================"
echo " RedPill DS918+ DSM 6.2.4-25556 Build"
echo "======================================"

# Build dependencies
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  ca-certificates build-essential git libssl-dev \
  curl cpio bsdiff vim gettext bc bison flex \
  dosfstools kmod jq file xz-utils

ROOT="$(pwd)"
BUILD_DIR="${ROOT}/ds918-6.2.4"
OUTPUT_DIR="${ROOT}/output"

mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
cd "$BUILD_DIR"

# Download RedPill sources
if [ ! -d redpill-lkm ]; then
  git clone --depth=1 \
    https://github.com/RedPill-TTG/redpill-lkm.git
fi

if [ ! -d redpill-load ]; then
  git clone --depth=1 \
    https://github.com/RedPill-TTG/redpill-load.git
fi

# Download Synology kernel source
KERNEL_URL="https://sourceforge.net/projects/dsgpl/files/Synology%20NAS%20GPL%20Source/25426branch/apollolake-source/linux-4.4.x.txz/download"

echo "Downloading Synology kernel source..."

curl -fL \
  --retry 3 \
  --connect-timeout 30 \
  --max-time 600 \
  "$KERNEL_URL" \
  -o linux-4.4.x.txz

echo "Downloaded archive:"
ls -lh linux-4.4.x.txz
file linux-4.4.x.txz

# Verify archive
if ! xz -t linux-4.4.x.txz; then
  echo "ERROR: Invalid XZ archive."
  echo "SourceForge may have returned HTML."
  exit 1
fi

echo "Kernel archive verification passed."

# Build RedPill LKM
cd "$BUILD_DIR/redpill-lkm"

tar -xf ../linux-4.4.x.txz

LINUX_SRC="$(find . -maxdepth 1 \
  -type d -name 'linux-4.4*' -print -quit)"

if [ -z "$LINUX_SRC" ]; then
  echo "ERROR: Linux source directory not found."
  exit 1
fi

cd "$LINUX_SRC"
LINUX_SRC="$(pwd)"

if [ ! -f synoconfigs/apollolake ]; then
  echo "ERROR: ApolloLake kernel config missing."
  exit 1
fi

cp synoconfigs/apollolake .config
echo '+' > .scmversion

make oldconfig
make modules_prepare

cd "$BUILD_DIR/redpill-lkm"

make LINUX_SRC="$LINUX_SRC" test-v6

if [ ! -f redpill.ko ]; then
  echo "ERROR: redpill.ko was not generated."
  exit 1
fi

KVERS="$(modinfo -F vermagic redpill.ko | awk '{print $1}')"

if [ -z "$KVERS" ]; then
  echo "ERROR: Cannot determine module version."
  exit 1
fi

cp -v redpill.ko \
  "$BUILD_DIR/redpill-load/ext/rp-lkm/redpill-linux-v${KVERS}.ko"

# Build loader
cd "$BUILD_DIR/redpill-load"

cp "$ROOT/user_config.DS918+.json" user_config.json

sudo ./build-loader.sh 'DS918+' '6.2.4-25556'

# Copy generated image
find images -maxdepth 1 -type f \
  -name 'redpill-DS918+_6.2.4-25556*.img' \
  -exec cp -v {} "$OUTPUT_DIR/" \;

if ! find "$OUTPUT_DIR" -maxdepth 1 \
  -name '*.img' | grep -q .; then
  echo "ERROR: No loader IMG generated."
  exit 1
fi

echo "======================================"
echo " Build completed successfully"
echo "======================================"
ls -lh "$OUTPUT_DIR"
