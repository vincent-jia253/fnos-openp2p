#!/bin/bash
# 块 F：B8 死锁修复回归（真机发现的缺陷）
#   B8 = "无 Token 就不启动" 与 "界面提示可稍后填 Token" 互锁：
#        界面要等应用启动后才可用，而应用却在等 Token → 用户永远填不上。
# 被测对象：**源码树**（打包前先验，避免把 bug 打进包里）
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
R=/tmp/qaF; DATA="$R/shares/openp2p"; V="$R/var"
P=0; F=0
res(){ if [ "$2" = 1 ]; then P=$((P+1)); echo "  [PASS] $1"; else F=$((F+1)); echo "  [FAIL] $1"; fi; }
say(){ echo; echo "=========== $* ==========="; }

echo "被测源码: $SRC"
echo "包 md5  : $(md5sum $PKG | awk '{print $1}')（二进制来源）"

stage(){  # 铺一份"已安装"的目录树（用源码，不用包）
  # 卫生：清掉上例残留进程，避免进程计数被污染
  if ps -eo cmd | grep -F "$R/shares/openp2p/openp2p" | grep -v grep | grep -q .; then
    echo "  [harness] 清理上例残留进程"; pkill -x openp2p 2>/dev/null; sleep 1; fi
  rm -rf "$R"; mkdir -p "$R" "$V" "$R/target/bin" "$DATA"
  cp -r "$SRC"/cmd "$R/cmd"
  chmod +x "$R"/cmd/*
  # 部署真实二进制到 DATA_DIR（跳过架构部署，只测启动逻辑）
  tar xzf "$PKG" -O app.tgz | tar xz -C "$R/target" --wildcards 'bin/openp2p_x86_64' 2>/dev/null
  mv "$R/target/bin/openp2p_x86_64" "$DATA/openp2p"; chmod +x "$DATA/openp2p"
  : > "$R/apps.log"
  export OPENP2P_APPROOT="$R" TRIM_APPNAME=openp2p TRIM_APPDEST="$R/target" \
         TRIM_PKGVAR="$V" LOG_FILE="$R/apps.log" TRIM_TEMP_LOGFILE="$R/install.err"
}
run(){ bash "$R/cmd/main" "$@" >/dev/null 2>&1; echo $?; }
cleanup(){ bash "$R/cmd/main" stop >/dev/null 2>&1; }

say "F1 无任何配置（无 settings.conf / 无 config.json / 无 Token）→ 应仍能启动"
stage
RC=$(run start)
[ "$RC" = 0 ] && res "无 Token 时 start 返回 0（不再跳过）" 1 || res "无 Token 时 start rc=$RC（期望 0）" 0
ST=$(run status)
[ "$ST" = 0 ] && res "status = 0（运行中）" 1 || res "status = $ST（期望 0=运行中）" 0
pgrep -f "^$DATA/openp2p" >/dev/null && res "进程真实存在" 1 || res "无进程" 0
grep -q '尚未配置 Token' "$R/apps.log" && res "日志给出『尚未配置 Token』提示" 1 || res "日志缺提示" 0
cleanup

say "F2 清空 Token（settings.conf 空白 + config.json 遗留旧 Token）→ 旧值不得复活"
stage
printf '{"network":{"Node":"old","Token":987654321,"ServerHost":"api.openp2p.cn"}}\n' > "$DATA/config.json"
printf 'token=\nnode=\nsharebandwidth=10\nserverhost=api.openp2p.cn\nserverport=27183\nloglevel=1\n' > "$DATA/settings.conf"
RC=$(run start)
[ "$RC" = 0 ] && res "清空 Token 后仍能启动（rc=0）" 1 || res "rc=$RC" 0
grep -qE '"Token":[[:space:]]*0([^0-9]|$)' "$DATA/config.json" && res "config.json 旧 Token 已被清零为 0（B2 保护保留）" 1 || res "旧 Token 仍存在：$(grep -o '\"Token\"[^,}]*' "$DATA/config.json")" 0
grep -q '987654321' "$DATA/config.json" && res "旧 Token 明文仍在（危险）" 0 || res "旧 Token 未残留在 config.json" 1
cleanup

say "F3 有 Token → 写入格式必须是【不带引号的数字】"
stage
printf 'token=123456789\nnode=my-nas\nsharebandwidth=10\nserverhost=api.openp2p.cn\nserverport=27183\nloglevel=1\n' > "$DATA/settings.conf"
RC=$(run start)
[ "$RC" = 0 ] && res "有 Token 时启动成功" 1 || res "rc=$RC" 0
grep -qE '"Token":[[:space:]]*123456789([^0-9]|$)' "$DATA/config.json" && res "Token 以数字形式写入（openp2p 可解析）" 1 || res "Token 写入格式错误：$(grep -o '\"Token\"[^,}]*' "$DATA/config.json")" 0
grep -qE '"Token":[[:space:]]*"' "$DATA/config.json" && res "Token 被写成带引号字符串（会被解析成 0）" 0 || res "Token 未加引号" 1
grep -q '123456789' "$R/apps.log" && res "Token 明文出现在日志（禁止）" 0 || res "日志无 Token 明文" 1
cleanup

say "F4 config_callback：应用未运行时也应自动拉起"
stage
printf 'token=123456789\nnode=my-nas\nsharebandwidth=10\nserverhost=api.openp2p.cn\nserverport=27183\nloglevel=1\n' > "$DATA/settings.conf"
bash "$R/cmd/config_callback" >/dev/null 2>&1
sleep 1
pgrep -f "^$DATA/openp2p" >/dev/null && res "保存设置后应用被自动拉起" 1 || res "保存设置后仍无进程" 0
grep -q '未运行，尝试启动' "$R/apps.log" && res "日志记录『未运行，尝试启动』" 1 || res "日志缺记录" 0
cleanup

say "F5 幂等：已运行再 start 不得起第二个进程"
stage
printf 'token=123456789\nnode=my-nas\nsharebandwidth=10\nserverhost=api.openp2p.cn\nserverport=27183\nloglevel=1\n' > "$DATA/settings.conf"
run start >/dev/null; run start >/dev/null
N=$(pgrep -f "^$DATA/openp2p" | wc -l)
[ "$N" = 1 ] && res "重复 start 仍只有 1 个进程" 1 || res "进程数=$N" 0
cleanup

say "F6 stop 后 status 必须为 3（未运行）"
ST=$(run status)
[ "$ST" = 3 ] && res "status = 3" 1 || res "status = $ST（期望 3）" 0
pgrep -f "^$DATA/openp2p" >/dev/null && res "stop 后仍有残留进程" 0 || res "无残留进程" 1

echo
echo "=========== 块 F 汇总 ==========="
echo "PASS=$P FAIL=$F"