#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "ERROR: build failed at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

ROOT="$(pwd)"
BUILD_DIR="${ROOT}/ds918-6.2.4"
OUTPUT_DIR="${ROOT}/output"
KERNEL_URL='https://global.synologydownload.com/download/ToolChain/Synology%20NAS%20GPL%20Source/6.2-25556/apollolake/linux-4.4.x.txz'
KERNEL_MD5='b0105c224ce0468391ce1027a90d944a'

echo '=== RedPill DS918+ DSM 6.2.4-25556 ==='
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  ca-certificates build-essential git libssl-dev curl cpio bsdiff \
  vim gettext bc bison flex dosfstools kmod jq file xz-utils

mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
cd "$BUILD_DIR"

if [[ ! -d redpill-lkm ]]; then
  git clone --depth=1 https://github.com/RedPill-TTG/redpill-lkm.git
fi
if [[ ! -d redpill-load ]]; then
  git clone --depth=1 https://github.com/RedPill-TTG/redpill-load.git
fi

printf '\nDownloading official Synology ApolloLake kernel source...\n'
curl --fail --location --retry 3 --retry-delay 5 \
  --connect-timeout 30 --max-time 1800 \
  "$KERNEL_URL" --output linux-4.4.x.txz
ls -lh linux-4.4.x.txz
file linux-4.4.x.txz
printf '%s  %s\n' "$KERNEL_MD5" linux-4.4.x.txz | md5sum --check --status || {
  echo 'ERROR: Synology source archive MD5 mismatch.' >&2
  exit 1
}
xz -t linux-4.4.x.txz

printf '\nPreparing kernel source...\n'
cd "$BUILD_DIR/redpill-lkm"
tar -xf ../linux-4.4.x.txz
LINUX_SRC="$(find "$PWD" -maxdepth 1 -mindepth 1 -type d -name 'linux-4.4*' -print -quit)"
[[ -n "$LINUX_SRC" ]] || { echo 'ERROR: linux-4.4 source directory not found.' >&2; exit 1; }
cd "$LINUX_SRC"
[[ -f synoconfigs/apollolake ]] || { echo 'ERROR: missing synoconfigs/apollolake.' >&2; exit 1; }
cp synoconfigs/apollolake .config
printf '+\n' > .scmversion
make oldconfig
make modules_prepare

printf '\nBuilding RedPill LKM...\n'
cd "$BUILD_DIR/redpill-lkm"
make LINUX_SRC="$LINUX_SRC" test-v6
[[ -s redpill.ko ]] || { echo 'ERROR: redpill.ko not generated.' >&2; exit 1; }
KVERS="$(modinfo -F vermagic redpill.ko | awk '{print $1}')"
[[ -n "$KVERS" ]] || { echo 'ERROR: unable to read module vermagic.' >&2; exit 1; }
DEST="$BUILD_DIR/redpill-load/ext/rp-lkm/redpill-linux-v${KVERS}.ko"
[[ -d "$(dirname "$DEST")" ]] || { echo 'ERROR: expected rp-lkm directory missing.' >&2; exit 1; }
cp -v redpill.ko "$DEST"

printf '\nBuilding loader image...\n'
cd "$BUILD_DIR/redpill-load"
[[ -s "$ROOT/user_config.DS918+.json" ]] || { echo 'ERROR: user_config.DS918+.json not found.' >&2; exit 1; }
jq -e . "$ROOT/user_config.DS918+.json" >/dev/null
cp "$ROOT/user_config.DS918+.json" user_config.json
sudo ./build-loader.sh 'DS918+' '6.2.4-25556'

shopt -s nullglob
images=(images/redpill-DS918+_6.2.4-25556*.img)
(( ${#images[@]} > 0 )) || { echo 'ERROR: loader IMG not generated.' >&2; exit 1; }
for img in "${images[@]}"; do cp -v "$img" "$OUTPUT_DIR/"; done
printf '\n=== Generated images ===\n'
ls -lh "$OUTPUT_DIR"/*.img
