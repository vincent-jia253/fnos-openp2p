#!/bin/bash
# 第 5 轮补充实测：半装状态（settings.conf 缺失/未写入）下用户点「启动」会发生什么？
#   A) 无 config.json（全新安装失败后的状态）
#   B) 有 config.json（从旧版升级失败后的状态，含旧 Token）
set -u
WS=/path/to
PKG="$WS/projects/fnos-openp2p/dist/openp2p_3.25.11-7_all.fpk"
CMDSRC="$WS/projects/fnos-openp2p/src/openp2p/cmd"
for MODE in A B; do
  R=/tmp/qa5/half-$MODE
  chmod -R u+rwX "$R" 2>/dev/null; rm -rf "$R"
  D="$R/shares/openp2p"
  mkdir -p "$D" "$R/var" "$R/target/bin"
  cp -r "$CMDSRC/." "$R/cmd/"; chmod +x "$R"/cmd/* 2>/dev/null
  tar xzf "$PKG" -O app.tgz | tar xz -C "$R/target" --wildcards 'bin/openp2p_x86_64' 2>/dev/null
  mv "$R/target/bin/openp2p_x86_64" "$D/openp2p"; chmod +x "$D/openp2p"
  export TRIM_APPNAME=openp2p OPENP2P_APPROOT="$R" TRIM_APPDEST="$R/target" TRIM_PKGVAR="$R/var"
  export LOG_FILE="$R/apps.log" TRIM_TEMP_LOGFILE="$R/install.err"
  echo "================ 场景 $MODE（settings.conf 不存在$( [ "$MODE" = B ] && echo '，但 config.json 里有旧 Token' )）================"
  if [ "$MODE" = B ]; then
    printf '{"network":{"Token":314159265358,"Node":"nas-old"}}\n' > "$D/config.json"; chmod 600 "$D/config.json"
    echo "  预置 config.json（旧 Token=314159265358），权限=$(stat -c %a "$D/config.json")"
  fi
  echo "  SETTINGS 存在? $([ -f "$D/settings.conf" ] && echo yes || echo no)   DATA_DIR=$D"
  : > "$R/apps.log"; : > "$R/install.err"
  bash "$R/cmd/main" start >"$R/start.stdout" 2>&1; rc=$?
  sleep 3
  PID=$(head -n1 "$R/var/app.pid" 2>/dev/null | tr -d '[:space:]')
  echo "  main start rc=$rc    pid=${PID:-<无>}   进程存活=$([ -n "$PID" ] && [ -d /proc/$PID ] && echo yes || echo no)"
  bash "$R/cmd/main" status >"$R/status.stdout" 2>&1; src=$?
  echo "  main status rc=$src（0=运行中 3=未运行）输出：$(cat "$R/status.stdout")"
  echo "  ---- apps.log 关键行 ----"
  grep -n 'Token\|启动\|运行\|设置' "$R/apps.log" 2>/dev/null | sed 's/^/    /'
  echo "  ---- 实际交付给 openp2p 的 argv ----"
  ps -ww -o pid=,args= -p "${PID:-1}" 2>/dev/null | sed 's/^/    /'
  echo "  ---- config.json 内容（Token 是否被保住/写入） ----"
  cat "$D/config.json" 2>/dev/null | sed 's/^/    /'
  bash "$R/cmd/main" stop >/dev/null 2>&1
  pkill -f "^$D/openp2p" 2>/dev/null
  chmod -R u+rwX "$R" 2>/dev/null; rm -rf "$R"
  echo
done
