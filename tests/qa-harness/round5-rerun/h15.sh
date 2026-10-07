#!/bin/bash
# 独立 H15：数据目录不可写时，安装/升级回调的 fix_binary_arch 必须零字节泄漏
# 用法: h15.sh <cmd目录> <标签>
set -u
WS=/path/to
PKG="$WS/projects/fnos-openp2p/dist/openp2p_3.25.11-7_all.fpk"
CMDSRC="$1"; TAG="$2"
R=/tmp/qa5/sbx/h15-$TAG
chmod -R u+rwX "$R" 2>/dev/null; rm -rf "$R"; mkdir -p "$R/shares/openp2p" "$R/var" "$R/target/bin" "$R/tmpdir"
cp -r "$CMDSRC/." "$R/cmd/"; chmod +x "$R"/cmd/* 2>/dev/null
# 前置①：包内负载二进制在位
tar xzf "$PKG" -O app.tgz | tar xz -C "$R/target" --wildcards 'bin/openp2p_x86_64' 2>/dev/null
if [ -f "$R/target/bin/openp2p_x86_64" ]; then echo "  [$TAG] 前置① 包内负载二进制在位: yes"; else echo "  [$TAG] 前置① 失败: 包内无二进制，用例无效"; exit 2; fi
# 前置②：数据目录里没有现成二进制（否则 fix_binary_arch 走"沿用"分支，根本不 cp）
rm -f "$R/shares/openp2p/openp2p"
if [ ! -e "$R/shares/openp2p/openp2p" ]; then echo "  [$TAG] 前置② 数据目录无现成二进制: yes（会真的走拷贝分支）"; else echo "  [$TAG] 前置② 失败"; exit 2; fi
export TRIM_APPNAME=openp2p OPENP2P_APPROOT="$R" TRIM_APPDEST="$R/target" TRIM_PKGVAR="$R/var"
export LOG_FILE="$R/apps.log" TRIM_TEMP_LOGFILE="$R/install.err"
: > "$R/apps.log"; : > "$R/install.err"
chmod 500 "$R/shares/openp2p"          # 数据目录不可写
bash "$R/cmd/upgrade_callback" >"$R/out" 2>"$R/err"; rc=$?
chmod 700 "$R/shares/openp2p"
echo "  [$TAG] upgrade_callback rc=$rc"
echo "  [$TAG] stdout=$(wc -c <"$R/out") 字节  stderr=$(wc -c <"$R/err") 字节  install.err=$(wc -c <"$R/install.err") 字节"
[ -s "$R/err" ] && echo "  [$TAG] [泄漏] stderr 首行: $(head -1 "$R/err")" || echo "  [$TAG] [干净] 回调 stderr 零字节"
echo "  [$TAG] 分支证据（日志）: $(grep -c '复制二进制到数据目录失败' "$R/apps.log" 2>/dev/null) 行 '复制二进制到数据目录失败'"
grep '复制二进制到数据目录失败' "$R/apps.log" 2>/dev/null | sed 's/^/      /'
echo "  [$TAG] 失败后数据目录仍无二进制: $([ -e "$R/shares/openp2p/openp2p" ] && echo NO || echo yes)  残留 openp2p.new.*: $(ls "$R/shares/openp2p"/openp2p.new.* 2>/dev/null | wc -l) 个"
