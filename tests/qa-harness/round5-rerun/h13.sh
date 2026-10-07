#!/bin/bash
# 独立 H13/H14 复现器（自写，不复用 exec-H.sh 的函数）
# 用法：h13.sh <index.cgi 路径> <标签>
# 场景：应用正在运行 → 保存设置时写入必然失败（settings.conf 被换成非空目录）
# 断言：1) 界面如实报错 2) 应用是否仍在运行 3) 文案是否交代应用状态
set -u
CGI_SRC="$1"; TAG="$2"
WS=/vol4/@appshare/octop-native/data/.octop/agents/ZD3XW7
PKG="$WS/projects/fnos-openp2p/dist/openp2p_3.25.11-7_all.fpk"
SRC="$WS/projects/fnos-openp2p/src/openp2p"
R=/tmp/qa5/sbx/h13-$TAG
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
bash "$R/cmd/main" start >/dev/null 2>&1; sleep 2
if ! pgrep -f "^$D/openp2p" >/dev/null; then echo "  TAG=$TAG [前置失败] 应用没起来，本用例无效"; exit 2; fi
PID_BEFORE=$(pgrep -f "^$D/openp2p" | head -1)
echo "  TAG=$TAG 保存前: 运行中 pid=$PID_BEFORE"

rm -f "$D/settings.conf"; mkdir -p "$D/settings.conf/blocker"     # 强制写入失败
B='action=save&token=111222333&node=still-up'
printf '%s' "$B" | CONTENT_LENGTH=${#B} REQUEST_METHOD=POST bash "$R/ui/index.cgi" >"$R/out" 2>"$R/err"
RC=$?
sleep 1
echo "  TAG=$TAG CGI rc=$RC  stderr=$(wc -c <"$R/err") 字节"
echo "  TAG=$TAG 界面文案: $(grep -oE '[✅❌⚠️🛑][^<]*' "$R/out" | head -3 | tr '\n' '|')"
if pgrep -f "^$D/openp2p" >/dev/null; then
  echo "  TAG=$TAG 保存后: 应用仍在运行 (pid=$(pgrep -f "^$D/openp2p" | head -1))  => [运行未被破坏]"
else
  echo "  TAG=$TAG 保存后: 应用已被静默停掉（没有进程）  => [被丢在停止态]"
fi
if grep -qE '应用未被改动|应用已恢复运行|未能重新启动|未能停止' "$R/out"; then
  echo "  TAG=$TAG 文案交代了应用状态: 是"
else
  echo "  TAG=$TAG 文案交代了应用状态: 否（只字不提）"
fi
pkill -f "^$D/openp2p" 2>/dev/null
chmod -R u+rwX "$R" 2>/dev/null; rm -rf "$R"
