#!/bin/bash
# 块 C2：TC-23 ~ TC-26（越界值回退、命令注入、脏 pid 保护、包结构）
PKG=/vol4/@appshare/octop-native/data/.octop/agents/ZD3XW7/projects/fnos-openp2p/dist/openp2p_3.25.11-8_all.fpk
R=/tmp/qac2; DATA="$R/shares/openp2p"; V="$R/var"
P=0; F=0
res(){ if [ "$2" = 1 ]; then P=$((P+1)); echo "  [PASS] $1"; else F=$((F+1)); echo "  [FAIL] $1"; fi; }
prep(){ # 卫生：rm -rf 会连 PID 文件一起删，若有上例残留进程就会变成孤儿并污染断言 → 先报告并清理
  if ps -eo pid,cmd | grep -F "$DATA/openp2p" | grep -v grep | grep -q .; then
    echo "  [harness] 清理上例残留进程"; pkill -x openp2p 2>/dev/null; sleep 1; fi
  rm -rf "$R"; mkdir -p "$R" "$V" "$R/target" "$DATA"
  tar xzf "$PKG" -C "$R"; tar xzf "$R/app.tgz" -C "$R/target"; : > "$R/apps.log"
  export OPENP2P_APPROOT="$R" TRIM_APPNAME=openp2p TRIM_APPDEST="$R/target" TRIM_PKGVAR="$V" LOG_FILE="$R/apps.log" TRIM_TEMP_LOGFILE="$R/install.err"
  bash "$R/cmd/install_callback" >/dev/null 2>&1; }

echo "=========== TC-23 越界值被拒绝并回退默认 (校验契约) ==========="
prep
OPENP2P_SHAREBANDWIDTH=x bash "$R/cmd/config_callback" >/dev/null 2>&1
openp2p_sharebandwidth=100001 bash "$R/cmd/config_callback" >/dev/null 2>&1
echo "  sharebandwidth => $(grep '^sharebandwidth' $DATA/settings.conf)"
grep -q '^sharebandwidth=10$' "$DATA/settings.conf" && res "sharebandwidth 100001 回退为 10" 1 || res "sharebandwidth 未回退" 0
openp2p_serverport=0 bash "$R/cmd/config_callback" >/dev/null 2>&1
grep -q '^serverport=27183$' "$DATA/settings.conf" && res "serverport 0 回退为 27183" 1 || res "serverport 0 未回退" 0
openp2p_serverport=65536 bash "$R/cmd/config_callback" >/dev/null 2>&1
grep -q '^serverport=27183$' "$DATA/settings.conf" && res "serverport 65536 回退为 27183" 1 || res "serverport 65536 未回退" 0
openp2p_loglevel=9 bash "$R/cmd/config_callback" >/dev/null 2>&1
grep -q '^loglevel=1$' "$DATA/settings.conf" && res "loglevel 9 回退为 1" 1 || res "loglevel 9 未回退" 0
grep -q '共享带宽上限须为' "$R/apps.log" && res "带宽拒绝有提示" 1 || res "带宽拒绝无提示" 0
grep -q '服务端端口须为' "$R/apps.log" && res "端口拒绝有提示" 1 || res "端口拒绝无提示" 0

echo "=========== TC-24 命令注入无效 (校验契约,I5) ==========="
prep
rm -f /tmp/qa-pwned /tmp/qa-pwned2 /tmp/qa-pwned3; touch /tmp/qa-marker; M1=$(md5sum /tmp/qa-marker | awk '{print $1}')
openp2p_token='12345678; rm -rf /tmp/qa-marker' bash "$R/cmd/config_callback" >/dev/null 2>&1
openp2p_node='$(touch /tmp/qa-pwned)' bash "$R/cmd/config_callback" >/dev/null 2>&1
openp2p_serverhost='api.openp2p.cn`touch /tmp/qa-pwned2`' bash "$R/cmd/config_callback" >/dev/null 2>&1
openp2p_node='x; touch /tmp/qa-pwned3' bash "$R/cmd/config_callback" >/dev/null 2>&1
[ -f /tmp/qa-marker ] && [ "$(md5sum /tmp/qa-marker | awk '{print $1}')" = "$M1" ] && res "rm -rf 未被执行（marker 完好）" 1 || res "标记文件被删 → 注入成功" 0
[ ! -f /tmp/qa-pwned ] && res "\$( ) 未被求值" 1 || res "反引号/\$() 被求值 → 注入成功" 0
[ ! -f /tmp/qa-pwned2 ] && res "反引号未被求值" 1 || res "反引号被求值 → 注入成功" 0
[ ! -f /tmp/qa-pwned3 ] && res "分号注入未生效" 1 || res "分号注入生效" 0
grep -q '^serverhost=api.openp2p.cn$' "$DATA/settings.conf" && res "注入型 serverhost 已回退默认" 1 || res "serverhost 未回退" 0
grep -q 'qa-pwned' "$DATA/settings.conf" && res "注入串未写入配置" 0 || res "注入串未写入配置" 1

echo "=========== TC-25 脏 pid 不误判、不误杀 (R1,R7,CLI) ==========="
prep
echo 999999 > "$V/app.pid"
bash "$R/cmd/main" status; RC=$?
[ "$RC" = 3 ] && res "指向不存在进程的脏 pid → status=3" 1 || res "脏 pid 被判为运行中（status=$RC）" 0
bash "$R/cmd/main" stop >/dev/null 2>&1; RC=$?
[ "$RC" = 0 ] && res "脏 pid 下 stop rc=0" 1 || res "脏 pid 下 stop rc=$RC" 0
# 关键：pid 文件指向一个【无关的存活进程】，stop 绝不能杀它
sleep 300 & UNREL=$!
# 先测 stop：此时 pid 文件指向无关存活进程，stop 必须跳过 kill 并留痕
echo "$UNREL" > "$V/app.pid"
bash "$R/cmd/main" stop >/dev/null 2>&1
kill -0 "$UNREL" 2>/dev/null && res "无关进程未被误杀（PID 复用保护生效）" 1 || res "无关进程被 kill → 严重缺陷" 0
grep -q '不是本应用进程' "$R/apps.log" && res "日志记录了跳过 kill" 1 || res "无跳过 kill 记录" 0
# 再测 status：指向无关存活进程时不得误判为运行中
echo "$UNREL" > "$V/app.pid"
bash "$R/cmd/main" status; RC=$?
[ "$RC" = 3 ] && res "指向无关存活进程 → status=3（不误判）" 1 || res "误判为运行中（status=$RC）" 0
kill -9 "$UNREL" 2>/dev/null
echo "token=12345678" > "$DATA/settings.conf"
bash "$R/cmd/main" start >/dev/null 2>&1; sleep 3; RC=$?
[ "$RC" = 0 ] && res "脏 pid 后 start rc=0" 1 || res "脏 pid 后 start rc=$RC" 0
[ "$(cat "$V/app.pid")" != "999999" ] && [ "$(cat "$V/app.pid")" != "$UNREL" ] && res "app.pid 已重写为真实新 PID" 1 || res "app.pid 未重写" 0
[ "$(pgrep -c -f "$DATA/openp2p" || true)" = "1" ] && res "进程数=1" 1 || res "进程数异常" 0
bash "$R/cmd/main" stop >/dev/null 2>&1

echo "=========== TC-26 包结构契约 (包结构,R5) ==========="
T=$(mktemp -d); tar xzf "$PKG" -C "$T"
for f in manifest ICON.PNG ICON_256.PNG config/privilege config/resource app.tgz \
         cmd/main cmd/common cmd/install_init cmd/install_callback cmd/upgrade_init cmd/upgrade_callback \
         cmd/uninstall_init cmd/uninstall_callback cmd/config_init cmd/config_callback \
         wizard/install wizard/config wizard/uninstall; do
  [ -e "$T/$f" ] || { F=$((F+1)); echo "  [FAIL] 缺少 $f"; }
done
[ -e "$T/manifest" ] && [ -e "$T/app.tgz" ] && res "包内必备文件齐全（含 cmd 10 脚本 / wizard 3 文件）" 1 || res "包内文件缺失" 0
MC=$(grep '^checksum' "$T/manifest" | awk '{print $3}'); AC=$(md5sum "$T/app.tgz" | awk '{print $1}')
[ "$MC" = "$AC" ] && res "manifest.checksum == md5(app.tgz)" 1 || res "checksum 不匹配（$MC vs $AC）" 0
IF=$(file -b "$T/ICON.PNG" | grep -o '[0-9]* x [0-9]*'); I2=$(file -b "$T/ICON_256.PNG" | grep -o '[0-9]* x [0-9]*')
[ "$IF" = "64 x 64" ] && res "ICON.PNG 为 64x64" 1 || res "ICON.PNG 尺寸=$IF（应 64x64）" 0
[ "$I2" = "256 x 256" ] && res "ICON_256.PNG 为 256x256" 1 || res "ICON_256.PNG 尺寸=$I2" 0
S1=$(stat -c%s "$T/ICON.PNG"); S2=$(stat -c%s "$T/ICON_256.PNG")
[ "$S1" -le 1048576 ] && [ "$S2" -le 1048576 ] && res "两个图标均 ≤1024KB" 1 || res "图标超过 1024KB" 0
A=$(mktemp -d); tar xzf "$T/app.tgz" -C "$A"
NA=0
for b in x86_64 aarch64 armv7 i386; do [ -s "$A/bin/openp2p_$b" ] || NA=$((NA+1)); done
[ "$NA" = 0 ] && res "app.tgz 内 4 架构二进制齐备且非空" 1 || res "缺 ${NA} 个架构二进制" 0
for b in x86_64 aarch64 armv7 i386; do
  printf '   %-9s %s\n' "$b" "$(file -b "$A/bin/openp2p_$b")"
done
rm -rf "$T" "$A"

echo
echo "=========== 块 C2 汇总：PASS=$P  FAIL=$F ==========="
