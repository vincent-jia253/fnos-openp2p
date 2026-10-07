#!/bin/bash
# 手工独立复现 H17：日志轮转必须沿用原文件权限
# 用法：h17_manual.sh <common文件> <标签>
set -u
CM="$1"; TAG="$2"
R=/tmp/qa5/sbx/h17-$TAG
chmod -R u+rwX "$R" 2>/dev/null; rm -rf "$R"; mkdir -p "$R"
export TRIM_APPNAME=openp2p OPENP2P_APPROOT="$R"
unset TRIM_APPDEST TRIM_PKGVAR TRIM_TEMP_LOGFILE
LF="$R/apps.log"
head -c 6000000 /dev/zero | tr '\0' 'x' > "$LF"
chmod 600 "$LF"
echo "  TAG=$TAG  轮转前: $(stat -c '%a %s bytes' "$LF")"
(
  umask 000
  LOG_FILE="$LF"
  . "$CM" 2>/dev/null
  rotate_log >/dev/null 2>&1
  echo "  TAG=$TAG  进程 umask=$(umask)"
)
echo "  TAG=$TAG  轮转后: $(stat -c '%a %s bytes' "$LF")"
if [ -e "${LF}.tmp" ]; then echo "  TAG=$TAG  [警告] 残留 ${LF}.tmp 权限=$(stat -c%a "${LF}.tmp")"; else echo "  TAG=$TAG  无 .tmp 残留"; fi
M=$(stat -c%a "$LF")
if [ "$M" = 600 ]; then echo "  TAG=$TAG  => $M (沿用原 600，PASS)"; else echo "  TAG=$TAG  => $M (FAIL: 原 600 被放宽)"; fi
