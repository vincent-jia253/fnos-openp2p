#!/bin/bash
# 块 G：真机根因回归（B9/B10/守护判定）
#
# 为什么必须单独一块：块 A–F 的 sandbox 用了「真实目录」作为 DATA_DIR
#   （OPENP2P_APPROOT=$R → shares/openp2p 是真目录），
# 因此完全测不出真机那类「路径形态不一致」的缺陷 —— 而真机上 12 秒起了 3 个实例。
#
# B11【真机根因】DATA_DIR 落在 /var/apps/<app>/shares/<app>，而该目录是指向
#   /volN/@appshare/<app> 的**符号链接**；/proc/<pid>/exe 给出的是解析后的真实路径，
#   与 $BIN 字符串永远不相等 → is_our_pid 恒为假：
#     · status 永远显示"已停止"
#     · 每次 start 都判"未运行" → 重复起实例（真机 12 秒 3 个，互抢 1025 端口）
#     · stop 认为 PID 文件"指向的不是本应用" → 拒绝按 PID 停止
# B12【真机后果】stop 只清理 find_pid 找到的**一个**进程；真机同时残留 2 个实例时，
#   另一个继续占用端口刷 bind 错误，用户以为已经停了。
# B13【升级场景】二进制被升级替换后，旧进程 /proc/<pid>/exe 带 " (deleted)"，
#   必须仍能被认领并停止，否则新旧实例会长期共存。
# B9【误杀风险】机器上可能有另一份也叫 openp2p 的程序，绝不能被我们认领/杀掉。
#
# 被测对象：**源码树**（打包前先验）
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
SRC="$ROOT/src/openp2p"
R=/tmp/qaG
REAL=/tmp/qaG-realdata            # 符号链接指向的真实数据目录（模拟 /volN/@appshare/openp2p）
DATA="$R/shares/openp2p"          # ← 真机形态：这是符号链接，不是真目录
V="$R/var"
OTHER=/tmp/qaG-other              # 冒充的"另一份 openp2p"
P=0; F=0
res(){ if [ "$2" = 1 ]; then P=$((P+1)); echo "  [PASS] $1"; else F=$((F+1)); echo "  [FAIL] $1"; fi; }
say(){ echo; echo "=========== $* ==========="; }
cnt(){ pgrep -f "^$DATA/openp2p" 2>/dev/null | wc -l | tr -d ' '; }
run(){ bash "$R/cmd/main" "$@" >/dev/null 2>&1; echo $?; }
cleanup(){
    bash "$R/cmd/main" stop >/dev/null 2>&1
    pkill -f "^$DATA/openp2p" 2>/dev/null
    pkill -f "^$OTHER/openp2p" 2>/dev/null
    sleep 1
}

echo "被测源码: $SRC"
echo "包 md5  : $(md5sum "$PKG" | awk '{print $1}')（二进制来源）"

stage(){  # 铺「真机形态」的目录树：shares/openp2p 是符号链接
  cleanup
  rm -rf "$R" "$REAL" "$OTHER"
  mkdir -p "$R/shares" "$V" "$R/target/bin" "$REAL" "$OTHER"
  ln -s "$REAL" "$DATA"                      # ★ 关键：符号链接，复现真机路径形态
  cp -r "$SRC"/cmd "$R/cmd"; chmod +x "$R"/cmd/*
  tar xzf "$PKG" -O app.tgz | tar xz -C "$R/target" --wildcards 'bin/openp2p_x86_64' 2>/dev/null
  mv "$R/target/bin/openp2p_x86_64" "$REAL/openp2p"; chmod +x "$REAL/openp2p"
  cp "$REAL/openp2p" "$OTHER/openp2p"        # 另一份"同名不同路径"的 openp2p
  chmod +x "$OTHER/openp2p"
  : > "$R/apps.log"
  export OPENP2P_APPROOT="$R" TRIM_APPNAME=openp2p TRIM_APPDEST="$R/target" \
         TRIM_PKGVAR="$V" LOG_FILE="$R/apps.log" TRIM_TEMP_LOGFILE="$R/install.err"
}

say "G0 前置确认：被测布局确实是符号链接形态"
stage
[ -L "$DATA" ] && res "DATA_DIR（shares/openp2p）是符号链接" 1 || res "布局构造失败，块 G 结论无效" 0
[ "$(readlink -f "$DATA")" = "$REAL" ] && res "符号链接解析到 $REAL" 1 || res "readlink -f 结果异常" 0

say "G1 符号链接数据目录下：start → status 必须报「运行中」（B11 核心）"
RC=$(run start)
[ "$RC" = 0 ] && res "start rc=0" 1 || res "start rc=$RC（期望 0）" 0
sleep 1
ST=$(run status)
[ "$ST" = 0 ] && res "status rc=0（运行中）" 1 || res "status rc=$ST（期望 0）" 0
N=$(cnt); [ "$N" = 1 ] && res "进程数=1" 1 || res "进程数=$N（期望 1）" 0

say "G2 符号链接下重复 start → 不得产生第二个实例（B11 真机 3 实例的直接原因）"
for i in 1 2 3; do run start >/dev/null; done
sleep 1
N=$(cnt)
[ "$N" = 1 ] && res "连续 4 次 start 后仍只有 1 个进程" 1 || res "出现 $N 个进程（旧代码真机实测 12 秒 3 个）" 0
grep -q '已在运行' "$R/apps.log" && res "日志出现『已在运行，跳过启动』" 1 || res "日志缺少幂等提示" 0

say "G3 符号链接下 stop → 必须真的停掉，且 status 归 3"
RC=$(run stop)
[ "$RC" = 0 ] && res "stop rc=0（不谎报）" 1 || res "stop rc=$RC" 0
sleep 1
N=$(cnt); [ "$N" = 0 ] && res "无残留进程" 1 || res "残留 $N 个进程" 0
ST=$(run status)
[ "$ST" = 3 ] && res "status rc=3（未运行）" 1 || res "status rc=$ST（期望 3）" 0

say "G4 PID 文件丢失 → status/start 必须靠进程探测自愈（B10）"
stage
run start >/dev/null; sleep 1
rm -f "$V/app.pid"                       # 模拟 PID 文件丢失/环境不一致
ST=$(run status)
[ "$ST" = 0 ] && res "PID 文件缺失时 status 仍报运行中" 1 || res "status rc=$ST（期望 0）" 0
[ -s "$V/app.pid" ] && res "PID 文件已被自动修复重建" 1 || res "PID 文件未重建" 0
run start >/dev/null; sleep 1
N=$(cnt); [ "$N" = 1 ] && res "PID 文件缺失后再次 start 不起新实例" 1 || res "起了 $N 个进程" 0
cleanup

say "G5 多实例残留 → stop 必须【全部】清理（B12）"
stage
run start >/dev/null; sleep 1
# 手工再造一个"重复启动遗留"实例（命令行前缀同 $BIN，会被 find_all_pids 通道 1 捕获）
nohup "$DATA/openp2p" -node dup -sharebandwidth 10 -serverhost api.openp2p.cn \
      -serverport 27183 -loglevel 3 -installpath "$REAL" >/dev/null 2>&1 &
sleep 2
N=$(cnt); [ "$N" -ge 2 ] && res "已构造出 $N 个实例（前置条件成立）" 1 || res "只造出 $N 个实例，前置条件不足" 0
RC=$(run stop)
[ "$RC" = 0 ] && res "stop rc=0" 1 || res "stop rc=$RC" 0
sleep 1
N=$(cnt); [ "$N" = 0 ] && res "全部实例已清理（旧代码只杀一个，另一个继续占端口）" 1 || res "仍残留 $N 个进程" 0

say "G6 升级场景：二进制被替换后，旧进程 exe 带 (deleted) 仍应被认领（B13）"
stage
run start >/dev/null; sleep 1
OLD=$(cnt); [ "$OLD" = 1 ] && res "旧实例已启动" 1 || res "旧实例数=$OLD" 0
# 模拟升级：同路径换新 inode（旧进程的 exe 变成 "...openp2p (deleted)"）
cp "$OTHER/openp2p" "$REAL/openp2p.new" && mv -f "$REAL/openp2p.new" "$REAL/openp2p" && chmod +x "$REAL/openp2p"
ST=$(run status)
[ "$ST" = 0 ] && res "二进制被替换后 status 仍报运行中（认领 (deleted) 旧进程）" 1 || res "status rc=$ST（期望 0）" 0
run start >/dev/null; sleep 1
N=$(cnt); [ "$N" = 1 ] && res "升级后 start 不产生新实例（先停旧再启由 config/升级流程负责）" 1 || res "出现 $N 个进程（新旧共存）" 0
RC=$(run stop)
[ "$RC" = 0 ] && res "stop rc=0（能停掉 (deleted) 旧进程）" 1 || res "stop rc=$RC" 0
sleep 1
N=$(cnt); [ "$N" = 0 ] && res "无残留" 1 || res "残留 $N 个进程" 0

say "G7 隔离性：不得认领/误杀另一份也叫 openp2p 的程序（B9）"
stage
# 先让"别人的" openp2p 跑起来
nohup "$OTHER/openp2p" -node other -sharebandwidth 10 -serverhost api.openp2p.cn \
      -serverport 27183 -loglevel 3 -installpath "$OTHER" >/dev/null 2>&1 &
sleep 2
OP=$(pgrep -f "^$OTHER/openp2p" 2>/dev/null | head -n 1)
if [ -z "$OP" ]; then
    echo "  [SKIP] 另一份 openp2p 未能常驻，本项无法判定（环境限制）"
else
    res "前置：另一份 openp2p 正在运行 (pid=$OP)" 1
    ST=$(run status)
    [ "$ST" = 3 ] && res "本应用未运行时 status 不被『同名进程』带成运行中" 1 || res "status rc=$ST（期望 3，被同名进程误报）" 0
    RC=$(run stop)
    sleep 1
    kill -0 "$OP" 2>/dev/null && res "stop 未误杀另一份 openp2p（进程仍在）" 1 || res "stop 误杀了另一份 openp2p（严重）" 0
    kill -TERM "$OP" 2>/dev/null
fi

# 伪装用例（P2-4）：argv0 与本应用二进制路径【完全相同】，但 exe 其实是 /usr/bin/sleep。
# 本机任何用户都能用 `exec -a <path> sleep 45` 造出来；若 find_all_pids 的命令行通道
# 只比 argv0 就采信，stop 会去 SIGTERM 这个无关进程 —— 与 B5「误杀无关进程」同类。
nohup bash -c "exec -a '$DATA/openp2p' sleep 45" >/dev/null 2>&1 &
SP=$!
sleep 1
if [ -n "$SP" ] && [ -d "/proc/$SP" ]; then
    res "前置：已造出 argv0 伪装进程 (pid=$SP)" 1
    run stop >/dev/null
    sleep 1
    if [ -d "/proc/$SP" ]; then
        res "stop 未误杀 argv0 伪装进程（P2-4 已修）" 1
    else
        res "stop 误杀了 argv0 伪装进程（命令行通道未校验 exe）" 0
    fi
    kill -TERM "$SP" 2>/dev/null
else
    res "前置失败：argv0 伪装进程未起来" 0
fi

say "G8 界面 running_pid 与 cmd/common 判据一致（界面不再自造一套）"
grep -q 'is_running || return 1' "$SRC/app/ui/index.cgi" \
    && res "index.cgi 的 running_pid 复用 cmd/common 的 is_running" 1 \
    || res "index.cgi 仍在自己实现判活逻辑（跨用户 kill -0 / 未校验 pidof 会误判）" 0
grep -qE '^\s*[^#]*kill -0|^\s*[^#]*pidof ' "$SRC/app/ui/index.cgi" \
    && res "index.cgi 仍残留 kill -0/pidof 判活" 0 \
    || res "index.cgi 已无 kill -0/pidof 判活" 1

say "G9 对照组自我验证：Legacy 3.25.11-1 代码必须在本用例上失败"
# 目的：证明 G1–G8 不是「无论如何都通过」的假绿。用真机当年装的那份 -1 代码
# （快照见 legacy-3.25.11-1-cmd/）在同样的符号链接布局下跑，必须复现重复实例。
LEG="$(cd "$(dirname "$0")" && pwd)/legacy-3.25.11-1-cmd"
if [ -d "$LEG" ]; then
    L=/tmp/qaG-legacy; LR=/tmp/qaG-legacy-real
    cleanup
    rm -rf "$L" "$LR"; mkdir -p "$L/shares" "$L/var" "$L/target/bin" "$LR"
    ln -s "$LR" "$L/shares/openp2p"
    cp -r "$LEG" "$L/cmd"; chmod +x "$L"/cmd/*
    cp "$OTHER/openp2p" "$LR/openp2p"; chmod +x "$LR/openp2p"
    # 必须给 Token：否则 -1 会因 B8 直接跳过启动，对照组会被 B8 污染而测不到 B11
    printf 'token=123456789\nnode=legacy\nsharebandwidth=10\nserverhost=api.openp2p.cn\nserverport=27183\nloglevel=1\n' > "$LR/settings.conf"
    : > "$L/apps.log"
    (
      export OPENP2P_APPROOT="$L" TRIM_APPNAME=openp2p TRIM_APPDEST="$L/target" \
             TRIM_PKGVAR="$L/var" LOG_FILE="$L/apps.log"
      bash "$L/cmd/main" start >/dev/null 2>&1
      sleep 2
      for i in 2 3 4; do bash "$L/cmd/main" start >/dev/null 2>&1; done
      sleep 2
    )
    LN=$(pgrep -f "^$L/shares/openp2p" 2>/dev/null | wc -l | tr -d ' ')
    [ "$LN" -gt 1 ] && res "旧代码复现重复实例（${LN} 个）——证明本用例确实能抓 B11" 1 \
                    || res "旧代码只起了 ${LN} 个实例，用例鉴别力不足，G1–G8 结论存疑" 0
    pkill -f "^$L/shares/openp2p" 2>/dev/null; pkill -f "^$LR" 2>/dev/null; sleep 1
else
    echo "  [SKIP] 未找到 legacy-3.25.11-1-cmd 快照，跳过对照组"
fi

cleanup
echo
echo "=========== 块 G 汇总：PASS=$P  FAIL=$F ==========="
[ "$F" = 0 ] || exit 1
