#!/bin/bash
# ============================================================
# openp2p → 飞牛 fnOS .fpk 打包脚本
#
# 用法：
#   ./build.sh                          # 默认 3.25.11-1，全架构包
#   ./build.sh --version 3.25.11-2      # 指定包版本号
#   ./build.sh --arch x86               # 只打 x86 包（老版 fnOS 不认 platform=all 时用）
#   ./build.sh --arch arm               # 只打 arm 包
#
# 产物：dist/openp2p_<version>_<arch>.fpk
#
# 打包格式（与 fnpack 一致，本脚本自行实现，无需安装 fnpack）：
#   app.tgz = tar -czf app.tgz -C app .        （app/bin、app/ui 解包到 TRIM_APPDEST）
#   manifest 里写入 app.tgz 的 md5 作为 checksum
#   .fpk    = tar -czf <name>.fpk --exclude=app *   （其余文件平铺在包根）
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

VERSION="3.25.11-11"
ARCH="all"
SRC="src/openp2p"
DIST="dist"
BUILD="build_tmp"

usage() {
    sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --arch)    ARCH="${2:-}";    shift 2 ;;
        --version) VERSION="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        -*)        echo "未知参数：$1" >&2; usage >&2; exit 1 ;;
        *)         VERSION="$1"; shift ;;
    esac
done

case "$ARCH" in
    all) PLATFORM="all"; KEEP="openp2p_x86_64 openp2p_aarch64 openp2p_armv7 openp2p_i386" ;;
    x86) PLATFORM="x86"; KEEP="openp2p_x86_64 openp2p_i386" ;;
    arm) PLATFORM="arm"; KEEP="openp2p_aarch64 openp2p_armv7" ;;
    *)   echo "❌ 未知 --arch：$ARCH（可选 all | x86 | arm）" >&2; exit 1 ;;
esac

[ -d "$SRC" ] || { echo "❌ 源目录不存在：$SRC" >&2; exit 1; }
[ -f "$SRC/manifest" ] || { echo "❌ 缺少 manifest" >&2; exit 1; }

echo "▶ 版本号：$VERSION    架构：$ARCH（platform=$PLATFORM）"

# ---------- 1. 铺到构建目录 ----------
rm -rf "$BUILD"
mkdir -p "$BUILD" "$DIST"
cp -a "$SRC/." "$BUILD/"

cd "$BUILD"

# ---------- 2. 精简二进制 ----------
for f in app/bin/openp2p_*; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    keep="no"
    for k in $KEEP; do
        [ "$base" = "$k" ] && keep="yes"
    done
    if [ "$keep" = "no" ]; then
        rm -f "$f"
    fi
done
echo "▶ 包内二进制：$(ls app/bin | tr '\n' ' ')"

# ---------- 3. 写 manifest ----------
sed -i "s|^version[[:space:]]*=.*|version               = ${VERSION}|" manifest
sed -i "s|^platform[[:space:]]*=.*|platform              = ${PLATFORM}|" manifest
sed -i "/^checksum[[:space:]]*=/d" manifest

# ---------- 4. 打包 ----------
OUT="openp2p_${VERSION}_${ARCH}.fpk"
# 优先用官方 fnpack（它做额外校验，产物与 fnOS 期望完全一致）；
# 开发机上没装 fnpack 时回退到自实现打包（逻辑与 fnpack 等价，已逐项比对）
if command -v fnpack >/dev/null 2>&1; then
    echo "▶ 打包方式：官方 fnpack ($(fnpack --help 2>&1 | sed -n 's/^Version //p' | head -1))"
    if ! fnpack build -d . >/dev/null 2>&1; then
        echo "❌ fnpack 打包失败，请单独运行查看原因：fnpack build -d ." >&2
        exit 1
    fi
    mv -f openp2p.fpk "../$DIST/$OUT"
else
    echo "▶ 打包方式：内置打包器（未检测到 fnpack）"
    tar -czf app.tgz -C app .
    MD5="$(md5sum app.tgz | awk '{print $1}')"
    printf 'checksum              = %s\n' "$MD5" >> manifest
    echo "▶ app.tgz md5：$MD5"
    tar -czf "../$DIST/$OUT" --exclude='./app' --exclude='app' *
fi

cd ..
rm -rf "$BUILD"

# ---------- 6. 自检 ----------
echo
echo "▶ 自检：$DIST/$OUT"
FAIL=0
# 注意：先把清单抓到变量再 grep。直接 `tar -tzf | grep -q` 会因 grep 提前退出
# 触发 SIGPIPE，叠加 set -o pipefail 后会误报「缺少文件」。
LISTING="$(tar -tzf "$DIST/$OUT")"
for need in manifest ICON.PNG ICON_256.PNG config/privilege config/resource \
            cmd/main cmd/common cmd/install_callback cmd/upgrade_callback \
            cmd/uninstall_callback cmd/config_callback wizard/install wizard/config wizard/uninstall \
            app.tgz; do
    if printf '%s\n' "$LISTING" | grep -qxF "$need" || printf '%s\n' "$LISTING" | grep -qxF "./$need"; then
        :
    else
        echo "   ❌ 缺少 $need"; FAIL=1
    fi
done
if printf '%s\n' "$LISTING" | grep -qE '^(\./)?app/'; then
    echo "   ❌ 包内不应包含 app/ 目录（应已打成 app.tgz）"; FAIL=1
fi
MANIFEST_TEXT="$(tar -xzOf "$DIST/$OUT" manifest)"
if ! printf '%s\n' "$MANIFEST_TEXT" | grep -q '^checksum'; then
    echo "   ❌ manifest 缺少 checksum"; FAIL=1
fi
if ! printf '%s\n' "$MANIFEST_TEXT" | grep -q "^version.*${VERSION}"; then
    echo "   ❌ manifest 版本号未更新为 ${VERSION}"; FAIL=1
fi
if ! printf '%s\n' "$MANIFEST_TEXT" | grep -q "^platform.*${PLATFORM}"; then
    echo "   ❌ manifest platform 不是 ${PLATFORM}"; FAIL=1
fi
# 校验 app.tgz 内确实有可执行二进制与 UI（app.tgz 此时已随构建目录清理，从 fpk 里取）
TMPTGZ="$(mktemp)"
tar -xzOf "$DIST/$OUT" app.tgz > "$TMPTGZ"
APPTGZ_LIST="$(tar -tzf "$TMPTGZ")"
rm -f "$TMPTGZ"
if ! printf '%s\n' "$APPTGZ_LIST" | grep -q 'bin/openp2p_'; then
    echo "   ❌ app.tgz 内缺少 bin/openp2p_<arch>"; FAIL=1
fi
if ! printf '%s\n' "$APPTGZ_LIST" | grep -q 'ui/index.cgi'; then
    echo "   ❌ app.tgz 内缺少 ui/index.cgi"; FAIL=1
fi
if ! printf '%s\n' "$APPTGZ_LIST" | grep -q 'ui/config'; then
    echo "   ❌ app.tgz 内缺少 ui/config（桌面入口）"; FAIL=1
fi
if ! printf '%s\n' "$APPTGZ_LIST" | grep -q 'ui/images/icon_64.png'; then
    echo "   ❌ app.tgz 内缺少 ui/images/icon_64.png"; FAIL=1
fi

# 校验包内所有 JSON 是否合法（wizard / config 被 fnOS 直接解析，格式错会导致安装失败）
if command -v jq >/dev/null 2>&1; then
    for jf in wizard/install wizard/config wizard/uninstall config/privilege config/resource; do
        if ! tar -xzOf "$DIST/$OUT" "$jf" 2>/dev/null | jq -e . >/dev/null 2>&1; then
            echo "   ❌ $jf 不是合法 JSON"; FAIL=1
        fi
    done
else
    echo "   ⚠️  未找到 jq，跳过 JSON 合法性检查"
fi

if [ "$FAIL" = "0" ]; then
    echo "   ✅ 结构检查通过"
    echo
    echo "✅ 打包完成：$DIST/$OUT  ($(du -h "$DIST/$OUT" | cut -f1))"
else
    echo
    echo "❌ 自检未通过，请检查上面的缺失项" >&2
    exit 1
fi
