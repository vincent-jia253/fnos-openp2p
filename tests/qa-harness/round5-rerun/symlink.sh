#!/bin/bash
# 符号链接数据目录沙箱（真机形态：/var/apps/openp2p/shares/openp2p → /vol4/@appshare/openp2p）
# 关键点：两层落在**不同的文件系统**上（/ 与 /vol4），用来验证 tmp + mv 原子改名是否仍工作。
set -u
WS=/vol4/@appshare/octop-native/data/.octop/agents/ZD3XW7
SRC="$WS/projects/fnos-openp2p/src/openp2p"
PKG="$WS/projects/fnos-openp2p/dist/openp2p_3.25.11-7_all.fpk"
APP=/tmp/qa5/sbx/sym/app                       # 模拟 /var/apps/openp2p（在 / 上）
REAL=/vol4/@appshare/octop-native/qa5-sym-real # 模拟 /vol4/@appshare/openp2p（在 /vol4 上）
chmod -R u+rwX /tmp/qa5/sbx/sym "$REAL" 2>/dev/null; rm -rf /tmp/qa5/sbx/sym "$REAL"
mkdir -p "$APP/shares" "$REAL" "$APP/var" "$APP/target/bin" "$APP/cmd" "$APP/ui"
ln -s "$REAL" "$APP/shares/openp2p"
echo "== 布局 =="
echo "  $APP/shares/openp2p -> $(readlink "$APP/shares/openp2p")"
echo "  device(/)     = $(stat -c %d "$APP/shares")"
echo "  device(/vol4) = $(stat -c %d "$REAL")"
[ "$(stat -c %d "$APP/shares")" != "$(stat -c %d "$REAL")" ] && echo "  => 确实跨文件系统（与真机同形）" || echo "  => 同一文件系统（沙箱与真机不同形，结论要打折）"

export TRIM_APPNAME=openp2p OPENP2P_APPROOT="$APP" TRIM_APPDEST="$APP/target" TRIM_PKGVAR="$APP/var"
export LOG_FILE="$APP/apps.log" TRIM_TEMP_LOGFILE="$APP/install.err"

echo
echo "== T1 apply_settings_env（冷启动，经符号链接路径）=="
(
  umask 022     # 真机 root 的典型 umask
  . "$SRC/cmd/common"
  echo "  DATA_DIR=$DATA_DIR  SETTINGS=$SETTINGS"
  openp2p_token=123456789 openp2p_node=nas-01 openp2p_sharebandwidth=20
  # 探针 mv：打印 tmp 与目标的所在设备号，证明改名是"同设备 rename"（原子）而非跨设备拷贝
  mv(){
    local t="$2" g="$3" d1 d2
    d1=$(readlink -f "$(dirname "$t")"); d2=$(readlink -f "$(dirname "$g")")
    echo "  [probe mv] tmp=$t  tmp存在=$([ -e "$t" ] && echo yes || echo no)"
    echo "  [probe mv] 真实目录(tmp)=$d1 dev=$(stat -Lc %d "$d1")   真实目录(target)=$d2 dev=$(stat -Lc %d "$d2")  同一目录=$([ "$d1" = "$d2" ] && echo YES || echo NO)"
    echo "  [probe mv] target(经符号链接)存在性=$([ -e "$g" ] && echo yes || echo no)"
    command mv "$@"
  }
  apply_settings_env; echo "  apply_settings_env rc=$?"
)
echo "  实际落地：$(ls -l "$REAL/settings.conf" 2>&1)"
echo "  经符号链接可见：$(ls -l "$APP/shares/openp2p/settings.conf" 2>&1)"
echo "  残留 .tmp：$(ls -A "$REAL" | grep -c 'settings.conf.tmp')"

echo
echo "== T2 ui/index.cgi save（经符号链接）=="
cp -r "$SRC/cmd" "$APP/cmd"; chmod +x "$APP"/cmd/*
sed "s|/var/apps/openp2p|$APP|g" "$SRC/app/ui/index.cgi" > "$APP/ui/index.cgi"; chmod +x "$APP/ui/index.cgi"
# 铺一份真实二进制，供"运行中保存并自动重启"路径使用
tar xzf "$PKG" -O app.tgz | tar xz -C "$APP/target" --wildcards 'bin/openp2p_x86_64' 2>/dev/null
mv "$APP/target/bin/openp2p_x86_64" "$REAL/openp2p"; chmod +x "$REAL/openp2p"
: > "$APP/apps.log"
B='action=save&token=987654321&node=nas-02'
printf '%s' "$B" | CONTENT_LENGTH=${#B} REQUEST_METHOD=POST bash "$APP/ui/index.cgi" > "$APP/t2.out" 2>"$APP/t2.err"
echo "  stderr=$(wc -c <"$APP/t2.err") 字节"
echo "  文案: $(grep -oE '[✅❌⚠️🛑][^<]*' "$APP/t2.out" | head -1)"
echo "  settings.conf: $(stat -c '%a %s bytes' "$REAL/settings.conf")  token=$(sed -n 's/^token=//p' "$REAL/settings.conf")"
echo "  残留 .tmp：$(ls -A "$REAL" | grep -c 'settings.conf.tmp')"

echo
echo "== T3 ui/index.cgi raw_save（经符号链接）=="
C='action=raw_save&rawjson=%7B%22network%22%3A%7B%22Token%22%3A555%7D%7D'
printf '%s' "$C" | CONTENT_LENGTH=${#C} REQUEST_METHOD=POST bash "$APP/ui/index.cgi" > "$APP/t3.out" 2>"$APP/t3.err"
echo "  stderr=$(wc -c <"$APP/t3.err") 字节"
echo "  文案: $(grep -oE '[✅❌⚠️🛑][^<]*' "$APP/t3.out" | head -1)"
echo "  config.json: $(stat -c '%a %s bytes' "$REAL/config.json")  内容=$(cat "$REAL/config.json")"
echo "  残留 .tmp：$(ls -A "$REAL" | grep -c 'config.json.tmp')"

echo
echo "== T4 通过符号链接启动/判活（B11 现场）=="
( . "$SRC/cmd/common"; DATA_DIR="$APP/shares/openp2p"; BIN="$DATA_DIR/openp2p"
  settings_ok=1
  nohup "$BIN" -node nas-01 -sharebandwidth 10 -serverhost api.openp2p.cn -serverport 27183 \
        -loglevel 1 -installpath "$DATA_DIR" >> "$APP/apps.log" 2>&1 < /dev/null &
  P=$!; sleep 2
  echo "  pid=$P  exe=$(readlink /proc/$P/exe 2>/dev/null)"
  if is_our_pid "$P"; then echo "  is_our_pid(经符号链接) → TRUE"; else echo "  is_our_pid(经符号链接) → FALSE"; fi
  kill $P 2>/dev/null )
echo
echo "== 清理 =="
chmod -R u+rwX /tmp/qa5/sbx/sym "$REAL" 2>/dev/null; rm -rf /tmp/qa5/sbx/sym "$REAL"
ls -d "$REAL" 2>&1
