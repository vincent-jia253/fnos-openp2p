#!/bin/bash
# 手工独立复现 H16：含 Token 的临时文件必须与进程 umask 无关地 0600
# 不依赖 exec-H.sh。用法：h16_manual.sh <common文件> <标签>
set -u
CM="$1"; TAG="$2"
R=/tmp/qa5/sbx/h16-$TAG
chmod -R u+rwX "$R" 2>/dev/null; rm -rf "$R"; mkdir -p "$R/shares/openp2p"
export TRIM_APPNAME=openp2p OPENP2P_APPROOT="$R"
unset TRIM_APPDEST TRIM_PKGVAR TRIM_TEMP_LOGFILE
export LOG_FILE="$R/apps.log"
(
  umask 000
  . "$CM" 2>/dev/null
  openp2p_token=987654321
  mv(){ return 1; }   # 逼进"原子改名失败"分支
  rm(){ return 1; }   # 不许清理现场
  apply_settings_env >/dev/null 2>&1
  echo "  TAG=$TAG  进程 umask=$(umask)"
)
T=$(find "$R" -name 'settings.conf.tmp.*' 2>/dev/null | head -1)
if [ -z "$T" ]; then
  echo "  TAG=$TAG  [前置不成立] 临时文件没留在磁盘上，无法判定创建时的权限"
  exit 2
fi
echo "  TAG=$TAG  残留临时文件: $T"
echo "  TAG=$TAG  权限 = $(stat -c '%a %A' "$T")  属主=$(stat -c '%U:%G' "$T")  大小=$(stat -c %s "$T")"
echo "  TAG=$TAG  内容首行: $(head -1 "$T")"
M=$(stat -c%a "$T")
if [ "$M" = 600 ]; then echo "  TAG=$TAG  => $M (0600，PASS)"; else echo "  TAG=$TAG  => $M (FAIL: 含 Token 明文在改名成功前过宽)"; fi
