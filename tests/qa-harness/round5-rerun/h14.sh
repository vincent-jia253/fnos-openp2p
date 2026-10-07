#!/bin/bash
# 独立 H14 复现器（自写）：raw_save（必须先停后写）写失败时必须恢复运行并如实交代
# 用法：h14.sh <index.cgi 路径> <标签>
set -u
CGI_SRC="$1"; TAG="$2"
WS=/path/to
PKG="$WS/projects/fnos-openp2p/dist/openp2p_3.25.11-7_all.fpk"
SRC="$WS/projects/fnos-openp2p/src/openp2p"
R=/tmp/qa5/sbx/h14-$TAG
chmod -R u+rwX "$R" 2>/dev/null; rm -rf "$R"
mkdir -p "$R/ui" "$R/var" "$R/target/bin" "$R/shares/openp2p"
export TRIM_APPNAME=openp2p OPENP2P_APPROOT="$R" TRIM_APPDEST="$R/target" TRIM_PKGVAR="$R/var"
export LOG_FILE="$R/apps.log" TRIM_TEMP_LOGFILE="$R/install.err"
cp -r "$SRC/cmd" "$R/cmd"; chmod +x "$R"/cmd/*
sed "s|/var/apps/openp2p|$R|g" "$CGI_SRC" > "$R/ui/index.cgi"; chmod +x "$R/ui/index.cgi"
tar xzf "$PKG" -O app.tgz | tar xz -C "$R/target" --wildcards 'bin/openp2p_x86_64' 2>/dev/null
mv "$R/target/bin/openp2p_x86_64" "$R/shares/openp2p/openp2p"; chmod +x "$R/shares/openp2p/openp2p"
: > "$R/apps.log"
D="$R/shares/openp2p"
printf 'token=123456789\nnode=my-nas\nsharebandwidth=10\nserverhost=api.openp2p.cn\nserverport=27183\nloglevel=1\n' > "$D/settings.conf"
printf '{"network":{"Token":123456789}}\n' > "$D/config.json"
bash "$R/cmd/main" start >/dev/null 2>&1; sleep 2
if ! pgrep -f "^$D/openp2p" >/dev/null; then echo "  TAG=$TAG [前置失败] 应用没起来，本用例无效"; exit 2; fi
echo "  TAG=$TAG 保存前: 运行中 pid=$(pgrep -f "^$D/openp2p" | head -1)"
INJECT="${3:-dirswap}"
if [ "$INJECT" = "ro" ]; then
    chmod 500 "$D"          # 更贴近真实：磁盘满 / 只读挂载（已存在的 config.json 也改不动）
else
    rm -f "$D/config.json"; mkdir -p "$D/config.json/blocker"
fi
B='action=raw_save&rawjson=%7B%22network%22%3A%7B%22Token%22%3A999%7D%7D'
printf '%s' "$B" | CONTENT_LENGTH=${#B} REQUEST_METHOD=POST bash "$R/ui/index.cgi" >"$R/out" 2>"$R/err"
echo "  TAG=$TAG stderr=$(wc -c <"$R/err") 字节"
echo "  TAG=$TAG 界面文案: $(grep -oE '[✅❌⚠️🛑][^<]*' "$R/out" | head -2 | tr '\n' '|')"
if pgrep -f "^$D/openp2p" >/dev/null; then echo "  TAG=$TAG 保存后: 应用在运行"; else echo "  TAG=$TAG 保存后: 应用已停（未恢复）"; fi
if grep -qE '应用已恢复运行|未能重新启动|未能停止' "$R/out"; then echo "  TAG=$TAG 文案交代了应用状态: 是"; else echo "  TAG=$TAG 文案交代了应用状态: 否（只字不提）"; fi
pkill -f "^$D/openp2p" 2>/dev/null
chmod -R u+rwX "$R" 2>/dev/null; rm -rf "$R"
