#!/bin/bash
# ============================================================
# 可独立复算的「最小复现」集合 —— 本文件里的每条命令都**只依赖公开输入**：
# 本仓库源码 + dist/ 里的 fpk + qa/legacy-* 快照，不需要任何私有环境。
#
# 立此文件的缘由（qa 第四轮）：此前 evidence-index.md 里的复现命令是手写的、**没实跑过**，
# 其中一条 sed 的 `|` 既当分隔符又出现在模式里，跑出来直接报错、产出 0 字节文件，
# 会被误读成「无泄漏」。教训：**写进证据索引的命令，必须先跑通再写进去**。
# 因此本文件承担"命令的唯一出处"，evidence-index.md 只引用它 + 它的输出 repro.log。
#
# 用法：bash repro.sh          （输出同时写到 stdout 与 repro.log）
# ============================================================
cd "$(dirname "$0")" || exit 1
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
SRC="$ROOT/src/openp2p"
DIST="$ROOT/dist"
QA="$(pwd)"
T=/tmp/repro-$$; mkdir -p "$T" || exit 1
# ⚠️ 本机（fnOS 上的 appuser 应用）环境自带 TRIM_APPNAME/TRIM_APPDEST/TRIM_PKGVAR/
# TRIM_TEMP_LOGFILE 等变量。若不清掉，cmd/common 会按"appuser"算出 /var/apps/appuser
# 下的路径，用例就在错误的目录上得出结论（我在 R4 上真踩到了）。这里统一固定。
export TRIM_APPNAME=openp2p
unset TRIM_APPDEST TRIM_PKGVAR TRIM_TEMP_LOGFILE 2>/dev/null || true
trap 'chmod -R u+rwX "$T" 2>/dev/null; rm -rf "$T"' EXIT
P=0; F=0
ok(){   P=$((P+1)); echo "  [OK]   $1"; }
bad(){  F=$((F+1)); echo "  [BAD]  $1"; }
say(){ echo; echo "=========== $* ==========="; }

echo "复现集运行时间：$(date '+%Y-%m-%d %H:%M:%S')"
# 包名不再写死（qa 第五轮 N5-5/N5-6：横幅曾长期停在 -6，而实际测的是源码树，
# 会让第三方误以为这份证据属于已作废的产物）。默认取 dist/ 下**最新**的产物。
PKG="${PKG:-$(ls -t "$DIST"/openp2p_3.25.11-*_all.fpk 2>/dev/null | head -1)}"
echo "被测产物：$PKG"
echo "  md5    = $(md5sum "$PKG" | awk '{print $1}')"
echo "  sha256 = $(sha256sum "$PKG" | awk '{print $1}')"

# ------------------------------------------------------------
say "R1 重定向顺序：把目标文件写在 2>/dev/null 之前会泄漏 stderr（P2-1 的核心事实）"
# 目录不可写 → 打开文件必然失败，此时才能看出 stderr 有没有被抑制。
mkdir -p "$T/r1/ro"; chmod 000 "$T/r1/ro"
n_old=$(bash -c '{ echo x; } >> '"$T"'/r1/ro/f 2>/dev/null' 2>&1 | wc -c)
n_grp=$(bash -c '{ echo x; } 2>/dev/null >> '"$T"'/r1/ro/f'  2>&1 | wc -c)
n_two=$(bash -c '{ echo x; } >> '"$T"'/r1/ro/f 2>/dev/null' 2>&1 | sed -n '1p' | wc -c)
echo "  旧写法 { echo x; } >> f 2>/dev/null   → stderr ${n_old} 字节"
echo "  新写法 { echo x; } 2>/dev/null >> f   → stderr ${n_grp} 字节"
[ "$n_old" -gt 0 ] && [ "$n_grp" -eq 0 ] \
    && ok "旧写法泄漏、新写法干净 → 这条判据有鉴别力（不是"怎么写都不泄漏"）" \
    || bad "重定向顺序实验未复现预期（old=${n_old} new=${n_grp}）"

# ------------------------------------------------------------
say "R2 产品代码：确认没有残留的旧写法 + 用行为实验验证写入函数不泄漏（P2-1 / BLK-3）"
# R2a：同一行里"目标文件出现在 2>/dev/null 之前"——这是 P2-1 的原始 bug 形态，必须为 0
n_a=$(grep -nE '(^|[^2&])(>>?|>\|) ?"?\$[A-Za-z_][A-Za-z0-9_]*"? 2>/dev/null' \
        "$SRC"/cmd/* "$SRC/app/ui/index.cgi" | grep -v '^[^:]*:[0-9]*: *#' | wc -l)
echo "  R2a 同行顺序错命中：$n_a"
[ "$n_a" -eq 0 ] && ok "R2a：无『目标文件在 2>/dev/null 之前』的写法" \
                 || bad "R2a：仍有旧写法 → $(grep -nE '(^|[^2&])(>>?|>\|) ?"?\$[A-Za-z_][A-Za-z0-9_]*"? 2>/dev/null' "$SRC"/cmd/* "$SRC/app/ui/index.cgi" | head -3 | tr '\n' ' ')"

# R2b：跨行的组命令（heredoc 写临时文件）——抑制写在收尾的 `} 2>/dev/null` 上。
#      检查规则：每个"目标重定向行"在后续 40 行内必须有 `} 2>/dev/null` 收尾，否则算漏抑制。
n_b=$(awk -v s="$SRC" '
  { line[FNR]=$0; n=FNR }
  END{
    c=0
    for (i=1;i<=n;i++){
      if (line[i] ~ /^[ \t]*#/) continue
      if (line[i] ~ /(^|[^2&])>>? ?"?\$[A-Za-z_]/ && line[i] !~ /2>\/dev\/null/){
        ok=0
        for (j=i+1;j<=i+40 && j<=n;j++){
          if (line[j] ~ /^[ \t]*\}[ \t]*2>\/dev\/null/) { ok=1; break }
          if (line[j] ~ /^[ \t]*\}[ \t]*$/) { break }
        }
        if (!ok){ c++; print "    " s ":" i ": " line[i] }
      }
    }
    print c
  }' "$SRC"/cmd/* "$SRC/app/ui/index.cgi" | tee "$T/r2b.txt" | tail -1)
echo "  R2b 跨行组未收尾命中：$n_b$([ "$n_b" -gt 0 ] && echo "（明细见上）")"
[ "$n_b" -eq 0 ] && ok "R2b：所有写入一律走上『2>/dev/null 在前 + 组收尾』的形式" \
                 || bad "R2b：有写入未抑制 stderr"

# R2c：行为实验（比文本扫描可信）——把目标文件设成打不开，捕获 stderr。
mkdir -p "$T/r2/ro"; chmod 000 "$T/r2/ro"
behav(){
  # $1 = 标签, $2 = 被测 common 路径, $3 = 要调的函数
  local out
  out=$(OPENP2P_APPROOT="$T/r2" TRIM_APPNAME=openp2p TRIM_PKGVAR="$T/r2/var" \
        LOG_FILE="$T/r2/ro/apps.log" TRIM_TEMP_LOGFILE="$T/r2/ro/install.err" \
        bash -c ". '$2'; $3" 2>&1 >/dev/null)
  echo "  [$1] stderr=$(printf '%s' "$out" | wc -c) 字节" >&2
  printf '%s' "$out"
}
leak_new=$(behav "-6" "$SRC/cmd/common" 'log_msg "x"; warn_msg "y"')
[ -z "$leak_new" ] && ok "R2c：-6 的 log_msg/warn_msg 在日志不可写时零泄漏" \
                   || bad "R2c：-6 仍泄漏：$(printf '%s' "$leak_new" | head -1)"
# 对照组：-4 旧写法必须泄漏（证明上面这条不是"怎么写都不泄漏"）
mkdir -p "$T/leg4b"; tar xzf "$DIST/openp2p_3.25.11-4_all.fpk" -C "$T/leg4b" cmd/common 2>/dev/null
if [ -f "$T/leg4b/cmd/common" ]; then
    leak_old=$(behav "-4 对照" "$T/leg4b/cmd/common" 'log_msg "x"; warn_msg "y"')
    [ -n "$leak_old" ] && ok "R2c 对照组：-4 旧写法确实泄漏 → 本用例有鉴别力" \
                       || bad "R2c 对照组未复现泄漏（用例无鉴别力）"
else
    bad "R2c 对照组：-4 解包失败"
fi

# ------------------------------------------------------------
say "R3 界面保存：写失败时必须如实报错、且不得把裸错误泄漏到 CGI stderr（BLK-3 / N-B）"
R="$T/r3"; DATA="$R/shares/openp2p"; mkdir -p "$R/ui" "$R/cmd" "$DATA" "$R/var"
sed "s|/var/apps/openp2p|$R|g" "$SRC/app/ui/index.cgi" > "$R/ui/index.cgi"
printf 'token=123456789\nnode=old-node\n' > "$DATA/settings.conf"
chmod 500 "$DATA"                      # 目录不可写：既挡住"新建"，也挡住 tmp+rename
B='action=save&token=987654321&node=new-node'
printf '%s' "$B" | CONTENT_LENGTH=${#B} REQUEST_METHOD=POST \
    OPENP2P_APPROOT="$R" bash "$R/ui/index.cgi" >"$R/out" 2>"$R/err"
chmod 700 "$DATA"
grep -q '设置写入失败' "$R/out" && ok "写失败时界面如实提示『设置写入失败』" \
                                || bad "写失败却没有失败提示"
grep -q '设置已保存' "$R/out" && bad "写失败却出现『设置已保存』（谎报）" \
                             || ok "写失败时未出现『已保存』文案"
[ -s "$R/err" ] && bad "CGI stderr 被污染：$(head -1 "$R/err")" || ok "CGI stderr 无泄漏"
grep -q '987654321' "$DATA/settings.conf" && bad "写失败却仍有内容落盘" \
                                          || ok "失败时旧设置未被破坏"

# 对照组：-5 版（修复前）在同一场景必须既谎报又泄漏
if [ -f "$QA/legacy-ui/index.cgi.from-5" ]; then
    sed "s|/var/apps/openp2p|$R|g" "$QA/legacy-ui/index.cgi.from-5" > "$R/ui/legacy5.cgi"
    rm -f "$DATA/settings.conf"
    chmod 500 "$DATA"
    printf '%s' "$B" | CONTENT_LENGTH=${#B} REQUEST_METHOD=POST \
        OPENP2P_APPROOT="$R" bash "$R/ui/legacy5.cgi" >"$R/o5" 2>"$R/e5"
    chmod 700 "$DATA"
    grep -q '设置已保存' "$R/o5" && ok "对照组 -5：确实谎报『设置已保存』" \
                                 || bad "对照组 -5 未复现谎报（用例无鉴别力）"
    [ -s "$R/e5" ] && ok "对照组 -5：确实泄漏 stderr（$(head -1 "$R/e5")）" \
                   || bad "对照组 -5 未复现 stderr 泄漏（用例无鉴别力）"
else
    bad "对照组快照缺失：$QA/legacy-ui/index.cgi.from-5"
fi

# ------------------------------------------------------------
say "R4 find_all_pids 不得认领 argv0 伪装进程（P2-4 / B5 同类）"
R="$T/r4"; mkdir -p "$R/shares/openp2p" "$R/var"
cp /bin/sleep "$T/fake-sleep"
# BIN 必须真实存在，否则"拒绝认领"可能只是因为"BIN 不存在"（qa 明确提醒过这种假信任）。
# 用 common 自己算出的 $BIN 路径，避免我手写路径与实现不一致（本机 TRIM_* 变量已在上方固定）。
BINPATH=$(OPENP2P_APPROOT="$R" bash -c '. "'"$SRC"'/cmd/common"; echo "$BIN"')
mkdir -p "$(dirname "$BINPATH")"
printf '#!/bin/bash\nexec sleep 30\n' > "$BINPATH"; chmod +x "$BINPATH"
echo "  BIN=$BINPATH（已放置可执行文件，inode $(stat -c %i "$BINPATH")）"
(
  OPENP2P_APPROOT="$R" LOG_FILE="$R/log"
  . "$SRC/cmd/common"
  exec -a "$BINPATH" "$T/fake-sleep" 47
) &
FAKE=$!
sleep 0.5
echo "  伪装进程 pid=$FAKE  argv0=$(tr '\0' '\n' < /proc/$FAKE/cmdline | head -1)  exe=$(readlink /proc/$FAKE/exe)"
found=$(OPENP2P_APPROOT="$R" LOG_FILE="$R/log" bash -c '. "'"$SRC"'/cmd/common"; find_all_pids' 2>/dev/null)
kill "$FAKE" 2>/dev/null; wait "$FAKE" 2>/dev/null
echo "  find_all_pids 返回：[$found]"
[ -z "$found" ] && ok "-6 拒绝认领 argv0 伪装进程" || bad "-6 认领了伪装进程（会误杀无关进程）"
if [ -f "$T/fake-sleep" ]; then
    : # 对照：-4 的同一函数（预期会认领）
    cp "$DIST/openp2p_3.25.11-4_all.fpk" "$T/" 2>/dev/null
    mkdir -p "$T/leg4"; tar xzf "$T/openp2p_3.25.11-4_all.fpk" -C "$T/leg4" cmd/common 2>/dev/null
    if [ -f "$T/leg4/cmd/common" ]; then
        (
          OPENP2P_APPROOT="$R" LOG_FILE="$R/log"
          . "$T/leg4/cmd/common"
          exec -a "$BINPATH" "$T/fake-sleep" 47
        ) &
        FAKE2=$!; sleep 0.5
        found2=$(OPENP2P_APPROOT="$R" LOG_FILE="$R/log" bash -c '. "'"$T"'/leg4/cmd/common"; find_all_pids' 2>/dev/null)
        kill "$FAKE2" 2>/dev/null; wait "$FAKE2" 2>/dev/null
        echo "  对照 -4 find_all_pids 返回：[$found2]"
        [ -n "$found2" ] && ok "对照组 -4：认领了伪装进程 → 证明本用例有鉴别力" \
                         || bad "对照组 -4 未认领（沙箱环境差异，需人工确认）"
    else
        bad "对照组 -4 解包失败"
    fi
fi

# ------------------------------------------------------------
say "R5 符号链接数据目录：is_our_pid 必须为真（B11 真机根因）"
R="$T/r5"; mkdir -p "$R/real" "$R/var"
cp /bin/sleep "$R/real/openp2p"
ln -sfn "$R/real" "$R/link"                 # DATA_DIR 指向符号链接，正是真机形态
(
  OPENP2P_APPROOT="$R"
  . "$SRC/cmd/common"
  DATA_DIR="$R/link"                        # 真机 /var/apps/openp2p/shares/openp2p → /volN/@appshare/openp2p
  BIN="$DATA_DIR/openp2p"
  nohup "$BIN" 53 >/dev/null 2>&1 &
  P1=$!
  sleep 0.5
  echo "  进程 pid=$P1  /proc/$P1/exe = $(readlink /proc/$P1/exe)"
  if is_our_pid "$P1"; then echo "  is_our_pid → TRUE"; else echo "  is_our_pid → FALSE"; fi
  kill "$P1" 2>/dev/null
) > "$T/r5.out" 2>&1
cat "$T/r5.out"
grep -q 'is_our_pid → TRUE' "$T/r5.out" && ok "符号链接场景下 -6 认得自己启动的进程" \
                                        || bad "符号链接场景下 is_our_pid 为假（B11 回归）"
# 对照：真机 -1 快照（预期 FALSE → 于是每次 start 都判"未运行"→ 重复起实例）
if [ -f "$QA/legacy-3.25.11-1-cmd/common" ]; then
    (
      OPENP2P_APPROOT="$R"
      . "$QA/legacy-3.25.11-1-cmd/common"
      DATA_DIR="$R/link"; BIN="$DATA_DIR/openp2p"
      nohup "$BIN" 53 >/dev/null 2>&1 &
      P1=$!; sleep 0.5
      if is_our_pid "$P1"; then echo "  对照 -1：is_our_pid → TRUE"; else echo "  对照 -1：is_our_pid → FALSE"; fi
      kill "$P1" 2>/dev/null
    ) > "$T/r5b.out" 2>&1
    cat "$T/r5b.out"
    grep -q '对照 -1：is_our_pid → FALSE' "$T/r5b.out" \
        && ok "对照组 -1：符号链接下 is_our_pid 恒假 → 真机重复实例的根因复现" \
        || bad "对照组 -1 未复现根因（用例无鉴别力）"
else
    bad "对照组快照缺失：$QA/legacy-3.25.11-1-cmd/common"
fi

# ------------------------------------------------------------
say "R6 日志不可写时启动不得泄漏裸错误（N-D）"
R="$T/r6"; mkdir -p "$R/shares/openp2p" "$R/cmd" "$R/var" "$R/target/bin" "$R/ro"
cp -r "$SRC/cmd/." "$R/cmd/"; chmod +x "$R"/cmd/*
# 桩二进制：必须能应答 `-v`（cmd/main:84 会先 `"$BIN" -v` 做可用性自检，桩若死循环
# 就会**把 main start 挂住**——我第一次写成 `while :; do sleep 1; done` 就把复现集跑超时了），
# 应答完再 exec sleep 保持存活，模拟真实的常驻进程。
cat > "$R/shares/openp2p/openp2p" <<'STUB'
#!/bin/bash
case "${1:-}" in
  -v|--version) echo "3.25.11"; exit 0 ;;
esac
exec sleep 300
STUB
chmod +x "$R/shares/openp2p/openp2p"
printf 'token=123456789\nnode=n1\nsharebandwidth=10\nserverhost=api.openp2p.cn\nserverport=27183\nloglevel=1\n' > "$R/shares/openp2p/settings.conf"
chmod 500 "$R/ro"
( OPENP2P_APPROOT="$R" TRIM_PKGVAR="$R/var" LOG_FILE="$R/ro/apps.log" \
  bash "$R/cmd/main" start ) >/dev/null 2>"$R/err"
rc=$?; chmod 700 "$R/ro"
PIDF="$R/var/app.pid"; PIDS=$(head -n 1 "$PIDF" 2>/dev/null | tr -d '[:space:]')
pkill -f "$R/shares/openp2p/openp2p" 2>/dev/null
echo "  start rc=$rc  stderr=$(wc -c <"$R/err") 字节  pid_file=${PIDS:-（空）}"
[ -s "$R/err" ] && bad "启动泄漏 stderr：$(head -1 "$R/err")" || ok "日志不可写时启动无 stderr 泄漏"
# start 只有在 pid_alive 通过时才返回 0（cmd/main 的既有语义），故 rc=0 即"确实起来了"
[ "$rc" = "0" ] && ok "日志不可写时依然成功启动（进程输出退回 /dev/null）" \
                || bad "日志不可写导致启动失败（rc=$rc）"

echo
echo "=========== 复现集汇总：OK=$P  BAD=$F ==========="
[ "$F" = 0 ] || exit 1
