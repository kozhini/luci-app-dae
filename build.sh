#!/bin/sh
# Build luci-app-dae IPK without OpenWrt buildroot
set -e

VERSION="0.3.32"
PKG="luci-app-dae_${VERSION}-1_all"
DIR="$(cd "$(dirname "$0")"; pwd)"
BUILD="/tmp/_luci-app-dae-build"
DIST="$DIR/dist"

rm -rf "$BUILD"
mkdir -p "$BUILD/data" "$BUILD/control" "$BUILD/stage" "$DIST"

cp -r "$DIR/root/." "$BUILD/data/"
cp -r "$DIR/www/."  "$BUILD/data/www/"
chmod +x "$BUILD/data/usr/libexec/rpcd/luci.dae" \
         "$BUILD/data/etc/uci-defaults/90_dae" \
         "$BUILD/data/usr/share/dae/installer.sh"

cat > "$BUILD/control/control" << EOF
Package: luci-app-dae
Version: ${VERSION}-1
Depends: libc, luci-base, dae, curl, ca-bundle
License: AGPL-3.0
Section: luci
Architecture: all
Description: LuCI app for dae
EOF

cat > "$BUILD/control/postinst" << 'EOF'
#!/bin/sh
[ "${IPKG_NO_SCRIPT}" = "1" ] && exit 0
[ -x /etc/uci-defaults/90_dae ] && /etc/uci-defaults/90_dae && rm -f /etc/uci-defaults/90_dae
/etc/init.d/rpcd reload 2>/dev/null
exit 0
EOF
chmod +x "$BUILD/control/postinst"
printf '#!/bin/sh\nexit 0\n' > "$BUILD/control/prerm"
chmod +x "$BUILD/control/prerm"

# conffiles: opkg will not overwrite these if already modified by user
cat > "$BUILD/control/conffiles" << 'EOF'
/etc/dae/config.dae
EOF

echo "2.0" > "$BUILD/stage/debian-binary"
cd "$BUILD/data";    tar czf "$BUILD/stage/data.tar.gz" .
cd "$BUILD/control"; tar czf "$BUILD/stage/control.tar.gz" .

python3 - << PYEOF
import tarfile, io, os, time
stage, out = "$BUILD/stage", "$DIST/${PKG}.ipk"
def add(tf, name, path):
    data = open(path,'rb').read()
    info = tarfile.TarInfo(name=name)
    info.size=len(data); info.mtime=int(time.time()); info.mode=0o644
    tf.addfile(info, io.BytesIO(data))
with tarfile.open(out, "w:gz") as tf:
    add(tf,"./debian-binary",  f"{stage}/debian-binary")
    add(tf,"./control.tar.gz", f"{stage}/control.tar.gz")
    add(tf,"./data.tar.gz",    f"{stage}/data.tar.gz")
print(f"Built: {out}  ({os.path.getsize(out)} bytes)")
PYEOF
