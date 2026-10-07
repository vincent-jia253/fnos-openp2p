#!/bin/bash
# fnOS 运行时模拟：把 .fpk 装进沙箱目录，走完安装→启动→状态→停止→幂等→异常 全流程
# 服务端指向 127.0.0.1:1，确保不访问真实 openp2p API
set -u

# 路径按脚本自身位置推导（谁 clone 下来都能跑），产物取 dist/ 下最新的一份
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
FPK="$(ls -t "$PROJ"/dist/*.fpk 2>/dev/null | head -n 1)"
if [ -z "$FPK" ]; then
    echo "❌ 没有找到 $PROJ/dist/*.fpk —— 请先执行 ./build.sh 构建安装包" >&2
    exit 1
fi
echo "▶ 被测包：$FPK"
SIM="/tmp/fnos-sim"
ROOT="$SIM/var/apps/openp2p"
DATA="$ROOT/shares/openp2p"
BIN="$DATA/openp2p"

PASS=0; FAIL=0
ok()   { echo "   ✅ $1"; PASS=$((PASS+1)); }
bad()  { echo "   ❌ $1"; FAIL=$((FAIL+1)); }
procs() { ps -eo pid,cmd 2>/dev/null | grep -F "$BIN" | grep -v grep; }
nprocs() { procs | wc -l | tr -d ' '; }

rm -rf "$SIM"
mkdir -p "$SIM/pkg" "$ROOT" "$SIM/log/apps"

echo "=== 0) 解包 fpk ==="
tar -xzf "$FPK" -C "$SIM/pkg" || exit 1
cp -a "$SIM/pkg/cmd" "$SIM/pkg/wizard" "$SIM/pkg/config" "$SIM/pkg/manifest" "$ROOT/"
mkdir -p "$ROOT/target"
tar -xzf "$SIM/pkg/app.tgz" -C "$ROOT/target" || exit 1
echo "解包后 target/："; ls "$ROOT/target"

export OPENP2P_APPROOT="$ROOT"
export TRIM_APPNAME="openp2p"
export TRIM_APPDEST="$ROOT/target"
export TRIM_PKGVAR="$ROOT/var"
export TRIM_TEMP_LOGFILE="$SIM/install.err"
export LOG_FILE="$SIM/log/apps/openp2p.log"

echo
echo "=== 1) install_callback（模拟安装向导填写）==="
openp2p_token=123456 openp2p_node=TESTNAS01 openp2p_sharebandwidth=10 \
openp2p_serverhost=127.0.0.1 openp2p_serverport=1 \
    bash "$ROOT/cmd/install_callback"
rc=$?; [ "$rc" = 0 ] && ok "install_callback exit=0" || bad "install_callback exit=$rc"
echo "--- 安装日志 ---"; cat "$LOG_FILE" 2>/dev/null
echo "--- 数据目录 ---"; ls -la "$DATA"
[ -x "$BIN" ] && ok "二进制已部署到数据目录 $BIN" || bad "二进制未部署到数据目录"
[ -f "$DATA/settings.conf" ] && ok "settings.conf 已写入" || bad "settings.conf 缺失"
grep -q '^token=123456$' "$DATA/settings.conf" && ok "token 已落盘" || bad "token 未落盘"
[ -f "$ROOT/target/bin/openp2p_x86_64" ] && bad "包内二进制未清理（应删掉以省空间）" \
                                         || ok "包内多架构二进制已清理"

echo
echo "=== 2) main start ==="
bash "$ROOT/cmd/main" start; rc=$?
[ "$rc" = 0 ] && ok "start exit=0" || bad "start exit=$rc"
[ -f "$ROOT/var/app.pid" ] && ok "pid 文件已写：$(cat "$ROOT/var/app.pid")" || bad "pid 文件缺失"
[ "$(nprocs)" = 1 ] && ok "进程数=1" || bad "进程数=$(nprocs)"

echo
echo "=== 3) main status（运行中应为 0）==="
bash "$ROOT/cmd/main" status; rc=$?
[ "$rc" = 0 ] && ok "status exit=0" || bad "status exit=$rc"

echo
echo "=== 4) config.json / log 是否落在数据目录（而非 target/bin）==="
ls -la "$DATA"
[ -f "$DATA/config.json" ] && ok "config.json 落在数据目录（cd 生效）" \
                           || bad "config.json 未落在数据目录 → 升级会丢配置"
[ -d "$DATA/log" ] && ok "log/ 落在数据目录" || bad "log/ 未落在数据目录"
[ -f "$ROOT/target/bin/config.json" ] && bad "config.json 误落在 target/bin（升级会丢）" \
                                      || ok "target/bin 无 config.json"
echo "--- config.json ---"; cat "$DATA/config.json" 2>/dev/null
perm=$(stat -c '%a' "$DATA/config.json" 2>/dev/null)
[ "$perm" = "600" ] && ok "config.json 权限已收紧 600（含 Token）" || bad "config.json 权限=$perm（含 Token，应为 600）"
echo "--- 进程 ---"; procs

# Token 安全：不得出现在命令行（ps 里任何本机用户可见）
if procs | grep -q '123456'; then
    bad "Token 出现在命令行参数中（ps 可见，应改为写入 config.json）"
else
    ok "Token 未出现在命令行（ps 不可见）"
fi
grep -q '"Token": 123456' "$DATA/config.json" 2>/dev/null && ok "Token 已写入 config.json" \
                                                         || bad "config.json 中未找到 Token"

echo
echo "=== 5) 重复 start（幂等性）==="
bash "$ROOT/cmd/main" start; rc=$?
[ "$rc" = 0 ] && ok "start(again) exit=0" || bad "start(again) exit=$rc"
[ "$(nprocs)" = 1 ] && ok "未重复起进程（进程数=1）" || bad "进程数=$(nprocs)（重复启动）"

echo
echo "=== 6) main stop ==="
bash "$ROOT/cmd/main" stop; rc=$?
[ "$rc" = 0 ] && ok "stop exit=0" || bad "stop exit=$rc"

echo
echo "=== 7) stop 后 status（应为 3=未运行）==="
bash "$ROOT/cmd/main" status; rc=$?
[ "$rc" = 3 ] && ok "status exit=3" || bad "status exit=$rc（期望 3）"
[ "$(nprocs)" = 0 ] && ok "无残留进程" || bad "残留进程数=$(nprocs)"

echo
echo "=== 8) 未填 Token 时仍须正常启动（-8 起的行为：不登录组网，但界面必须进得去）==="
sed -i 's/^token=.*/token=/' "$DATA/settings.conf"
bash "$ROOT/cmd/main" start; rc=$?
[ "$rc" = 0 ] && ok "start(no-token) 优雅返回 0" || bad "start(no-token) exit=$rc"
[ "$(nprocs)" = 1 ] && ok "未填 Token 也起了进程" \
                     || bad "未填 Token 竟没起进程（nprocs=$(nprocs)）—— 那界面进不去，Token 就永远填不上"
grep -q '尚未配置 Token' "$LOG_FILE" 2>/dev/null && ok "日志明确提示尚未配置 Token" \
                                                 || bad "日志未提示 Token 状态"
# 清空 Token 必须写进 config.json（否则"在界面上清空"会被旧值复活）
grep -qE '"Token": *0' "$DATA/config.json" 2>/dev/null && ok "config.json 里的 Token 已被清为 0（旧值不复活）" \
                                                       || bad "config.json 仍留着旧 Token"
bash "$ROOT/cmd/main" stop >/dev/null 2>&1

echo
echo "=== 9) 重装/修复场景（数据目录已有二进制，包内 payload 已清空）==="
# 先把 token 填回去（第 8 步清空了）；重装必须保留用户设置，这是刻意设计
sed -i 's/^token=.*/token=123456/' "$DATA/settings.conf"
bash "$ROOT/cmd/install_callback" >/dev/null 2>&1
[ -x "$BIN" ] && ok "修复安装后二进制仍在" || bad "修复安装把二进制弄丢了"
grep -q '^token=123456$' "$DATA/settings.conf" && ok "修复安装保留了用户设置（未冲掉 Token）" \
                                             || bad "修复安装冲掉了用户设置"
bash "$ROOT/cmd/main" start >/dev/null 2>&1
[ "$(nprocs)" = 1 ] && ok "修复安装后仍能启动" || bad "修复安装后起不来"
bash "$ROOT/cmd/main" stop >/dev/null 2>&1

echo
echo "=== 10) 卸载 ==="
bash "$ROOT/cmd/uninstall_init" >/dev/null 2>&1; rc1=$?
[ "$rc1" = 0 ] && ok "uninstall_init exit=0" || bad "uninstall_init exit=$rc1"
echo "（uninstall_callback 需 TRIM_* 环境完整，此处只验证 init 不误删数据）"
[ -d "$DATA" ] && ok "uninstall_init 未提前删掉用户数据" || bad "数据被 init 删了"

echo
echo "=== 11) 日志全文 ==="
cat "$LOG_FILE"

echo
echo "===================================="
echo "  通过 $PASS 项，失败 $FAIL 项"
echo "===================================="
[ "$FAIL" = 0 ] || exit 1
