#!/bin/bash
# TC-08 跨架构补测：用 qemu-user-static 真正执行各架构二进制
Q=/tmp/qemuget/x/usr/bin
A=$(mktemp -d)
tar xzf /vol4/@appshare/octop-native/data/.octop/agents/ZD3XW7/projects/fnos-openp2p/dist/openp2p_3.25.11-8_all.fpk -O app.tgz | tar xz -C "$A"
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
