#!/usr/bin/env bash
# DS918+ DSM 6.2.4-25556 RedPill build with PAT compatibility preflight.
# Does not bypass checksum validation or modify RedPill's expected hashes.
set -Eeuo pipefail
trap 'echo "ERROR at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

ROOT="$(pwd)"
BUILD="$ROOT/ds918-6.2.4"
OUTPUT="$ROOT/output"
mkdir -p "$BUILD" "$OUTPUT"

echo '=== Install build tools ==='
sudo apt-get update
sudo apt-get install -y --no-install-recommends ca-certificates build-essential git libssl-dev curl cpio bsdiff vim gettext bc bison flex dosfstools kmod jq file xz-utils python3

cd "$BUILD"
[ -d redpill-lkm ] || git clone --depth=1 https://github.com/RedPill-TTG/redpill-lkm.git
[ -d redpill-load ] || git clone --depth=1 https://github.com/RedPill-TTG/redpill-load.git

CONFIG="$BUILD/redpill-load/config/DS918+/6.2.4-25556/config.json"
USER_CONFIG="$ROOT/user_config.DS918+.json"
[ -s "$CONFIG" ] || { echo "Missing $CONFIG" >&2; exit 1; }
[ -s "$USER_CONFIG" ] || { echo "Missing $USER_CONFIG" >&2; exit 1; }

# PAT preflight: verify the archive itself and the unmodified kernel/ramdisk.
# PAT is downloaded from the exact URL defined by the checked-out RedPill config.
PAT_URL="$(jq -er '.os.pat_url' "$CONFIG")"
PAT_SHA="$(jq -er '.os.sha256' "$CONFIG")"
PAT="$BUILD/ds918p_25556.pat"
echo '=== Download DSM PAT ==='
echo "URL: $PAT_URL"
curl -fL --retry 3 --connect-timeout 30 --max-time 1800 "$PAT_URL" -o "$PAT"
file "$PAT"
ls -lh "$PAT"
ACTUAL_PAT_SHA="$(sha256sum "$PAT" | awk '{print $1}')"
echo "PAT expected: $PAT_SHA"
echo "PAT actual:   $ACTUAL_PAT_SHA"

# DSM PATs can be tar archives; inspect only if tar can list the contents.
if tar -tf "$PAT" >/dev/null 2>&1; then
  for key in zlinux ramdisk; do
    name="$(jq -er --arg k "$key" '.files[$k].name' "$CONFIG")"
    expected="$(jq -er --arg k "$key" '.files[$k].sha256' "$CONFIG")"
    member="$(tar -tf "$PAT" | awk -v n="$name" '$0==n || $0=="./"n {print; exit}')"
    if [ -z "$member" ]; then
      echo "Cannot find $name in PAT; stopping safely." >&2
      exit 1
    fi
    actual="$(tar -xOf "$PAT" "$member" | sha256sum | awk '{print $1}')"
    echo "$name expected: $expected"
    echo "$name actual:   $actual"
    if [ "$actual" != "$expected" ]; then
      echo "ERROR: $name checksum mismatch; legacy patches may be incompatible." >&2
      exit 1
    fi
  done
else
  echo 'PAT is not a directly readable tar archive; cannot verify inner files safely.' >&2
  exit 1
fi

if [ "$ACTUAL_PAT_SHA" != "$PAT_SHA" ]; then
  echo 'PAT outer checksum differs, even though inspected inner files matched.' >&2
  echo 'Stopping: do not bypass RedPill integrity validation without independent verification.' >&2
  exit 1
fi

echo '=== Download Synology ApolloLake GPL kernel source ==='
KERNEL_URL='https://global.synologydownload.com/download/ToolChain/Synology%20NAS%20GPL%20Source/6.2-25556/apollolake/linux-4.4.x.txz'
KERNEL="$BUILD/linux-4.4.x.txz"
curl -fL --retry 3 --connect-timeout 30 --max-time 1800 "$KERNEL_URL" -o "$KERNEL"
file "$KERNEL"
xz -t "$KERNEL"

cd "$BUILD/redpill-lkm"
tar -xf "$KERNEL"
LINUX_SRC="$(find "$PWD" -maxdepth 1 -type d -name 'linux-4.4*' -print -quit)"
[ -n "$LINUX_SRC" ] || { echo 'Missing extracted Linux 4.4 source' >&2; exit 1; }
cd "$LINUX_SRC"
[ -f synoconfigs/apollolake ] || { echo 'Missing synoconfigs/apollolake' >&2; exit 1; }
cp synoconfigs/apollolake .config
printf '+\n' > .scmversion
make oldconfig
make modules_prepare
cd "$BUILD/redpill-lkm"
make LINUX_SRC="$LINUX_SRC" test-v6
[ -s redpill.ko ] || { echo 'redpill.ko missing' >&2; exit 1; }
KVERS="$(modinfo -F vermagic redpill.ko | awk '{print $1}')"
[ -n "$KVERS" ] || { echo 'Could not determine kernel vermagic' >&2; exit 1; }
cp -v redpill.ko "$BUILD/redpill-load/ext/rp-lkm/redpill-linux-v${KVERS}.ko"

cd "$BUILD/redpill-load"
cp "$USER_CONFIG" user_config.json
# Prevalidated PAT; copy into the location expected by redpill-load.
mkdir -p cache
cp "$PAT" cache/ds918p_25556.pat
sudo ./build-loader.sh 'DS918+' '6.2.4-25556'

shopt -s nullglob
images=(images/redpill-DS918+_6.2.4-25556*.img)
((${#images[@]} > 0)) || { echo 'No output IMG produced' >&2; exit 1; }
cp -v "${images[@]}" "$OUTPUT/"
echo '=== Finished ==='
ls -lh "$OUTPUT"/*.img
