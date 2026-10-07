#!/bin/bash
# ============================================================
# 从上游 openp2p 官方 Release 获取四个架构的二进制，并校验后落盘。
#
#   ./tools/fetch-upstream.sh                 # 下载 + 校验 + 写入 src/openp2p/app/bin/
#   ./tools/fetch-upstream.sh --verify        # 只校验当前 src/openp2p/app/bin/ 里的文件（不联网）
#   ./tools/fetch-upstream.sh --dest /tmp/x   # 写到别处（用于试跑）
#
# 校验依据：tools/upstream-v3.25.11.sha256（上游资产 sha256）+ NOTICE 中的 md5。
# 任何一项不匹配 → 报错退出，不落盘。
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/.."

UPSTREAM_REPO="openp2p-cn/openp2p"
UPSTREAM_VER="3.25.11"
MANIFEST="tools/upstream-v3.25.11.sha256"
DEST="src/openp2p/app/bin"
MODE="fetch"

while [ $# -gt 0 ]; do
    case "$1" in
        --verify) MODE="verify"; shift ;;
        --dest)   DEST="${2:-}"; shift 2 ;;
        -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "未知参数：$1" >&2; exit 1 ;;
    esac
done

[ -f "$MANIFEST" ] || { echo "❌ 缺少校验清单：$MANIFEST" >&2; exit 1; }
[ -d "$DEST" ]    || mkdir -p "$DEST"

# 上游资产名 → 本仓库文件名 → sha256
mapfile -t LINES < <(grep -v '^#' "$MANIFEST" | grep -v '^[[:space:]]*$')

fail=0
TMP=""
# 注意：在 `set -e` 下，EXIT trap 里最后一条命令若返回非 0，会把整个脚本的退出码带成 1
# （即使前面全部成功）。所以这里必须显式 `return 0`。
cleanup() { [ -n "${TMP:-}" ] && rm -rf "$TMP"; return 0; }
trap cleanup EXIT

if [ "$MODE" = "fetch" ]; then
    TMP="$(mktemp -d)"
fi

for line in "${LINES[@]}"; do
    read -r tgz_sum bin_sum asset target <<<"$line"
    [ -n "${tgz_sum:-}" ] && [ -n "${bin_sum:-}" ] && [ -n "${asset:-}" ] && [ -n "${target:-}" ] \
        || { echo "❌ 清单格式错误：$line" >&2; exit 1; }

    if [ "$MODE" = "verify" ]; then
        f="$DEST/$target"
        [ -f "$f" ] || { echo "❌ 缺失：$f"; fail=1; continue; }
        got="$(sha256sum "$f" | cut -d' ' -f1)"
        if [ "$got" = "$bin_sum" ]; then
            echo "✅ $target  sha256 匹配（$got）"
        else
            echo "❌ $target  sha256 不符：期望 $bin_sum，实际 $got"
            fail=1
        fi
        continue
    fi

    url="https://github.com/$UPSTREAM_REPO/releases/download/v$UPSTREAM_VER/$asset"
    echo "▶ 下载 $asset"
    if ! curl -fsSL --retry 3 --retry-delay 2 -o "$TMP/$asset" "$url"; then
        echo "❌ 下载失败：$url" >&2; fail=1; continue
    fi
    got="$(sha256sum "$TMP/$asset" | cut -d' ' -f1)"
    if [ "$got" != "$tgz_sum" ]; then
        echo "❌ $asset 资产校验失败：期望 $tgz_sum，实际 $got（上游资产已变？请勿继续）" >&2; fail=1; continue
    fi
    tar -xzf "$TMP/$asset" -C "$TMP"
    [ -f "$TMP/openp2p" ] || { echo "❌ $asset 内没有 openp2p" >&2; fail=1; continue; }
    gotbin="$(sha256sum "$TMP/openp2p" | cut -d' ' -f1)"
    if [ "$gotbin" != "$bin_sum" ]; then
        echo "❌ $asset 解包后二进制校验失败：期望 $bin_sum，实际 $gotbin" >&2; fail=1; continue
    fi
    install -m 0755 "$TMP/openp2p" "$DEST/$target"
    rm -f "$TMP/openp2p"
    echo "✅ $target  ← $asset（资产 sha256 $got / 二进制 sha256 $gotbin）"
done

[ "$fail" -eq 0 ] || { echo "❌ 存在失败项，见上。" >&2; exit 1; }
echo "▶ 全部通过。"

if [ "$MODE" = "fetch" ]; then
    echo "▶ 复核落盘结果（sha256）"
    "$0" --verify --dest "$DEST"
fi
