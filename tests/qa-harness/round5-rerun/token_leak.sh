#!/bin/bash
# 独立断言：Token 不得出现在 日志 / 运行文件 / ps argv / config.json 以外的数据目录文件
# 用法: token_leak.sh <cmd源码目录> <标签>
set -u
WS=/path/to
PKG="$WS/projects/fnos-openp2p/dist/openp2p_3.25.11-7_all.fpk"
CMDSRC="$1"; TAG="$2"
TOK=314159265358
R=/tmp/qa5/sbx/tok-$TAG
chmod -R u+rwX "$R" 2>/dev/null; rm -rf "$R"
D="$R/shares/openp2p"
mkdir -p "$D" "$R/var" "$R/target/bin"
cp -r "$CMDSRC/." "$R/cmd/"; chmod +x "$R"/cmd/* 2>/dev/null
tar xzf "$PKG" -O app.tgz | tar xz -C "$R/target" --wildcards 'bin/openp2p_x86_64' 2>/dev/null
mv "$R/target/bin/openp2p_x86_64" "$D/openp2p"; chmod +x "$D/openp2p"
# ⚠️ 必须先固定 TRIM_APPNAME=openp2p 并 unset 其余 TRIM_*，否则 cmd/common 会算出
#    /var/apps/appuser 的路径（本机自带 TRIM_APPNAME=appuser）。我第一次就踩了。
export TRIM_APPNAME=openp2p OPENP2P_APPROOT="$R" TRIM_APPDEST="$R/target" TRIM_PKGVAR="$R/var"
export LOG_FILE="$R/apps.log" TRIM_TEMP_LOGFILE="$R/install.err"
# 用**产品代码**写入 settings.conf（而不是手写夹具），顺便验证它的权限
( . "$R/cmd/common"; openp2p_token="$TOK" openp2p_node=nas-01 openp2p_sharebandwidth=10 \
    openp2p_serverhost=api.openp2p.cn openp2p_serverport=27183 openp2p_loglevel=1 \
    apply_settings_env; rc=$?; echo "  [$TAG] 被测 SETTINGS=$SETTINGS"; \
    echo "  [$TAG] apply_settings_env rc=$rc 权限=$(stat -c %a "$SETTINGS" 2>/dev/null)" )
: > "$R/apps.log"; : > "$R/install.err"
bash "$R/cmd/main" start >/dev/null 2>&1
sleep 3
PID=$(head -n1 "$R/var/app.pid" 2>/dev/null | tr -d '[:space:]')
echo "  [$TAG] start 后 pid=$PID  (存活=$([ -n "$PID" ] && [ -d /proc/$PID ] && echo yes || echo no))"
echo "  [$TAG] ps 里的启动命令行："
ps -ww -o pid=,args= -p "${PID:-1}" 2>/dev/null | sed "s/^/      /"
echo "  [$TAG] /proc/$PID/cmdline: $(tr '\0' ' ' < /proc/$PID/cmdline 2>/dev/null)"
echo
echo "  [$TAG] 在以下位置搜索 Token 明文 '$TOK'："
print_hits(){ # $1=标签 $2...=路径
  local label="$1"; shift
  local out
  out=$(grep -rl "$TOK" "$@" 2>/dev/null)
  if [ -n "$out" ]; then echo "      [命中] $label: $(printf '%s' "$out" | tr '\n' ' ')"; else echo "      [干净] $label"; fi
}
print_hits "日志 \$LOG_FILE + \$DATA_DIR/log/" "$R/apps.log" "$D/log" 2>/dev/null
print_hits "fnOS 安装进度文件 TRIM_TEMP_LOGFILE" "$R/install.err"
print_hits "运行文件（pid/start_time/锁/owner）" "$R/var"
# 数据目录里除 config.json 以外的所有文件
OTHER=$(find "$D" -type f ! -name 'config.json' 2>/dev/null | tr '\n' ' ')
# 数据目录里除 config.json / settings.conf 以外的所有文件（这两个是 Token 的合法落点，但必须 600）
OTHER=$(find "$D" -type f ! -name 'config.json' ! -name 'settings.conf' 2>/dev/null | tr '\n' ' ')
if [ -n "$OTHER" ]; then print_hits "数据目录（排除 config.json / settings.conf）" $OTHER; else echo "      [无文件] 数据目录内除 config.json/settings.conf 外无其它文件"; fi
echo "      [对照] config.json 含 Token 次数（应≥1）：$(grep -c "$TOK" "$D/config.json" 2>/dev/null)；权限=$(stat -c %a "$D/config.json" 2>/dev/null)"
echo "      [对照] settings.conf 含 Token 次数（应=1）：$(grep -c "$TOK" "$D/settings.conf" 2>/dev/null)；权限=$(stat -c %a "$D/settings.conf" 2>/dev/null)"
echo "  [$TAG] 全机进程表快照搜索 Token（先落盘再 grep，避免 grep 自己 argv 里的 Token 造成自命中）："
ps -eo pid=,args= > "$R/ps.txt" 2>/dev/null
echo "      命中行数 = $(grep -c "$TOK" "$R/ps.txt" 2>/dev/null)  （pid/args 明细：$(grep "$TOK" "$R/ps.txt" 2>/dev/null | tr '\n' '|'))"
bash "$R/cmd/main" stop >/dev/null 2>&1
# 收尾：确保不留进程
pkill -f "^$D/openp2p" 2>/dev/null
