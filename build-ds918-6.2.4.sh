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
