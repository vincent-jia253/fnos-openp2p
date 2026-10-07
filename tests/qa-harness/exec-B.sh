#!/bin/bash
# qa 复测执行器 · 块 B（TC-10 ~ TC-18）
set -u
PKG="/vol4/@appshare/octop-native/data/.octop/agents/ZD3XW7/projects/fnos-openp2p/dist/openp2p_3.25.11-8_all.fpk"
R="/tmp/qa-exec"; APPDEST="$R/target"; PKGVAR="$R/var"
DATA="$R/shares/openp2p"; BIN="$DATA/openp2p"; CONF="$DATA/config.json"; SETTINGS="$DATA/settings.conf"
PID="$PKGVAR/app.pid"; LOG="$R/apps.log"
export OPENP2P_APPROOT="$R" TRIM_APPNAME=openp2p TRIM_APPDEST="$APPDEST" TRIM_PKGVAR="$PKGVAR" LOG_FILE="$LOG"
export TRIM_TEMP_LOGFILE="$R/install.err"

prep() {
    # 卫生：rm -rf 会连 PID 文件一起删，若有上例残留进程就会变成孤儿并污染断言 → 先报告并清理
    if ps -eo pid,cmd | grep -F "$BIN" | grep -v grep | grep -q .; then
        echo "  [harness] 清理上例残留进程"; pkill -x openp2p 2>/dev/null; sleep 1; fi
    rm -rf "$R"; mkdir -p "$R" "$PKGVAR" "$APPDEST"
    tar xzf "$PKG" -C "$R"; tar xzf "$R/app.tgz" -C "$APPDEST"
    : > "$LOG"; : > "$TRIM_TEMP_LOGFILE"
    bash "$R/cmd/install_callback" >/dev/null 2>&1
}
procs() { ps -eo pid,cmd | grep -F "$BIN" | grep -v grep; }
nproc_o2p() { procs | wc -l | tr -d ' '; }
stopq() { bash "$R/cmd/main" stop >/dev/null 2>&1; }
P=0; F=0
res() { if [ "$2" = 1 ]; then echo "  [PASS] $1"; P=$((P+1)); else echo "  [FAIL] $1"; F=$((F+1)); fi; }

echo "=========== TC-10 无可用二进制 + 无匹配架构 → 不空转 (R5,R4) ==========="
prep; rm -f "$BIN"; rm -f "$APPDEST"/bin/openp2p_*; : > "$LOG"
bash "$R/cmd/install_callback"; echo "  install_callback rc=$? （预期 1）"
bash "$R/cmd/main" start; echo "  start rc=$?"
bash "$R/cmd/main" status; echo "  status rc=$?"
echo "  --- 日志 ---"; cat "$LOG"
[ "$(nproc_o2p)" = 0 ] && res "未启动任何进程" 1 || res "有进程被启动" 0
[ "$(bash "$R/cmd/main" status; echo $?)" = 3 ] && res "status rc=3" 1 || res "status 非 3" 0
grep -qi '缺少\|不支持' "$LOG" && res "日志有明确错误行" 1 || res "日志无明确错误" 0

echo "=========== TC-11 二进制损坏 → start rc=1 且不静默 (R5,R1) ==========="
prep; echo 'token=12345678' > "$SETTINGS"
head -c 1024 "$BIN" > /tmp/trunc.bin; cp /tmp/trunc.bin "$BIN"; chmod +x "$BIN"
M1=$(md5sum "$BIN" | awk '{print $1}'); : > "$LOG"
bash "$R/cmd/main" start; RC=$?; echo "  start rc=$RC （预期 1）"
echo "  --- 日志 ---"; tail -3 "$LOG"
M2=$(md5sum "$BIN" | awk '{print $1}')
[ "$RC" = 1 ] && res "start rc=1" 1 || res "start rc=$RC" 0
[ "$(nproc_o2p)" = 0 ] && res "无进程残留" 1 || res "有进程残留" 0
grep -q '无法运行' "$LOG" && res "有『无法运行（架构不匹配或文件损坏）』提示" 1 || res "提示不明确" 0
[ "$M1" = "$M2" ] && res "损坏文件未被半截新文件覆盖" 1 || res "文件被改写" 0

echo "=========== TC-12 包内候选损坏 → 不落盘替换，服务仍可用 (R5) ==========="
prep; echo 'token=12345678' > "$SETTINGS"; bash "$R/cmd/main" start >/dev/null 2>&1; sleep 2; stopq
MB=$(md5sum "$BIN" | awk '{print $1}')
NATIVE=$(uname -m); [ "$NATIVE" = x86_64 ] && NAT=openp2p_x86_64 || NAT=openp2p_aarch64
head -c 1024 /dev/urandom > "$APPDEST/bin/$NAT" 2>/dev/null || truncate -s 1024 "$APPDEST/bin/$NAT"
: > "$LOG"
bash "$R/cmd/install_callback"; echo "  install_callback rc=$?"
MA=$(md5sum "$BIN" | awk '{print $1}')
echo "  二进制 md5 前=$MB 后=$MA"
echo "  --- 日志 ---"; cat "$LOG"
[ "$MB" = "$MA" ] && res "未落盘替换（保留原可用二进制）" 1 || res "原二进制被覆盖" 0
bash "$R/cmd/main" start >/dev/null 2>&1; sleep 2
[ "$(nproc_o2p)" = 1 ] && res "服务仍可启动" 1 || res "服务起不来" 0
stopq

echo "=========== TC-13 Token 不进命令行 (I5) ==========="
prep; echo 'token=135790246' > "$SETTINGS"; bash "$R/cmd/main" start >/dev/null 2>&1; sleep 2
PV=$(cat "$PID" 2>/dev/null)
CL=$(tr '\0' ' ' < "/proc/$PV/cmdline" 2>/dev/null); echo "  /proc/$PV/cmdline: $CL"
PSLINE=$(ps -ww -o args= -p "$PV" 2>/dev/null); echo "  ps: $PSLINE"
PG=$(pgrep -af openp2p 2>/dev/null | grep -F "$BIN")
printf '%s' "$CL" | grep -q '135790246' && res "cmdline 不含 Token" 0 || res "cmdline 不含 Token" 1
printf '%s' "$PSLINE" | grep -q '135790246' && res "ps 不含 Token" 0 || res "ps 不含 Token" 1
printf '%s' "$PG" | grep -q '135790246' && res "pgrep -af 不含 Token" 0 || res "pgrep -af 不含 Token" 1
printf '%s' "$CL" | grep -q -- '-token' && res "cmdline 不含 -token 参数" 0 || res "cmdline 不含 -token 参数" 1
grep -q '"Token": 135790246' "$CONF" && res "Token 已写入 config.json" 1 || res "Token 未写入 config.json" 0
printf '%s' "$CL" | grep -q -- '-node' && res "其他 flags 仍正常传入" 1 || res "flags 缺失" 0
stopq

echo "=========== TC-14 权限 600 + 日志无 Token 明文 (I5,I2) ==========="
prep; echo 'token=135790246' > "$SETTINGS"; bash "$R/cmd/main" start >/dev/null 2>&1; sleep 2
echo "  config.json: $(stat -c '%a' "$CONF")  settings.conf: $(stat -c '%a' "$SETTINGS")"
echo "  --- 在日志中搜 Token ---"
HIT=$(grep -rl '135790246' "$LOG" "$DATA/log" 2>/dev/null); echo "  命中: [${HIT}]"
[ "$(stat -c '%a' "$CONF")" = 600 ] && res "config.json 权限 600" 1 || res "config.json 权限非 600" 0
[ "$(stat -c '%a' "$SETTINGS")" = 600 ] && res "settings.conf 权限 600" 1 || res "settings.conf 权限非 600" 0
[ -z "$HIT" ] && res "日志中 0 处 Token 明文" 1 || res "日志泄露 Token" 0
stopq

echo "=========== TC-15 未配 Token → 仍启动、不登录 (R4,CLI,B8) ==========="
prep; rm -f "$SETTINGS" "$CONF"; : > "$LOG"; : > "$TRIM_TEMP_LOGFILE"
bash "$R/cmd/main" start; echo "  start rc=$? （预期 0）"
bash "$R/cmd/main" status; echo "  status rc=$? （预期 0=运行中）"
echo "  --- 日志尾部 ---"; tail -2 "$LOG"
[ "$(nproc_o2p)" != 0 ] && res "进程已启动（B8：不再因缺 Token 而卡住界面）" 1 || res "进程未启动" 0
[ "$(bash "$R/cmd/main" status; echo $?)" = 0 ] && res "status rc=0（运行中）" 1 || res "status 非 0" 0
grep -q '未配置 Token' "$LOG" && res "有用户可见提示『未配置 Token』" 1 || res "无提示" 0
grep -q '不会登录组网' "$LOG" && res "提示说明了后果（不会登录组网）" 1 || res "提示未说明后果" 0
stopq

echo "=========== TC-16 清空 Token 但 config.json 有旧值 → 启动但旧 Token 必须清零 (I4,B8) ==========="
prep; printf 'token=\nnode=x\n' > "$SETTINGS"
printf '{"network":{"Token":135790246}}\n' > "$CONF"; : > "$LOG"
bash "$R/cmd/main" start; echo "  start rc=$?"
bash "$R/cmd/main" status; echo "  status rc=$? （预期 0=运行中）"
echo "  清空后 config.json 的 Token: $(grep -o '"Token"[^,}]*' "$CONF")"
[ "$(bash "$R/cmd/main" status; echo $?)" = 0 ] && res "status rc=0（应用可用，界面可进入填 Token）" 1 || res "status 非 0" 0
grep -qE '"Token":[[:space:]]*0([^0-9]|$)' "$CONF" && res "旧 Token 被清零为 0（settings.conf 为唯一权威，未复活旧值）" 1 || res "旧 Token 未清零：$(grep -o '"Token"[^,}]*' "$CONF")" 0
grep -q '135790246' "$CONF" && res "旧 Token 明文仍在 config.json" 0 || res "旧 Token 已从 config.json 清除" 1
stopq

echo "=========== TC-17 并发重复启动 → 幂等 (R7) ==========="
prep; echo 'token=12345678' > "$SETTINGS"
bash "$R/cmd/main" start >/dev/null 2>&1 & bash "$R/cmd/main" start >/dev/null 2>&1 & bash "$R/cmd/main" start >/dev/null 2>&1 & wait
sleep 4
N=$(nproc_o2p); echo "  进程数=$N （预期 1）"
echo "  app.pid=$(cat "$PID" 2>/dev/null)"
[ "$N" = 1 ] && res "三次 start 只产生 1 个进程（幂等）" 1 || res "进程数=$N（重复启动）" 0
[ -f "$PID" ] && res "app.pid 存在" 1 || res "app.pid 缺失" 0
stopq

echo "=========== TC-18 stop 干净 + 重复 stop (R6) ==========="
prep; echo 'token=12345678' > "$SETTINGS"; bash "$R/cmd/main" start >/dev/null 2>&1; sleep 2
bash "$R/cmd/main" stop; echo "  stop rc=$?"
echo "  残留进程: [$(procs)]"
bash "$R/cmd/main" status; echo "  status rc=$? （预期 3）"
bash "$R/cmd/main" stop; echo "  再次 stop rc=$? （预期 0）"
[ "$(nproc_o2p)" = 0 ] && res "无残留进程" 1 || res "有残留进程" 0
[ "$(bash "$R/cmd/main" status; echo $?)" = 3 ] && res "stop 后 status rc=3" 1 || res "status 非 3" 0
[ "$(bash "$R/cmd/main" stop >/dev/null 2>&1; echo $?)" = 0 ] && res "重复 stop rc=0" 1 || res "重复 stop 非 0" 0

echo
echo "=========== 块 B 汇总：PASS=$P  FAIL=$F ==========="
