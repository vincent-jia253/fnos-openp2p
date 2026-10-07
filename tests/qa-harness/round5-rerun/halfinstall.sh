#!/bin/bash
# 语义验证：install_callback 在"二进制已部署、设置写失败"时的半装状态与用户可见文案
set -u
WS=/path/to
PKG="$WS/projects/fnos-openp2p/dist/openp2p_3.25.11-7_all.fpk"
R=/tmp/qa5/sbx/half
chmod -R u+rwX "$R" 2>/dev/null; rm -rf "$R"; mkdir -p "$R/shares/openp2p" "$R/var" "$R/target/bin"
cp -r "$WS/projects/fnos-openp2p/src/openp2p/cmd" "$R/cmd"; chmod +x "$R"/cmd/*
tar xzf "$PKG" -O app.tgz | tar xz -C "$R/target" --wildcards 'bin/openp2p_x86_64' 2>/dev/null
export TRIM_APPNAME=openp2p OPENP2P_APPROOT="$R" TRIM_APPDEST="$R/target" TRIM_PKGVAR="$R/var"
export LOG_FILE="$R/apps.log" TRIM_TEMP_LOGFILE="$R/install.err"
: > "$R/apps.log"; : > "$R/install.err"
echo "== 场景：数据目录可写，但 settings.conf 已是个非空目录（写设置必然失败）=="
mkdir -p "$R/shares/openp2p/settings.conf/blocker"
echo "-- 安装前：DATA_DIR 内容 --"; ls -la "$R/shares/openp2p"
openp2p_token=314159265358 openp2p_node=nas-01 bash "$R/cmd/install_callback" >"$R/out" 2>"$R/err"; rc=$?
echo "-- install_callback rc=$rc --"
echo "-- TRIM_TEMP_LOGFILE（fnOS 安装进度界面看的那个文件）--"; cat "$R/install.err"
echo "-- stdout/stderr --"; wc -c <"$R/out"; wc -c <"$R/err"
echo "-- 安装后：DATA_DIR 内容（注意二进制是否已落地 = 半装状态）--"; ls -la "$R/shares/openp2p"
echo "-- 应用日志 --"; cat "$R/apps.log"
echo "-- 此时 main status --"; bash "$R/cmd/main" status; echo "status rc=$?"
