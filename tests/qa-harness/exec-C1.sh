#!/bin/bash
# 块 C1：TC-19 ~ TC-22（卸载保留/删除数据、日志、非法输入拒绝）
# —— 路径自解析：谁 clone 下来都能跑 ——
# 解析顺序：$OPENP2P_ROOT → 从脚本目录向上找含 src/openp2p 的目录 → 常见相对布局 → 从 $PWD 向上找
find_root(){
  local d c x
  d="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"; [ -n "$d" ] || d="$PWD"
  x="$d"
  while [ "$x" != / ]; do [ -d "$x/src/openp2p" ] && { printf %s "$x"; return 0; }; x="$(dirname "$x")"; done
  for c in "$d/../.." "$d/../../../../projects/fnos-openp2p" "$d/../../../../../projects/fnos-openp2p" "$PWD"; do
    c="$(cd "$c" 2>/dev/null && pwd)"
    [ -n "$c" ] && [ -d "$c/src/openp2p" ] && { printf %s "$c"; return 0; }
  done
  x="$PWD"
  while [ "$x" != / ]; do [ -d "$x/src/openp2p" ] && { printf %s "$x"; return 0; }; x="$(dirname "$x")"; done
}
ROOT="${OPENP2P_ROOT:-$(find_root)}"
[ -d "$ROOT/src/openp2p" ] || { echo "找不到项目根（含 src/openp2p）；可用 OPENP2P_ROOT=<项目路径> 指定" >&2; exit 1; }
PKG="${PKG:-$(ls -t "$ROOT"/dist/*.fpk 2>/dev/null | head -n 1)}"
[ -f "$PKG" ] || { echo "找不到安装包（$ROOT/dist/*.fpk），请先执行 ./build.sh" >&2; exit 1; }
R=/tmp/qac; DATA="$R/shares/openp2p"; V="$R/var"
P=0; F=0
res(){ if [ "$2" = 1 ]; then P=$((P+1)); echo "  [PASS] $1"; else F=$((F+1)); echo "  [FAIL] $1"; fi; }
prep(){ # 卫生：rm -rf 会连 PID 文件一起删，若有上例残留进程就会变成孤儿并污染断言 → 先报告并清理
  if ps -eo pid,cmd | grep -F "$DATA/openp2p" | grep -v grep | grep -q .; then
    echo "  [harness] 清理上例残留进程"; pkill -x openp2p 2>/dev/null; sleep 1; fi
  rm -rf "$R"; mkdir -p "$R" "$V" "$R/target" "$DATA"
  tar xzf "$PKG" -C "$R"; tar xzf "$R/app.tgz" -C "$R/target"; : > "$R/apps.log"
  export OPENP2P_APPROOT="$R" TRIM_APPNAME=openp2p TRIM_APPDEST="$R/target" TRIM_PKGVAR="$V" LOG_FILE="$R/apps.log"
  bash "$R/cmd/install_callback" >/dev/null 2>&1
  echo "token=12345678" > "$DATA/settings.conf"; }

echo "=========== TC-19 uninstall_init 停进程但保留数据 (R6,R3) ==========="
prep; bash "$R/cmd/main" start >/dev/null 2>&1; sleep 3
S1=$(md5sum "$DATA/settings.conf" | awk '{print $1}')
bash "$R/cmd/uninstall_init"; echo "  uninstall_init rc=$?"
sleep 1
[ "$(pgrep -c -f "$DATA/openp2p" || true)" = "0" ] && res "进程已停止" 1 || res "进程未停止" 0
[ -f "$DATA/settings.conf" ] && res "settings.conf 保留" 1 || res "settings.conf 被删" 0
S2=$(md5sum "$DATA/settings.conf" 2>/dev/null | awk '{print $1}')
[ "$S1" = "$S2" ] && res "settings.conf 内容未变" 1 || res "settings.conf 内容变了" 0
[ -f "$DATA/config.json" ] && res "config.json 保留" 1 || res "config.json 被删" 0
[ -d "$DATA/log" ] && res "log/ 保留" 1 || res "log/ 被删" 0

echo "=========== TC-20 uninstall_callback 删除数据分支 (R6) ==========="
prep; bash "$R/cmd/main" start >/dev/null 2>&1; sleep 3
openp2p_data_action=delete bash "$R/cmd/uninstall_callback"; echo "  uninstall_callback(delete) rc=$?"
[ ! -d "$DATA" ] && res "选择删除时 DATA_DIR 已清理" 1 || res "DATA_DIR 仍存在" 0
[ "$(pgrep -c -f "$DATA/openp2p" || true)" = "0" ] && res "无进程残留" 1 || res "有进程残留" 0

echo "=========== TC-20b uninstall_callback 保留数据分支 (R6,R3) ==========="
prep; echo "token=12345678" > "$DATA/settings.conf"
openp2p_data_action=keep bash "$R/cmd/uninstall_callback"; echo "  uninstall_callback(keep) rc=$?"
[ -f "$DATA/settings.conf" ] && res "选择保留时数据仍在" 1 || res "选择保留却删了数据" 0

echo "=========== TC-21 日志可诊断且不含 Token (R8,I5) ==========="
prep; bash "$R/cmd/main" start >/dev/null 2>&1; sleep 3; bash "$R/cmd/main" stop >/dev/null 2>&1
[ -s "$R/apps.log" ] && res "LOG_FILE 存在且非空" 1 || res "LOG_FILE 为空" 0
grep -q '启动中' "$R/apps.log" && res "含启动信息" 1 || res "缺启动信息" 0
grep -q '已停止' "$R/apps.log" && res "含停止信息" 1 || res "缺停止信息" 0
N=$(grep -c '12345678' "$R/apps.log" || true)
[ "$N" = "0" ] && res "日志中 Token 出现 0 次" 1 || res "日志泄露 Token ${N} 次" 0

echo "=========== TC-22 非法 token/node 被拒绝且有提示 (校验契约) ==========="
prep; rm -f "$DATA/settings.conf"; : > "$R/install.err"
export TRIM_TEMP_LOGFILE="$R/install.err"
openp2p_token='12ab34' bash "$R/cmd/config_callback"; echo "  config_callback(非法token) rc=$?"
bash "$R/cmd/main" status; RC=$?
# B8 之后：进程是否运行与 Token 合法性解耦（无/非法 Token 也运行，只是不登录）。
# 因此本用例的关键不变式改为：非法值必须被拒绝，且绝不能落到配置里/传给 openp2p。
echo "  status rc=$RC（B8 后允许为 0；关键在于下面的『未写入/未传递』断言）"
grep -q '12ab34' "$DATA/settings.conf" 2>/dev/null && res "非法 token 未写入 settings.conf" 0 || res "非法 token 未写入 settings.conf" 1
grep -q '12ab34' "$DATA/config.json" 2>/dev/null && res "非法 token 未传给 openp2p" 0 || res "非法 token 未传给 openp2p（config.json 中无此值）" 1
grep -q 'Token 只接受数字' "$R/apps.log" && res "日志有拒绝提示" 1 || res "缺拒绝提示" 0
grep -q 'Token 只接受数字' "$R/install.err" && res "用户可见提示（TRIM_TEMP_LOGFILE）已写入" 1 || res "未写用户可见提示" 0
openp2p_node='bad name!*' bash "$R/cmd/config_callback" >/dev/null 2>&1
grep -q '^node=bad name' "$DATA/settings.conf" 2>/dev/null && res "非法 node 未写入配置" 0 || res "非法 node 未写入配置（已回退）" 1
grep -q '节点名须为' "$R/apps.log" && res "node 拒绝提示已记录" 1 || res "缺 node 拒绝提示" 0

echo
echo "=========== 块 C1 汇总：PASS=$P  FAIL=$F ==========="
bash "$R/cmd/main" stop >/dev/null 2>&1
