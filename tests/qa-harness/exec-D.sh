#!/bin/bash
# TC-08 跨架构补测：用 qemu-user-static 真正执行各架构二进制
Q=/tmp/qemuget/x/usr/bin
A=$(mktemp -d)
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
tar xzf "$PKG" -O app.tgz | tar xz -C "$A"
cd "$A/bin" && chmod +x ./*
echo "=== TC-08b 四架构二进制可执行性实测 ==="
echo "（qemu-user-static 由 Debian 包免 root 解包：/tmp/qemuget/x/usr/bin）"
for pair in "x86_64:" "aarch64:$Q/qemu-aarch64-static" "armv7:$Q/qemu-arm-static" "i386:$Q/qemu-i386-static"; do
  arch="${pair%%:*}"; em="${pair##*:}"
  out=$($em ./openp2p_$arch -v 2>&1 | head -1)
  if [ "$out" = "3.25.11" ]; then
    echo "  [PASS] $arch 可执行，版本输出：$out"
  else
    echo "  [FAIL] $arch 执行异常：$out"
  fi
done
echo
echo "=== TC-08c 判定 i386 异常是 qemu 局限还是二进制损坏 ==="
echo "对照实验：Go 官方 386 工具链（真实 386 硬件上必然可用）在同一 qemu-i386 下运行"
GOOUT=$($Q/qemu-i386-static /tmp/go386/go/bin/go version 2>&1 | head -2)
echo "  官方 go 386 输出：$GOOUT"
case "$GOOUT" in
  *"fatal error"*|*"fatal:"*) echo "  [结论] 官方 Go 386 二进制同样崩溃 → 属 qemu-i386 对 Go 二进制的模拟局限，非本包二进制损坏" ;;
  *) echo "  [结论] 官方 Go 386 可运行而本包不可 → 本包 i386 二进制可能损坏（需上报）" ;;
esac
echo
echo "=== 对照：三个可用架构的 Go 构建信息 ==="
for f in openp2p_x86_64 openp2p_aarch64 openp2p_armv7 openp2p_i386; do
  printf '  %-18s %s\n' "$f" "$(strings "$f" 2>/dev/null | grep -m1 -oE 'go1\.[0-9]+(\.[0-9]+)?')"
done
rm -rf "$A"
