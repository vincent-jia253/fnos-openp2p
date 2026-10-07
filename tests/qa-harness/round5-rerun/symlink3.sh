#!/bin/bash
# 补充：符号链接数据目录下 fix_binary_arch / install_callback 是否正常
set -u
WS=/path/to
PKG="$WS/projects/fnos-openp2p/dist/openp2p_3.25.11-7_all.fpk"
APP=/tmp/qa5/sbx/sym2/app                # 在 / 上（模拟 /var/apps/openp2p）
REAL=/path/to/qa5-sym3-real   # 在 /vol4 上
chmod -R u+rwX "$APP" "$REAL" 2>/dev/null; rm -rf "$APP" "$REAL"
mkdir -p "$APP/shares" "$APP/var" "$APP/target/bin" "$REAL"
ln -sfn "$REAL" "$APP/shares/openp2p"
cp -r "$WS/projects/fnos-openp2p/src/openp2p/cmd" "$APP/cmd"; chmod +x "$APP"/cmd/*
tar xzf "$PKG" -O app.tgz | tar xz -C "$APP/target" --wildcards 'bin/openp2p_x86_64' 2>/dev/null
export TRIM_APPNAME=openp2p OPENP2P_APPROOT="$APP" TRIM_APPDEST="$APP/target" TRIM_PKGVAR="$APP/var"
export LOG_FILE="$APP/apps.log" TRIM_TEMP_LOGFILE="$APP/install.err"
: > "$APP/apps.log"; : > "$APP/install.err"
echo "布局: $APP/shares/openp2p -> $(readlink -f "$APP/shares/openp2p")"
openp2p_token=314159265358 openp2p_node=nas-01 bash "$APP/cmd/install_callback" >"$APP/out" 2>"$APP/err"; rc=$?
echo "install_callback rc=$rc  stderr=$(wc -c <"$APP/err") 字节"
echo "真实目录内容："; ls -la "$REAL"
echo "经符号链接看到：" ; ls -la "$APP/shares/openp2p"
echo "settings.conf 权限: $(stat -c%a "$APP/shares/openp2p/settings.conf" 2>/dev/null)"
echo "二进制可执行: $([ -x "$APP/shares/openp2p/openp2p" ] && echo yes || echo no)"
echo "安装进度文件内容: $(cat "$APP/install.err")"
chmod -R u+rwX "$REAL" 2>/dev/null; rm -rf "$REAL"
