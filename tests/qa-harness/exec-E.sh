#!/bin/bash
# 块 E：B6（armv8l 架构映射）动态验证 + 四架构真二进制佐证
# 设计要点：B6 的缺陷本体是 fix_binary_arch「选错文件」。
#   自检 `$cand -v` 在 x86_64 宿主上无法 exec 真实 armv7 ELF（环境假象，非产品缺陷），
#   故用「脚本桩」隔离"架构选择"逻辑做动态验证；真二进制可运行性由 E2 单独佐证。
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
Q=/tmp/qemuget/x/usr/bin
R=/tmp/qae; DATA="$R/shares/openp2p"; V="$R/var"; MB="$R/mockbin"
P=0; F=0
res(){ if [ "$2" = 1 ]; then P=$((P+1)); echo "  [PASS] $1"; else F=$((F+1)); echo "  [FAIL] $1"; fi; }

echo "=========== 证据绑定（T5）==========="
echo "被测包: $PKG"
echo "包 md5 : $(md5sum "$PKG" | awk '{print $1}')"
echo "执行时间: $(date '+%F %T')"

# 注意顺序：必须先清空 $R，再建 mock（$MB 位于 $R 之内），否则 mock 会被一起删掉
rm -rf "$R"; mkdir -p "$R" "$V"

# uname mock（走 PATH，非绝对路径；src 中无 PATH= 覆写，故 shim 有效）
mkdir -p "$MB"; printf '#!/bin/sh\n[ "$1" = "-m" ] && { echo "${MOCK_UNAME:-x86_64}"; exit 0; }\nexec /usr/bin/uname "$@"\n' > "$MB/uname"; chmod +x "$MB/uname"
echo "  mock 自检: $(MOCK_UNAME=armv8l PATH="$MB:$PATH" uname -m) (期望 armv8l)"

tar xzf "$PKG" -C "$R" || { echo "解包失败"; exit 1; }
: > "$R/apps.log"
export OPENP2P_APPROOT="$R" TRIM_APPNAME=openp2p TRIM_APPDEST="$R/target" TRIM_PKGVAR="$V" \
       LOG_FILE="$R/apps.log" TRIM_TEMP_LOGFILE="$R/install.err"

stage_stub(){ rm -rf "$R/target"; mkdir -p "$R/target/bin"
  for a in x86_64 i386 aarch64 armv7; do
    printf '#!/bin/sh\necho "9.9.9-%s"\n' "$a" > "$R/target/bin/openp2p_$a"
    chmod +x "$R/target/bin/openp2p_$a"; done; }

echo
echo "=========== TC-08d 架构映射动态验证（B6 · 脚本桩隔离）==========="
echo "  断言：fix_binary_arch 依据 mock 的 uname -m 选中正确架构文件"
case_m(){ local m="$1" exp="$2"
  rm -rf "$DATA" "$V"; mkdir -p "$DATA" "$V"; stage_stub; : > "$R/apps.log"
  MOCK_UNAME="$m" PATH="$MB:$PATH" bash "$R/cmd/install_callback" >/dev/null 2>&1; local rc=$?
  if [ -z "$exp" ]; then
    [ $rc -eq 1 ] && res "uname=$m → 正确拒绝(rc=1) 并提示不支持" 1 || res "uname=$m → 期望拒绝，实际 rc=$rc" 0
    grep -q '不支持的系统架构' "$R/apps.log" && res "uname=$m → 日志含『不支持的系统架构』" 1 || res "uname=$m → 缺明确提示" 0
    return; fi
  grep -q "9\.9\.9-$exp" "$DATA/openp2p" 2>/dev/null \
    && res "uname=$m → 选中 $exp" 1 || res "uname=$m → 未选中 $exp（rc=$rc，落盘=$(cat "$DATA/openp2p" 2>/dev/null | tail -1)）" 0; }

case_m armv8l  armv7
case_m armv7hl armv7
case_m armv7a  armv7
case_m armv7l  armv7
case_m armv6l  armv7
case_m aarch64 aarch64
case_m arm64   aarch64
case_m amd64   x86_64
case_m x86_64  x86_64
case_m i686    i386
case_m i386    i386
case_m riscv64 ""      # 未支持架构须拒绝，不得静默选错

echo
echo "  —— B6 专项：armv8l 命中与日志留痕 ——"
rm -rf "$DATA" "$V"; mkdir -p "$DATA" "$V"; stage_stub; : > "$R/apps.log"
MOCK_UNAME=armv8l PATH="$MB:$PATH" bash "$R/cmd/install_callback" >/dev/null 2>&1
grep -q '架构 armv7' "$R/apps.log" && res "B6: armv8l 设备日志记录『架构 armv7』" 1 || res "B6: 日志未记录架构 armv7" 0
[ "$(stat -c '%a' "$DATA/openp2p")" = "755" ] && res "B6: 落盘二进制可执行权限 755" 1 || res "B6: 权限异常 $(stat -c '%a' "$DATA/openp2p")" 0

echo
echo "=========== TC-08e 真二进制佐证（armv8l 实收哪份文件）==========="
R2=/tmp/qae-real; rm -rf "$R2"; mkdir -p "$R2"
tar xzf "$PKG" -C "$R2"; tar xzf "$R2/app.tgz" -C "$R2"
[ -f "$R2/bin/openp2p_armv7" ] && res "包内存在 openp2p_armv7（armv8l 实收文件）" 1 || res "包内缺 openp2p_armv7" 0
echo "  openp2p_armv7 md5（= armv8l 设备将收到的文件）: $(md5sum "$R2/bin/openp2p_armv7" | awk '{print $1}')"
OUT=$(chmod +x "$R2/bin/openp2p_armv7" 2>/dev/null; $Q/qemu-arm-static "$R2/bin/openp2p_armv7" -v 2>&1 | head -1)
[ "$OUT" = "3.25.11" ] && res "armv8l 实收的 openp2p_armv7 可执行且版本 3.25.11（qemu 实测）" 1 || res "openp2p_armv7 执行异常：$OUT" 0

echo
echo "=========== TC-08f 错架构候选被自检拒绝（补 T1 静默跳过）==========="
echo "  构造：宿主 mock 为 x86_64，但包内 openp2p_x86_64 实际是 aarch64 真实 ELF"
R3=/tmp/qae-wrong; rm -rf "$R3"; mkdir -p "$R3/target/bin" "$R3/var"
cp -f "$R2/bin/openp2p_aarch64" "$R3/target/bin/openp2p_x86_64"; chmod +x "$R3/target/bin/openp2p_x86_64"
rm -rf "$DATA"; mkdir -p "$DATA"; : > "$R/apps.log"
# 预置一个"已存在的可用旧二进制"，用于断言"不被替换"
printf '#!/bin/sh\necho "1.0.0-old"\n' > "$DATA/openp2p"; chmod +x "$DATA/openp2p"
OLD=$(md5sum "$DATA/openp2p" | awk '{print $1}')
MOCK_UNAME=x86_64 PATH="$MB:$PATH" TRIM_APPDEST="$R3/target" bash "$R/cmd/install_callback" >/dev/null 2>&1; RC=$?
[ "$RC" -eq 1 ] && res "错架构候选 → install_callback rc=1" 1 || res "错架构候选 → 期望 rc=1，实际 rc=$RC" 0
grep -q '候选二进制无法运行' "$R/apps.log" && res "日志明确『候选二进制无法运行』并含架构提示" 1 || res "日志缺明确提示" 0
[ "$(md5sum "$DATA/openp2p" | awk '{print $1}')" = "$OLD" ] && res "旧二进制未被错架构文件替换（md5 不变）" 1 || res "旧二进制被替换 → 危险" 0
grep -q '1\.0\.0-old' <(bash "$DATA/openp2p" 2>&1 | head -1) && res "数据目录二进制仍可正常执行" 1 || res "数据目录二进制已损坏" 0

echo
echo "=========== 块 E 汇总 ==========="
echo "PASS=$P FAIL=$F"
rm -rf "$R2" "$R3"
