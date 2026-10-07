#!/bin/bash
# 独立探针：ensure_token_in_conf 冷启动分支是否"先以进程 umask 创建、后 chmod"
set -u
R=/tmp/qa5/sbx/conf-win
chmod -R u+rwX "$R" 2>/dev/null; rm -rf "$R"; mkdir -p "$R/shares/openp2p"
export TRIM_APPNAME=openp2p OPENP2P_APPROOT="$R" TRIM_APPDEST="$R/target" TRIM_PKGVAR="$R/var"
export LOG_FILE="$R/apps.log"
unset TRIM_TEMP_LOGFILE
. /vol4/@appshare/octop-native/data/.octop/agents/ZD3XW7/projects/fnos-openp2p/src/openp2p/cmd/common
echo "被测 CONF=$CONF"
(
  umask 000
  # 探针 1：在 chmod 被调用的那一刻看文件权限（$1=mode $2=file）
  chmod(){ echo "  [probe1] 即将 chmod $1 到 $2，此刻该文件权限 = $(command stat -c%a "$2" 2>/dev/null)"; command chmod "$@"; }
  ensure_token_in_conf 314159265358; echo "  ensure_token_in_conf rc=$?"
  command rm -f "$CONF"
  # 探针 2：把 chmod 变成空操作（模拟 chmod 失败 / 进程在 chmod 前被杀）
  chmod(){ echo "  [probe2] chmod 被吞掉（模拟 chmod 未生效）"; }
  ensure_token_in_conf 314159265358; echo "  rc=$?"
  echo "  最终 config.json 权限 = $(command stat -c%a "$CONF"), 内容 = $(command cat "$CONF")"
)
