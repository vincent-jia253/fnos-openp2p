#!/bin/bash
# qa 复测执行器 · 块 A（TC-01 ~ TC-09）—— 修正版
#
# 对 qa/testcases.md 的修正（均为用例缺陷，非实现缺陷）：
#  [C1] 用例用大写 OPENP2P_NODE 读向导字段 → 应为小写（OpenList 实证 + api.md §3）
#  [C2] 用例把 cmd/ 写在 $APPDEST/cmd/ → 实际在 $APPROOT/cmd/
#  [C3] 用例 #PREP 只解包、未跑 install_callback → 二进制未部署，start 必然失败
#  [C4] TC-08 试图用 mock uname 验证跨架构 → 本机为 x86_64，无法执行他架构二进制
#       （fix_binary_arch 的自检是"真去运行 -v"），改为验证：本机架构正确部署 + 错架构被拒绝
#  [C5] TC-09 mock uname=riscv64 实际命中的是"不支持架构"分支，非"包内无此架构"分支
#       → 改为删除本机架构的 payload 二进制来命中目标分支
set -u
PKG="/vol4/@appshare/octop-native/data/.octop/agents/ZD3XW7/projects/fnos-openp2p/dist/openp2p_3.25.11-8_all.fpk"
R="/tmp/qa-exec"; APPDEST="$R/target"; PKGVAR="$R/var"
DATA="$R/shares/openp2p"; BIN="$DATA/openp2p"; CONF="$DATA/config.json"; SETTINGS="$DATA/settings.conf"
PID="$PKGVAR/app.pid"; LOG="$R/apps.log"
export OPENP2P_APPROOT="$R" TRIM_APPNAME=openp2p TRIM_APPDEST="$APPDEST" TRIM_PKGVAR="$PKGVAR" LOG_FILE="$LOG"
export TRIM_TEMP_LOGFILE="$R/install.err"

# prep = 解包 + 完成安装（真实 fnOS 上 install_callback 在安装时已跑过）
prep() {
    # 用例卫生：prep 会 rm -rf $R（连 PID 文件一起删），若此时仍有上个用例留下的进程，
    # 它会变成 pid 文件已丢失的孤儿，后续用例的进程计数/status 就会被污染。
    # 这里主动报告并清理，避免「串扰被误读成产品缺陷」。
    local stray; stray=$(ps -eo pid,cmd | grep -F "$BIN" | grep -v grep)
    if [ -n "$stray" ]; then
        echo "  [harness] prep 前发现残留进程，已清理："
        printf '%s\n' "$stray" | sed 's/^/      /'
        pkill -x openp2p 2>/dev/null; sleep 1
    fi
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

echo "=========== TC-01 启动常驻 + /proc/pid/exe 指向 DATA_DIR (R1,I1) ==========="
prep; echo 'token=12345678' > "$SETTINGS"
bash "$R/cmd/main" start; echo "  start rc=$?"
bash "$R/cmd/main" status; echo "  status rc=$?"
sleep 5
PIDV=$(cat "$PID" 2>/dev/null); echo "  pid=$PIDV"
EXE=$(readlink -f "/proc/$PIDV/exe" 2>/dev/null); echo "  /proc/$PIDV/exe -> $EXE"
kill -0 "$PIDV" 2>/dev/null && res "5秒后进程仍存活（常驻）" 1 || res "5秒后进程仍存活" 0
[ "$EXE" = "$BIN" ] && res "exe 指向 \$DATA_DIR/openp2p（满足 I1）" 1 || res "exe=$EXE 期望 $BIN" 0
stopq

echo "=========== TC-02 未运行 status=3 + 未知参数 rc=1 (R1,CLI) ==========="
prep
bash "$R/cmd/main" status; RC=$?; echo "  status rc=$RC (期望 3)"
OUT=$(bash "$R/cmd/main" bogus-arg 2>&1); RC2=$?; echo "  bogus rc=$RC2 输出: $OUT"
[ "$RC" = 3 ] && res "未运行时 status rc=3" 1 || res "status rc=$RC 期望 3" 0
[ "$RC2" = 1 ] && res "未知参数 rc=1" 1 || res "未知参数 rc=$RC2" 0
printf '%s' "$OUT" | grep -qi 'usage' && res "打印 Usage" 1 || res "未打印 Usage" 0
[ "$(nproc_o2p)" = 0 ] && res "两命令均未产生进程" 1 || res "产生了进程" 0

echo "=========== TC-03 config.json/log 只在 DATA_DIR (I2) ==========="
prep; echo 'token=12345678' > "$SETTINGS"; bash "$R/cmd/main" start >/dev/null 2>&1; sleep 2
ls -l "$CONF" 2>/dev/null; ls -ld "$DATA/log" 2>/dev/null
STRAY=$(find "$APPDEST" -name config.json 2>/dev/null); echo "  APPDEST 下 config.json: [${STRAY}]"
[ -f "$CONF" ] && res "config.json 在 DATA_DIR" 1 || res "config.json 在 DATA_DIR" 0
[ -d "$DATA/log" ] && res "log/ 在 DATA_DIR" 1 || res "log/ 在 DATA_DIR" 0
[ -z "$STRAY" ] && res "APPDEST 下无 config.json（I2）" 1 || res "APPDEST 下有 config.json" 0
stopq

echo "=========== TC-04 config_callback 改设置 → 重启生效不丢 (R2) ==========="
prep; echo 'token=12345678' > "$SETTINGS"; bash "$R/cmd/main" start >/dev/null 2>&1
openp2p_node=mynas-01 openp2p_sharebandwidth=50 bash "$R/cmd/config_callback"; echo "  config_callback rc=$?"
stopq; bash "$R/cmd/main" start >/dev/null 2>&1; sleep 3
echo "  --- settings.conf ---"; grep -E '^(token|node|sharebandwidth)=' "$SETTINGS"
CMDLINE=$(tr '\0' ' ' < "/proc/$(cat "$PID" 2>/dev/null)/cmdline" 2>/dev/null); echo "  命令行: $CMDLINE"
grep -q '^node=mynas-01$' "$SETTINGS" && res "node 已更新为 mynas-01" 1 || res "node 未更新" 0
grep -q '^sharebandwidth=50$' "$SETTINGS" && res "sharebandwidth 已更新为 50" 1 || res "sharebandwidth 未更新" 0
printf '%s' "$CMDLINE" | grep -q -- '-node mynas-01' && res "重启后 flags 生效且不丢" 1 || res "重启后 flags 未生效" 0
stopq

echo "=========== TC-05 settings.conf 权限 600 + 重启不丢 (R2,I4) ==========="
prep; echo 'token=12345678' > "$SETTINGS"
bash "$R/cmd/config_callback" >/dev/null 2>&1
echo "  权限/属主: $(stat -c '%a %U' "$SETTINGS")"
bash "$R/cmd/main" start >/dev/null 2>&1; sleep 2; stopq
grep -E '^token=' "$SETTINGS"
[ "$(stat -c '%a' "$SETTINGS")" = "600" ] && res "settings.conf 权限 600" 1 || res "权限非 600" 0
grep -q '^token=12345678$' "$SETTINGS" && res "重启后 Token 未丢" 1 || res "Token 丢了" 0

echo "=========== TC-06 升级（覆盖 target）不丢配置 (R3,I3) ==========="
# 注意：用 install_callback 产出的【规范化】settings.conf，才是有意义的 I3 检验
# 注意：config_callback 现在会把未运行的应用拉起（B8 修复的配套行为），故用后立即 stopq，
#       本用例只关心"配置规范化 + 升级后不丢"，不关心进程。
prep; echo 'token=12345678' > "$SETTINGS"; bash "$R/cmd/config_callback" >/dev/null 2>&1; stopq
printf '{"network":{"Token":12345678},"apps":[{"Name":"web","Protocol":"tcp","SrcPort":18080,"DstHost":"127.0.0.1","DstPort":8080,"Enabled":1}]}\n' > "$CONF"
M1=$(md5sum "$SETTINGS" | awk '{print $1}'); M2=$(md5sum "$CONF" | awk '{print $1}')
echo "  升级前 settings=$M1 config=$M2"
rm -rf "$APPDEST"; mkdir -p "$APPDEST"
tar xzf "$PKG" -C "$R" --overwrite 2>/dev/null; tar xzf "$R/app.tgz" -C "$APPDEST"
bash "$R/cmd/upgrade_init"; echo "  upgrade_init rc=$?"
bash "$R/cmd/upgrade_callback"; echo "  upgrade_callback rc=$?"
N1=$(md5sum "$SETTINGS" | awk '{print $1}'); N2=$(md5sum "$CONF" | awk '{print $1}')
echo "  升级后 settings=$N1 config=$N2"
[ "$M1" = "$N1" ] && res "settings.conf 升级前后 md5 一致（值+格式均未变）" 1 || res "settings.conf 内容变了" 0
[ "$M2" = "$N2" ] && res "config.json 升级前后 md5 一致" 1 || res "config.json 变了" 0
grep -q '"web"' "$CONF" && res "apps[] 未丢失" 1 || res "apps[] 丢了" 0
grep -q '^token=12345678$' "$SETTINGS" && res "Token 未丢失" 1 || res "Token 丢了" 0

echo "=========== TC-07 修复重装：二进制回位且不覆盖 config (R3,R5) ==========="
# 注意：config_callback 现在会把未运行的应用拉起（B8 修复的配套行为），故用后立即 stopq，
#       本用例只关心"配置规范化 + 升级后不丢"，不关心进程。
prep; echo 'token=12345678' > "$SETTINGS"; bash "$R/cmd/config_callback" >/dev/null 2>&1; stopq
printf '{"network":{"Token":12345678},"apps":[{"Name":"keepme","Protocol":"tcp","SrcPort":19999,"DstHost":"127.0.0.1","DstPort":9,"Enabled":1}]}\n' > "$CONF"
M2=$(md5sum "$CONF" | awk '{print $1}')
rm -f "$BIN"; echo "  已删除 \$BIN"
# 真实的"修复"会重新展开安装包（payload 随之回来），这里如实模拟
rm -rf "$APPDEST"; mkdir -p "$APPDEST"; tar xzf "$R/app.tgz" -C "$APPDEST"
echo "  重新展开安装包（模拟 fnOS『修复』）"
bash "$R/cmd/install_callback"; echo "  install_callback rc=$?"
ls -l "$BIN" 2>/dev/null
N2=$(md5sum "$CONF" 2>/dev/null | awk '{print $1}')
[ -x "$BIN" ] && res "二进制重新落地 DATA_DIR" 1 || res "二进制未落地" 0
[ "$M2" = "$N2" ] && res "config.json 未被覆盖/重建" 1 || res "config.json 被改动了" 0
grep -q 'keepme' "$CONF" && res "apps[] 保留" 1 || res "apps[] 丢了" 0

echo "=========== TC-08 架构选择（本机可执行部分）(R5) ==========="
# [C4] 跨架构无法在本机执行：自检是真运行 -v。这里验证两件可验证的事。
prep
NATIVE=$(uname -m); echo "  本机架构: $NATIVE"
case "$NATIVE" in x86_64) WANT=openp2p_x86_64 ;; *) WANT="" ;; esac
if [ -n "$WANT" ]; then
    REF=$(mktemp -d); tar xzf "$R/app.tgz" -C "$REF"
    GM=$(md5sum "$BIN" | awk '{print $1}'); WM=$(md5sum "$REF/bin/$WANT" 2>/dev/null | awk '{print $1}'); rm -rf "$REF"
    [ "$GM" = "$WM" ] && res "本机架构部署了正确的 $WANT" 1 || res "部署的二进制不是 $WANT" 0
    V=$("$BIN" -v 2>/dev/null | head -1); echo "  $BIN -v → $V"
    printf '%s' "$V" | grep -q '3\.25\.11' && res "二进制可运行且版本正确" 1 || res "二进制版本异常" 0
fi
# 错架构必须被拒绝：把 aarch64 二进制伪装成本机架构的候选
prep
if [ -f "$APPDEST/bin/openp2p_aarch64" ]; then
    cp -f "$APPDEST/bin/openp2p_aarch64" "$APPDEST/bin/openp2p_x86_64"
    rm -f "$BIN"; : > "$LOG"
    bash "$R/cmd/install_callback"; RC=$?
    echo "  install_callback(错架构候选) rc=$RC"; tail -1 "$LOG"
    [ "$RC" != 0 ] && [ ! -x "$BIN" ] && res "错架构二进制被拒绝部署（自检拦截）" 1 || res "错架构二进制被放行了" 0
fi

echo "=========== TC-09 包内无本机架构二进制 + 已有可用二进制 → 沿用 (R5) ==========="
# [C5] 命中"包内缺该架构"分支的正确做法：删掉本机架构的 payload 二进制
prep
MB=$(md5sum "$BIN" | awk '{print $1}'); : > "$LOG"
rm -f "$APPDEST/bin/openp2p_$( [ "$(uname -m)" = x86_64 ] && echo x86_64 || echo aarch64 )"
bash "$R/cmd/install_callback"; echo "  install_callback rc=$?"
MA=$(md5sum "$BIN" 2>/dev/null | awk '{print $1}')
cat "$LOG"
[ -x "$BIN" ] && [ "$MB" = "$MA" ] && res "沿用旧二进制且 md5 不变" 1 || res "旧二进制被改动/丢失" 0
grep -q '沿用' "$LOG" && res "日志有『沿用已有二进制』记录" 1 || res "日志缺少沿用记录" 0
echo 'token=12345678' > "$SETTINGS"
bash "$R/cmd/main" start >/dev/null 2>&1; sleep 2
[ "$(nproc_o2p)" = 1 ] && res "沿用后仍能正常启动" 1 || res "沿用后起不来" 0
stopq

echo
echo "=========== 块 A 汇总：PASS=$P  FAIL=$F ==========="
