#!/bin/bash
# 块 I：可移植性阻塞项修复（`-9`）
#
# 为什么必须有这一块：
#   QA 的可移植性专项审计（`qa/qa-portability-review.md`）判「有条件可以给陌生人用」，
#   并给出 3 条阻塞项 —— 它们的共同点是**只在"别人的机器/别的时序"上才暴露**，
#   作者本机跑一万遍也看不到：
#     P1 卸载选「删除配置」实际没删（数据目录是符号链接，rm -rf 只删了链接）
#     P2 config.json 没有 Token 键时被整文件覆盖 → 用户手写的 apps[] 静默清零
#     P3 运行时目录建不出来时，启动锁 0.2 秒一轮死循环 → CLI/界面一起挂死
#   本块为每条都配**对照组**（用 `-8` 包里的旧实现跑同一场景），证明用例有鉴别力。
#
# 被测对象：源码树 src/openp2p/cmd/*；对照组取自 dist/openp2p_3.25.11-8_all.fpk（修复前）
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
[ -d "$ROOT/src/openp2p" ] || { echo "找不到项目根（含 src/openp2p）" >&2; exit 1; }
SRC="$ROOT/src/openp2p"
PKG="${OLD_FPK:-$ROOT/dist/openp2p_3.25.11-8_all.fpk}"
R=/tmp/qaI
OLD="$R/old"
export LOG_FILE="$R/logs/openp2p.log"
P=0; F=0
res(){ if [ "$2" = 1 ]; then P=$((P+1)); echo "  [PASS] $1"; else F=$((F+1)); echo "  [FAIL] $1"; fi; }
say(){ echo; echo "=========== $* ==========="; }

mkdir -p "$R/logs"
echo "被测源码: $SRC"
echo "对照组包: $PKG (md5 $(md5sum "$PKG" 2>/dev/null | awk '{print $1}'))"

# 对照组：把 `-8` 包里的 cmd/ 解出来（修复前的实现）
rm -rf "$OLD"; mkdir -p "$OLD"
# 对照组来源优先级：
#   ① 冻结快照 legacy-8-cmd/（跟仓库走，任何人 clone 下来都能复跑对照组）
#   ② dist 里的 -8 包（作者本机有；外来者通常没有）
SNAP="$(cd "$(dirname "$0")" && pwd)/legacy-8-cmd"
if [ -f "$SNAP/common" ]; then
    cp -a "$SNAP"/. "$OLD"/ 2>/dev/null
    echo "对照组来源: 冻结快照 $SNAP"
elif [ -f "$PKG" ]; then
    tar -xzf "$PKG" -C "$OLD" 2>/dev/null            # 包根里有 cmd/
    if [ -d "$OLD/cmd" ]; then cp -a "$OLD/cmd"/. "$OLD"/ && rm -rf "$OLD/cmd"; fi
    echo "对照组来源: 包内 cmd/（$PKG）"
else
    echo "  [harness] ⚠️ 无对照组来源（缺 legacy-8-cmd/ 与 -8 包），对照组将跳过"
fi
OLD_CMD="$OLD"
[ -f "$OLD_CMD/common" ] || echo "  [harness] ⚠️ 对照组内容为空，I1/I2/I3 的对照组断言会 FAIL"
# 第二组对照：冻结快照 legacy-9-cmd/（`-9` = qa 第七轮已复核、但 N5~N10 加固前的实现）
OLD9_CMD="$(cd "$(dirname "$0")" && pwd)/legacy-9-cmd"

# 每次用例前把沙箱恢复成"可删"状态：权限收紧过就删不掉
sandbox_rm(){
  [ -e "$1" ] || return 0
  chmod -R u+rwX "$1" 2>/dev/null
  rm -rf "$1" 2>/dev/null
}

########################################################################
say "I1 · 卸载选「删除配置」必须真的删掉 Token（P1）"
########################################################################
# fnOS 的真实形态：APPLICATION/shares/<app> 是指向数据卷的**符号链接**
# 沙箱里用 $R/volN/@appshare/openp2p 扮演数据卷上的真实目录
mkreal(){
  local root="$1"; sandbox_rm "$root"; mkdir -p "$root/app/shares" "$root/volN/@appshare/openp2p/var" "$root/logs"
  printf '{"network":{"Token":314159265358}}\n' > "$root/volN/@appshare/openp2p/config.json"
  printf 'token=314159265358\nnode=demo\n' > "$root/volN/@appshare/openp2p/settings.conf"
  ln -s "$root/volN/@appshare/openp2p" "$root/app/shares/openp2p"
}
run_uninstall(){   # $1=cmd 目录  $2=sandbox root
  ( export TRIM_APPNAME=openp2p OPENP2P_APPROOT="$2/app" TRIM_PKGVAR="$2/app/var" \
           LOG_FILE="$2/logs/openp2p.log" openp2p_data_action=delete
    bash "$1/uninstall_callback" >/dev/null 2>&1 )
}

# --- 新实现 ---
mkreal "$R/i1new"
run_uninstall "$SRC/cmd" "$R/i1new"
[ ! -e "$R/i1new/volN/@appshare/openp2p" ] && res "I1a 数据卷上的真实目录已删除" 1 || res "I1a 数据卷上的真实目录已删除（仍存在：$(ls -A "$R/i1new/volN/@appshare/openp2p" 2>/dev/null | tr '\n' ' ')）" 0
[ ! -e "$R/i1new/app/shares/openp2p" ] && res "I1b 符号链接已清理" 1 || res "I1b 符号链接已清理" 0
grep -q '314159265358' "$R/i1new/volN/@appshare/openp2p/config.json" 2>/dev/null && res "I1c Token 已从磁盘消失" 0 || res "I1c Token 已从磁盘消失" 1
grep -q '已按用户选择删除配置' "$R/i1new/logs/openp2p.log" 2>/dev/null && res "I1d 日志如实报告已删除" 1 || res "I1d 日志如实报告已删除（日志内容：$(tail -1 "$R/i1new/logs/openp2p.log" 2>/dev/null)）" 0

# --- 对照组：修复前实现（应当"删了链接却留下 Token"）---
if [ -f "$OLD_CMD/uninstall_callback" ]; then
  mkreal "$R/i1old"
  run_uninstall "$OLD_CMD" "$R/i1old"
  if [ -e "$R/i1old/volN/@appshare/openp2p/config.json" ] && grep -q '314159265358' "$R/i1old/volN/@appshare/openp2p/config.json"; then
    echo "  [对照] 旧实现：Token 仍在数据卷上（LEAK）→ 本用例有鉴别力"
  else
    echo "  [对照] ⚠️ 旧实现竟然删掉了数据 —— 对照组无效，I1a/I1c 的结论不能采信"
    F=$((F+1))
  fi
else
  echo "  [对照] 缺少旧实现快照，跳过"
fi

# --- "保留配置"分支：不许误删 ---
mkreal "$R/i1keep"
( export TRIM_APPNAME=openp2p OPENP2P_APPROOT="$R/i1keep/app" TRIM_PKGVAR="$R/i1keep/app/var" \
         LOG_FILE="$R/i1keep/logs/openp2p.log" openp2p_data_action=keep
  bash "$SRC/cmd/uninstall_callback" >/dev/null 2>&1 )
[ -f "$R/i1keep/volN/@appshare/openp2p/config.json" ] && res "I1e 选「保留配置」时数据完好" 1 || res "I1e 选「保留配置」时数据完好" 0

# --- 安全守卫：不许删白名单之外的路径 ---
mkdir -p "$R/i1guard/app/shares" "$R/i1guard/important"
printf 'x\n' > "$R/i1guard/important/keepme"
ln -s "$R/i1guard/important" "$R/i1guard/app/shares/openp2p"
run_uninstall "$SRC/cmd" "$R/i1guard"
[ -f "$R/i1guard/important/keepme" ] && res "I1f 白名单外的目录被拒绝删除（守卫生效）" 1 || res "I1f 白名单外的目录被拒绝删除（守卫生效）—— 误删了！" 0

########################################################################
say "I2 · 冷启动不许清掉用户手写的 apps[]（P2）"
########################################################################
mksandbox2(){   # $1=root  $2=config.json 内容
  sandbox_rm "$1"; mkdir -p "$1/app/shares/openp2p" "$1/logs"
  printf '%s\n' "$2" > "$1/app/shares/openp2p/config.json"
}
driver(){   # $1=cmd 目录  $2=sandbox root  $3=token
  ( export TRIM_APPNAME=openp2p OPENP2P_APPROOT="$2/app" TRIM_PKGVAR="$2/app/var" \
           LOG_FILE="$2/logs/openp2p.log"
    . "$1/common" >/dev/null 2>&1
    ensure_token_in_conf "$3" )
}

CONF_NOKEY='{"network":{"Node":"demo","ShareBandwidth":10,"apps":[{"AppName":"rdp","Protocol":"tcp","SrcPort":3389,"DstPort":3389}]}}'
# --- 新实现 ---
mksandbox2 "$R/i2new" "$CONF_NOKEY"
driver "$SRC/cmd" "$R/i2new" 123456789; rc=$?
NEWCONF="$R/i2new/app/shares/openp2p/config.json"
res "I2a ensure_token_in_conf 返回成功（rc=$rc）" $([ "$rc" = 0 ] && echo 1 || echo 0)
python3 -c 'import json,sys;json.load(open(sys.argv[1]))' "$NEWCONF" 2>/dev/null && res "I2b 改写后仍是合法 JSON" 1 || res "I2b 改写后仍是合法 JSON" 0
grep -q '"AppName": *"rdp"' "$NEWCONF" 2>/dev/null && res "I2c 用户手写的 apps[] 被保留" 1 || res "I2c 用户手写的 apps[] 被保留（内容：$(cat "$NEWCONF" 2>/dev/null)）" 0
grep -q '"Token": *123456789' "$NEWCONF" 2>/dev/null && res "I2d Token 已写入（不带引号的数字）" 1 || res "I2d Token 已写入（不带引号的数字）" 0
[ -f "${NEWCONF}.bak" ] && res "I2e 改写前已留备份 config.json.bak" 1 || res "I2e 改写前已留备份 config.json.bak" 0
[ "$(stat -c %a "${NEWCONF}.bak" 2>/dev/null)" = "600" ] && res "I2f 备份权限为 600（含 Token）" 1 || res "I2f 备份权限为 600（含 Token；实际 $(stat -c %a "${NEWCONF}.bak" 2>/dev/null)）" 0
[ "$(stat -c %a "$NEWCONF" 2>/dev/null)" = "600" ] && res "I2g config.json 权限为 600" 1 || res "I2g config.json 权限为 600（实际 $(stat -c %a "$NEWCONF" 2>/dev/null)）" 0

# --- 对照组：修复前实现 ---
if [ -f "$OLD_CMD/common" ]; then
  mksandbox2 "$R/i2old" "$CONF_NOKEY"
  driver "$OLD_CMD" "$R/i2old" 123456789
  OLDCONF="$R/i2old/app/shares/openp2p/config.json"
  if grep -q 'rdp' "$OLDCONF" 2>/dev/null; then
    echo "  [对照] ⚠️ 旧实现竟然保住了 apps —— 对照组无效"
    F=$((F+1))
  else
    echo "  [对照] 旧实现：apps[] 已丢失（内容变成 $(cat "$OLDCONF" 2>/dev/null)）→ 本用例有鉴别力"
  fi
else
  echo "  [对照] 缺少旧实现快照，跳过"
fi

# --- 已有 Token 键：替换值，仍不许丢 apps ---
mksandbox2 "$R/i2rep" '{"network":{"Token":111111111,"apps":[{"AppName":"ssh"}]}}'
driver "$SRC/cmd" "$R/i2rep" 222222222
REPCONF="$R/i2rep/app/shares/openp2p/config.json"
grep -q '"Token": *222222222' "$REPCONF" 2>/dev/null && grep -q '"ssh"' "$REPCONF" 2>/dev/null \
  && res "I2h 已有 Token 键时：换值且保留 apps" 1 || res "I2h 已有 Token 键时：换值且保留 apps（内容：$(cat "$REPCONF" 2>/dev/null)）" 0

# --- 连 network 段都没有：保留原文件，不改写 ---
mksandbox2 "$R/i2bad" '{"foo":1}'
driver "$SRC/cmd" "$R/i2bad" 333333333
grep -q '"foo": *1' "$R/i2bad/app/shares/openp2p/config.json.broken" 2>/dev/null \
  && res "I2i 结构异常时原文件被保留为 .broken（未覆盖用户文件）" 1 || res "I2i 结构异常时原文件被保留为 .broken（未覆盖用户文件）" 0

########################################################################
say "I3 · 运行时目录不可用时必须快速失败，不许挂死（P3）"
########################################################################
# 场景：$TRIM_PKGVAR 的父路径是一个**普通文件** → mkdir 必然失败，且锁目录不存在
mkbad(){ sandbox_rm "$1"; mkdir -p "$1/app/shares/openp2p" "$1/logs"; : > "$1/notadir"; }

mkbad "$R/i3new"
start_ts=$(date +%s)
( export TRIM_APPNAME=openp2p OPENP2P_APPROOT="$R/i3new/app" TRIM_PKGVAR="$R/i3new/notadir/var" \
         LOG_FILE="$R/i3new/logs/openp2p.log"
  timeout 12 bash "$SRC/cmd/main" start >/dev/null 2>&1 )
rc=$?; elapsed=$(( $(date +%s) - start_ts ))
res "I3a 启动在 ${elapsed}s 内返回（rc=$rc，不是 124 超时）" $([ "$rc" != 124 ] && [ "$elapsed" -lt 10 ] && echo 1 || echo 0)
res "I3b 返回码为 1（明确失败，不是 0 假成功）" $([ "$rc" = 1 ] && echo 1 || echo 0)
grep -q '无法创建运行时锁目录' "$R/i3new/logs/openp2p.log" 2>/dev/null \
  && res "I3c 日志给出可读原因" 1 || res "I3c 日志给出可读原因（日志：$(cat "$R/i3new/logs/openp2p.log" 2>/dev/null | tail -1)）" 0

# --- 对照组：修复前实现（应当挂死到超时）---
if [ -f "$OLD_CMD/main" ]; then
  mkbad "$R/i3old"
  ( export TRIM_APPNAME=openp2p OPENP2P_APPROOT="$R/i3old/app" TRIM_PKGVAR="$R/i3old/notadir/var" \
           LOG_FILE="$R/i3old/logs/openp2p.log"
    timeout 12 bash "$OLD_CMD/main" start >/dev/null 2>&1 )
  oldrc=$?
  if [ "$oldrc" = 124 ]; then
    echo "  [对照] 旧实现：12 秒未返回（rc=124 挂死）→ 本用例有鉴别力"
  else
    echo "  [对照] ⚠️ 旧实现 rc=$oldrc 也返回了 —— 对照组无效"
    F=$((F+1))
  fi
else
  echo "  [对照] 缺少旧实现快照，跳过"
fi

# --- 陈旧锁（>60 秒）应被清理并继续 ---
sandbox_rm "$R/i3stale"; mkdir -p "$R/i3stale/app/shares/openp2p" "$R/i3stale/app/var/.o2p.lock" "$R/i3stale/logs"
touch -d '3 minutes ago' "$R/i3stale/app/var/.o2p.lock" 2>/dev/null
( export TRIM_APPNAME=openp2p OPENP2P_APPROOT="$R/i3stale/app" TRIM_PKGVAR="$R/i3stale/app/var" \
         LOG_FILE="$R/i3stale/logs/openp2p.log"
  . "$SRC/cmd/common" >/dev/null 2>&1
  acquire_lock; echo "acquire_rc=$?" > "$R/i3stale/rc.txt"; release_lock ) >/dev/null 2>&1
grep -q 'acquire_rc=0' "$R/i3stale/rc.txt" 2>/dev/null && res "I3d 陈旧锁被清理后可正常获取（不误判为活锁）" 1 || res "I3d 陈旧锁被清理后可正常获取（不误判为活锁）" 0

# --- 新鲜锁（<60 秒）不许抢 ---
# 注意：`timeout 3 acquire_lock` 这种写法是**错的**（timeout 只能执行外部命令，
# 不能直接跑 shell 函数 → rc=127）。必须让 timeout 去跑一个 bash -c 子进程。
sandbox_rm "$R/i3held"; mkdir -p "$R/i3held/app/shares/openp2p" "$R/i3held/app/var/.o2p.lock" "$R/i3held/logs"
rm -f "$R/i3held/rc.txt"
( export TRIM_APPNAME=openp2p OPENP2P_APPROOT="$R/i3held/app" TRIM_PKGVAR="$R/i3held/app/var" \
         LOG_FILE="$R/i3held/logs/openp2p.log"
  timeout 3 bash -c ". '$SRC/cmd/common' >/dev/null 2>&1; acquire_lock; echo \"held_rc=\$?\" > '$R/i3held/rc.txt'" ) >/dev/null 2>&1
outer_rc=$?
if [ "$outer_rc" = 124 ] || grep -q 'held_rc=124' "$R/i3held/rc.txt" 2>/dev/null; then
  res "I3e 新鲜锁存在时按预期等待（不抢锁）" 1
else
  res "I3e 新鲜锁存在时按预期等待（不抢锁；outer rc=${outer_rc}，$(cat "$R/i3held/rc.txt" 2>/dev/null)）" 0
fi
[ -d "$R/i3held/app/var/.o2p.lock" ] && res "I3f 等待期间未删掉别人持有的新鲜锁" 1 || res "I3f 等待期间未删掉别人持有的新鲜锁" 0

########################################################################
say "I4 · 陈旧锁 + 锁目录删不掉（只读挂载）也不许忙等挂死（B3'）"
########################################################################
# 场景：`.o2p.lock` 已存在且 >60 秒（陈旧）→ 进"清理"分支；但所在 FS 只读 → rm 必然失败。
# 旧实现 rm 失败后是 `i=0; continue`：跳过下面的计时与 sleep → **无 sleep 忙等，永不返回**。
# （这是 qa 第七轮 B3' 实测到的残洞：10 秒刷 1309 行日志、rc=124 挂死。）
# 用 `unshare -rmn` 造私有 mount namespace 把沙箱 remount 成 ro —— **绝不碰真机挂载点**。
# 断言口径：用 O2P_LOCK_MAX_TICKS 把总时长从 120 秒缩到 2 秒（600→10 个 tick），
#   修复后必须 ~2 秒内以 rc=1 返回；对照组（-8 旧实现）无视该注入点，必须挂死到 timeout。
mklockro(){ sandbox_rm "$1"
            mkdir -p "$1/ro/var/.o2p.lock" "$1/app/shares/openp2p" "$1/logs"
            touch -d '10 minutes ago' "$1/ro/var/.o2p.lock" 2>/dev/null; }
run_ro(){  # $1=沙箱 $2=cmd 目录 $3=ticks；stdout 只回一行 rc=N
  unshare -rmn bash -c "
    mount --bind '$1/ro' '$1/ro' 2>/dev/null || exit 99
    mount -o remount,bind,ro '$1/ro' 2>/dev/null || exit 99
    [ -w '$1/ro' ] && exit 99
    export TRIM_APPNAME=openp2p OPENP2P_APPROOT='$1/app' TRIM_PKGVAR='$1/ro/var' \
           LOG_FILE='$1/logs/openp2p.log' O2P_LOCK_MAX_TICKS='$3'
    timeout 12 bash '$2/main' start >/dev/null 2>&1
    echo \"rc=\$?\"
  " 2>/dev/null | tail -1
}

if unshare -rmn true 2>/dev/null; then
  mklockro "$R/i4new"
  ts=$(date +%s); out=$(run_ro "$R/i4new" "$SRC/cmd" 10); el=$(( $(date +%s) - ts ))
  rc=${out#rc=}
  lines=$(wc -l < "$R/i4new/logs/openp2p.log" 2>/dev/null || echo 0)
  res "I4a 陈旧锁 + 只读目录下仍在 ${el} 秒内返回（rc=$rc，非 124 挂死）" \
      $([ "$rc" != 124 ] && [ "$rc" != 99 ] && [ "$el" -lt 8 ] && echo 1 || echo 0)
  res "I4b 返回码为 1（明确失败，不是假成功）" $([ "$rc" = 1 ] && echo 1 || echo 0)
  res "I4c 未退化成忙等（日志 ${lines} 行，要求 < 40）" $([ "$lines" -lt 40 ] && echo 1 || echo 0)
  grep -q '清理失败\|等待启动锁超时' "$R/i4new/logs/openp2p.log" 2>/dev/null \
    && res "I4d 日志交代了锁清理失败/超时" 1 \
    || res "I4d 日志交代了锁清理失败/超时（末行：$(tail -1 "$R/i4new/logs/openp2p.log" 2>/dev/null)）" 0

  # --- 对照组：-8 旧实现（应当忙等挂死到 timeout）---
  if [ -f "$OLD_CMD/main" ]; then
    mklockro "$R/i4old"
    ts=$(date +%s); out=$(run_ro "$R/i4old" "$OLD_CMD" 10); el=$(( $(date +%s) - ts ))
    orc=${out#rc=}
    if [ "$orc" = 124 ]; then
      echo "  [对照] 旧实现：${el} 秒未返回（rc=124 忙等挂死）→ 本用例有鉴别力"
    else
      echo "  [对照] ⚠️ 旧实现 rc=$orc 竟然也返回了（${el}s）—— 对照组无效，本块结论不成立"
      F=$((F+1))
    fi
  else
    echo "  [对照] 缺少旧实现快照，跳过"
  fi
else
  echo "  [skip] 本机 unshare -rmn 不可用 → I4 无法构造只读目录，跳过（不计入 PASS/FAIL）"
fi

########################################################################
say "I5 · 第七轮审计的非阻塞项加固（N5/N6/N7/N9/N10）"
########################################################################
# 对照组 = 冻结快照 legacy-9-cmd/（qa 第七轮已复核的 `-9` 实现，即加固前）。
if [ ! -f "$OLD9_CMD/common" ]; then
  echo "  [skip] 缺少 legacy-9-cmd/ 冻结快照 → I5 无法给出对照组，跳过（不计入 PASS/FAIL）"
else

# --- I5a【N5】$APPDIR 白名单过宽：shares/<app> 被指向 $APPDIR/target 时不许连安装目录一起删 ---
mkwide(){ sandbox_rm "$1"; mkdir -p "$1/app/shares" "$1/app/target" "$1/logs"
          printf 'payload\n' > "$1/app/target/keepme"
          ln -s "$1/app/target" "$1/app/shares/openp2p"; }
mkwide "$R/i5a-new"; run_uninstall "$SRC/cmd" "$R/i5a-new"
[ -f "$R/i5a-new/app/target/keepme" ] && res "I5a 指到 \$APPDIR/target 的数据目录被拒绝删除（安装目录未被误删）" 1 \
                                      || res "I5a 指到 \$APPDIR/target 的数据目录被拒绝删除 —— 安装目录被误删了！" 0
if [ -f "$OLD9_CMD/uninstall_callback" ]; then
  mkwide "$R/i5a-old"; run_uninstall "$OLD9_CMD" "$R/i5a-old"
  [ -f "$R/i5a-old/app/target/keepme" ] \
    && { echo "  [对照] ⚠️ -9 竟然也没删 —— 对照组无效"; F=$((F+1)); } \
    || echo "  [对照] -9：把整个 target/ 一起删了（白名单过宽）→ 本用例有鉴别力"
fi

# --- I5b【N6】$APPDIR 自身是符号链接时，删配置不许被"误判为拒绝" ---
mklinkroot(){ sandbox_rm "$1"; mkdir -p "$1/appreal/shares/openp2p" "$1/logs"
              printf '{"network":{"Token":271828}}\n' > "$1/appreal/shares/openp2p/config.json"
              ln -s "$1/appreal" "$1/app"; }
mklinkroot "$R/i5b-new"; run_uninstall "$SRC/cmd" "$R/i5b-new"
[ ! -e "$R/i5b-new/appreal/shares/openp2p/config.json" ] \
  && res "I5b \$APPDIR 是符号链接时仍能真删（规范化后命中白名单）" 1 \
  || res "I5b \$APPDIR 是符号链接时仍能真删 —— 误判为拒绝，删配置静默变保留" 0
if [ -f "$OLD9_CMD/uninstall_callback" ]; then
  mklinkroot "$R/i5b-old"; run_uninstall "$OLD9_CMD" "$R/i5b-old"
  [ -e "$R/i5b-old/appreal/shares/openp2p/config.json" ] \
    && echo "  [对照] -9：拒绝了删除（Token 留存）→ 本用例有鉴别力" \
    || { echo "  [对照] ⚠️ -9 也删掉了 —— 对照组无效"; F=$((F+1)); }
fi

# --- I5c【N7】config.json 是符号链接时，改写必须写进它指向的真实文件（不许把链接换成普通文件）---
mklinkconf(){ sandbox_rm "$1"; mkdir -p "$1/app/shares/openp2p" "$1/logs"
              printf '{"network":{"Token":111}}\n' > "$1/app/shares/openp2p/realconf.json"
              ln -s realconf.json "$1/app/shares/openp2p/config.json"; }
tok_write(){ # $1=cmd 目录 $2=沙箱 $3=token
  ( export TRIM_APPNAME=openp2p OPENP2P_APPROOT="$2/app" TRIM_PKGVAR="$2/app/var" LOG_FILE="$2/logs/openp2p.log"
    . "$1/common" >/dev/null 2>&1
    ensure_token_in_conf "$3" >/dev/null 2>&1 ) >/dev/null 2>&1
}
mklinkconf "$R/i5c-new"; tok_write "$SRC/cmd" "$R/i5c-new" 424242
if [ -L "$R/i5c-new/app/shares/openp2p/config.json" ] \
   && grep -q '"Token": 424242' "$R/i5c-new/app/shares/openp2p/realconf.json" 2>/dev/null; then
  res "I5c 符号链接 config.json：链接保留且 Token 写进了真实目标文件" 1
else
  res "I5c 符号链接 config.json：链接保留且 Token 写进了真实目标文件（链接还在=$([ -L "$R/i5c-new/app/shares/openp2p/config.json" ] && echo 是 || echo 否)，目标内容=$(cat "$R/i5c-new/app/shares/openp2p/realconf.json" 2>/dev/null)）" 0
fi
if [ -f "$OLD9_CMD/common" ]; then
  mklinkconf "$R/i5c-old"; tok_write "$OLD9_CMD" "$R/i5c-old" 424242
  if [ ! -L "$R/i5c-old/app/shares/openp2p/config.json" ] \
     && grep -qE '"Token"[[:space:]]*:[[:space:]]*111' "$R/i5c-old/app/shares/openp2p/realconf.json" 2>/dev/null; then
    echo "  [对照] -9：链接被换成普通文件、真实目标未被更新 → 本用例有鉴别力"
  else
    echo "  [对照] ⚠️ -9 的行为与本用例预期不符 → 对照组无效"; F=$((F+1))
  fi
fi

# --- I5d【N9】锁的属主进程还活着时，即使"超龄"也不许夺锁 ---
mklive(){ sandbox_rm "$1"; mkdir -p "$1/app/shares/openp2p" "$1/app/var/.o2p.lock" "$1/logs"
          sleep 30 & echo $! > "$1/livepid"
          echo "$(cat "$1/livepid")" > "$1/app/var/.o2p.lock/owner"
          touch -d '5 minutes ago' "$1/app/var/.o2p.lock" 2>/dev/null; }
lock_probe(){ # $1=cmd 目录 $2=沙箱；把 acquire_lock 的返回码写进 $2/rc.txt
  ( export TRIM_APPNAME=openp2p OPENP2P_APPROOT="$2/app" TRIM_PKGVAR="$2/app/var" \
           LOG_FILE="$2/logs/openp2p.log" O2P_LOCK_MAX_TICKS=6
    timeout 20 bash -c ". '$1/common' >/dev/null 2>&1; acquire_lock; echo \"rc=\$?\" > '$2/rc.txt'" ) >/dev/null 2>&1
}
mklive "$R/i5d-new"; lock_probe "$SRC/cmd" "$R/i5d-new"
if grep -q 'rc=1' "$R/i5d-new/rc.txt" 2>/dev/null && [ -d "$R/i5d-new/app/var/.o2p.lock" ]; then
  res "I5d 活进程持有的超龄锁不被夺走（等待超时 rc=1，锁仍在）" 1
else
  res "I5d 活进程持有的超龄锁不被夺走（$(cat "$R/i5d-new/rc.txt" 2>/dev/null)；锁存在=$([ -d "$R/i5d-new/app/var/.o2p.lock" ] && echo 是 || echo 否)）" 0
fi
kill "$(cat "$R/i5d-new/livepid" 2>/dev/null)" 2>/dev/null
if [ -f "$OLD9_CMD/common" ]; then
  mklive "$R/i5d-old"; lock_probe "$OLD9_CMD" "$R/i5d-old"
  # 注意：-9 夺锁后会立刻重新 mkdir 拿到锁，所以这里只看"是否抢到了"（rc=0），
  # 不看锁目录是否存在（抢到后它当然存在——那是 -9 自己持有的）。
  if grep -q 'rc=0' "$R/i5d-old/rc.txt" 2>/dev/null; then
    echo "  [对照] -9：夺走了活进程的锁（rc=0）→ 本用例有鉴别力"
  else
    echo "  [对照] ⚠️ -9 未夺锁（$(cat "$R/i5d-old/rc.txt" 2>/dev/null)）—— 对照组无效"; F=$((F+1))
  fi
  kill "$(cat "$R/i5d-old/livepid" 2>/dev/null)" 2>/dev/null
fi

# --- I5e【N10】锁路径被普通文件占用：要能自愈，而不是永久挡住 start/stop ---
mkfilelock(){ sandbox_rm "$1"; mkdir -p "$1/app/shares/openp2p" "$1/app/var" "$1/logs"
              : > "$1/app/var/.o2p.lock"; }
mkfilelock "$R/i5e-new"; lock_probe "$SRC/cmd" "$R/i5e-new"
if grep -q 'rc=0' "$R/i5e-new/rc.txt" 2>/dev/null && [ -d "$R/i5e-new/app/var/.o2p.lock" ]; then
  res "I5e 锁路径被普通文件占用时自动清理并成功取锁（不再永久挡住）" 1
else
  res "I5e 锁路径被普通文件占用时自动清理并成功取锁（$(cat "$R/i5e-new/rc.txt" 2>/dev/null)）" 0
fi
if [ -f "$OLD9_CMD/common" ]; then
  mkfilelock "$R/i5e-old"; lock_probe "$OLD9_CMD" "$R/i5e-old"
  if grep -q 'rc=1' "$R/i5e-old/rc.txt" 2>/dev/null && [ ! -d "$R/i5e-old/app/var/.o2p.lock" ]; then
    echo "  [对照] -9：快速失败且那个文件一直留着（start/stop 被永久挡住）→ 本用例有鉴别力"
  else
    echo "  [对照] ⚠️ -9 行为不合预期（$(cat "$R/i5e-old/rc.txt" 2>/dev/null)）—— 对照组无效"; F=$((F+1))
  fi
fi

fi   # /I5 前置条件

########################################################################
say "I6 · 第七轮 b 复验挖出的 N11–N14（读属主阻塞 / stderr 泄漏 / 注入点越界 / 链接逃逸）"
########################################################################
# 对照：legacy-10-cmd/ = `-10` 包内 cmd/（第七轮 b 已审、这四条修之前的实现）
OLD10_CMD="$(cd "$(dirname "$0")" && pwd)/legacy-10-cmd"

mklock(){ # $1=沙箱；建锁目录（**先别设陈旧时间**，见下面 mkstale 的注释）
  sandbox_rm "$1"; mkdir -p "$1/app/shares/openp2p" "$1/app/var/.o2p.lock" "$1/logs"
}
# 陈旧时间必须**最后**设置：往锁目录里放 owner 文件会把目录 mtime 刷成"现在"，
# 于是 `age > 60` 不成立、"陈旧锁"场景根本没构造出来（我第一次就踩了这个坑，
# 对照组因此假装"返回了"）。教训：构造时序也算实验条件，要写在断言旁。
mkstale(){ touch -d '10 minutes ago' "$1/app/var/.o2p.lock" 2>/dev/null; }
# 跑一次 acquire_lock：$1=沙箱 $2=cmd 目录 $3=ticks（可空）$4=timeout 秒
# 用「独立脚本 + timeout」而不是后台子 shell —— 后者会留下孤儿进程占着管道，
# 让外层命令看起来"卡住"（我自己先踩了一次，观测到的 rc 也是假的）。
run_acq(){
  cat > "$1/run.sh" <<RUNEOF
export TRIM_APPNAME=openp2p OPENP2P_APPROOT=$1/app TRIM_PKGVAR=$1/app/var LOG_FILE=$1/logs/openp2p.log
[ -n "$3" ] && export O2P_LOCK_MAX_TICKS="$3"
. "$2/common"
acquire_lock
echo "rc=\$?" > "$1/rc.txt"
RUNEOF
  timeout "${4:-8}" bash "$1/run.sh" >/dev/null 2>"$1/stderr.txt" </dev/null
  echo $?
}
stderr_bytes(){ stat -c%s "$1/stderr.txt" 2>/dev/null || echo 0; }

# --- N11：owner 是"读不到底"的东西（FIFO / 设备 / 符号链接）时，不许被拖死 ---
for kind in fifo symzero; do
  S="$R/i6a-$kind"; mklock "$S"
  if [ "$kind" = fifo ]; then mkfifo "$S/app/var/.o2p.lock/owner"
  else ln -s /dev/zero "$S/app/var/.o2p.lock/owner"; fi
  mkstale "$S"
  ts=$(date +%s); outer=$(run_acq "$S" "$SRC/cmd" 8 8); el=$(( $(date +%s) - ts ))
  got="$(cat "$S/rc.txt" 2>/dev/null)"
  res "I6a[$kind] owner 是 $kind 时未被拖死（${el}s，${got}，outer=${outer}）" \
      $([ "$outer" != 124 ] && [ -n "$got" ] && [ "$el" -lt 8 ] && echo 1 || echo 0)
done
if [ -f "$OLD10_CMD/common" ]; then
  S="$R/i6a-old"; mklock "$S"; mkfifo "$S/app/var/.o2p.lock/owner"; mkstale "$S"
  outer=$(run_acq "$S" "$OLD10_CMD" 8 8)
  if [ "$outer" = 124 ]; then
    echo "  [对照] -10：FIFO 属主下 8 秒仍未返回（rc=124 被拖死）→ 本用例有鉴别力"
  else
    echo "  [对照] ⚠️ -10 outer=$outer 竟然返回了 —— 对照组无效"; F=$((F+1))
  fi
fi

# --- N12：owner 文件不存在时不得往 stderr 吐字节 ---
S="$R/i6b"; mklock "$S"; mkstale "$S"; run_acq "$S" "$SRC/cmd" 8 8 >/dev/null
sb=$(stderr_bytes "$S")
res "I6b owner 缺失时 stderr 零泄漏（实测 ${sb} 字节）" $([ "$sb" = 0 ] && echo 1 || echo 0)
if [ -f "$OLD10_CMD/common" ]; then
  S="$R/i6b-old"; mklock "$S"; mkstale "$S"; run_acq "$S" "$OLD10_CMD" 8 8 >/dev/null
  ob=$(stderr_bytes "$S")
  if [ "$ob" != 0 ]; then
    echo "  [对照] -10：stderr 泄漏 ${ob} 字节（owner: No such file…）→ 本用例有鉴别力"
  else
    echo "  [对照] ⚠️ -10 也没泄漏 —— 对照组无效"; F=$((F+1))
  fi
fi

# --- N13：注入点被塞进超长数字时，超时判据不能失效（判据=重复打印的整数表达式错误） ---
# 场景：锁是**新鲜**的（不触发清理），于是循环只会走"计时 + sleep"这条路径 =>
#   旧实现：`[ "$waited" -ge 99999999999999999999 ]` 每 0.2 秒报一次
#           "integer expression expected"，判据形同不存在 → 永不返回且刷 stderr；
#   修复后：长度 >4 位直接回落 600（120 秒），stderr 干净。
# 这里用 4 秒窗口观察：修复版应"仍在等（124）且 stderr=0 字节"。
S="$R/i6c"; sandbox_rm "$S"; mkdir -p "$S/app/shares/openp2p" "$S/app/var/.o2p.lock" "$S/logs"
outer=$(run_acq "$S" "$SRC/cmd" 99999999999999999999 4)
sb=$(stderr_bytes "$S")
res "I6c 超长 O2P_LOCK_MAX_TICKS：判据未失效且 stderr 干净（outer=${outer}，stderr=${sb} 字节）" \
    $([ "$outer" = 124 ] && [ "$sb" = 0 ] && echo 1 || echo 0)
if [ -f "$OLD10_CMD/common" ]; then
  S="$R/i6c-old"; sandbox_rm "$S"; mkdir -p "$S/app/shares/openp2p" "$S/app/var/.o2p.lock" "$S/logs"
  outer=$(run_acq "$S" "$OLD10_CMD" 99999999999999999999 4)
  ob=$(stderr_bytes "$S")
  if [ "$ob" != 0 ]; then
    echo "  [对照] -10：同一场景 stderr 刷出 ${ob} 字节「integer expression expected」→ 判据失效（永不返回）"
  else
    echo "  [对照] ⚠️ -10 也没刷错 —— 对照组无效"; F=$((F+1))
  fi
fi

# --- N14：config.json 是指向数据目录之外的符号链接 → 拒绝改写，不许把 Token 写到外面 ---
mklinkout(){ # $1=沙箱
  sandbox_rm "$1"; mkdir -p "$1/app/shares/openp2p" "$1/logs" "$1/outside"
  printf '{"network":{"Token":111}}\n' > "$1/outside/target.json"
  ln -s "$1/outside/target.json" "$1/app/shares/openp2p/config.json"
}
tok_write(){ # $1=cmd 目录 $2=沙箱
  ( export TRIM_APPNAME=openp2p OPENP2P_APPROOT="$2/app" TRIM_PKGVAR="$2/app/var" \
           LOG_FILE="$2/logs/openp2p.log"
    . "$1/common" >/dev/null 2>&1
    ensure_token_in_conf 424242; echo "rc=$?" > "$2/rc.txt" ) >/dev/null 2>&1
}
mklinkout "$R/i6d"; tok_write "$SRC/cmd" "$R/i6d"
[ "$(cat "$R/i6d/rc.txt" 2>/dev/null)" = "rc=1" ] \
  && res "I6d 指向数据目录外的链接被拒绝（rc=1）" 1 \
  || res "I6d 指向数据目录外的链接被拒绝（rc=1；实测 $(cat "$R/i6d/rc.txt" 2>/dev/null)）" 0
grep -q '424242' "$R/i6d/outside/target.json" 2>/dev/null \
  && res "I6e 外部文件未被写入 Token" 0 || res "I6e 外部文件未被写入 Token" 1
# 数据目录内部的链接仍要正常工作（别把正常场景一起挡了）
sandbox_rm "$R/i6f"; mkdir -p "$R/i6f/app/shares/openp2p" "$R/i6f/logs"
printf '{"network":{"Token":111}}\n' > "$R/i6f/app/shares/openp2p/real.json"
ln -s real.json "$R/i6f/app/shares/openp2p/config.json"
tok_write "$SRC/cmd" "$R/i6f"
[ -L "$R/i6f/app/shares/openp2p/config.json" ] && grep -q '424242' "$R/i6f/app/shares/openp2p/real.json" 2>/dev/null \
  && res "I6f 数据目录内的链接仍照常写入（链接未脱、目标已更新）" 1 \
  || res "I6f 数据目录内的链接仍照常写入" 0
if [ -f "$OLD10_CMD/common" ]; then
  mklinkout "$R/i6d-old"; tok_write "$OLD10_CMD" "$R/i6d-old"
  if grep -q '424242' "$R/i6d-old/outside/target.json" 2>/dev/null; then
    echo "  [对照] -10：Token 被写进了数据目录之外的文件 → 本用例有鉴别力"
  else
    echo "  [对照] ⚠️ -10 也没写出去 —— 对照组无效"; F=$((F+1))
  fi
fi

########################################################################
echo
echo "=========== 块 I 结果：PASS=$P  FAIL=$F ==========="
[ "$F" -eq 0 ] || exit 1
exit 0
