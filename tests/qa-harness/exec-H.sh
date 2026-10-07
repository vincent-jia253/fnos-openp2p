#!/bin/bash
# 块 H：应用界面（app/ui/index.cgi）回归
#
# 为什么必须有这一块：
#   块 A–G 测的都是 cmd/*（后端）。但用户实际交互的是**界面**，而界面里曾经
#   自造过一套判活逻辑（跨用户 kill -0 / 未校验 pidof）、并且会在没停掉旧进程、
#   没确认起得来的情况下就喊「已自动重启」「应用已停止」。这类"文案与事实不符"
#   正是把用户带偏的元凶（缺陷 T9 / N1 / N6 / N7）。
#   本块把 CGI 真跑起来（模拟 POST），断言的是**界面输出与实际状态一致**。
#
# 被测对象：源码树 app/ui/index.cgi + cmd/*
SRC=/vol4/@appshare/octop-native/data/.octop/agents/ZD3XW7/projects/fnos-openp2p/src/openp2p
PKG=/vol4/@appshare/octop-native/data/.octop/agents/ZD3XW7/projects/fnos-openp2p/dist/openp2p_3.25.11-8_all.fpk
QA=/vol4/@appshare/octop-native/data/.octop/agents/ZD3XW7/teams/dev-squad/runs/20260930-openp2p-fpk/qa
LEGACY_UI="$QA/legacy-ui"    # 历史版本的 ui/index.cgi 快照（对照组用，证明用例有鉴别力）
LEGACY_CMD="$QA/legacy-cmd"  # 历史版本的 cmd/common 快照（同理）
R=/tmp/qaH; DATA="$R/shares/openp2p"; V="$R/var"
P=0; F=0
res(){ if [ "$2" = 1 ]; then P=$((P+1)); echo "  [PASS] $1"; else F=$((F+1)); echo "  [FAIL] $1"; fi; }
say(){ echo; echo "=========== $* ==========="; }

echo "被测源码: $SRC"
echo "包 md5  : $(md5sum "$PKG" 2>/dev/null | awk '{print $1}')（二进制来源）"

# 起一份沙箱里的 CGI：把源码里硬编码的 /var/apps/openp2p 改指沙箱
stage(){
  if ps -eo cmd | grep -F "$R/shares/openp2p/openp2p" | grep -v grep | grep -q .; then
    echo "  [harness] 清理上例残留进程"; pkill -f "^$R/shares/openp2p/openp2p" 2>/dev/null; sleep 1; fi
  # 先恢复权限再删：本套用例会**故意**把沙箱里的目录改成 0500/0600/把 settings.conf
  # 换成只读目录。那种目录连 descend 都不允许，`rm -rf` 只能删掉一半 —— 于是**下一个块**
  # 会在脏沙箱里得出错误结论。本轮真踩到：H11/H13 注入的失败目录没清干净，
  # 导致 H4/H5 在"settings.conf 已是个目录"的状态下误报 FAIL。
  if [ -d "$R" ]; then chmod -R u+rwX "$R" 2>/dev/null; rm -rf "$R"; fi
  rm -rf "$R"; mkdir -p "$R/ui" "$V" "$R/target/bin" "$DATA"
  # 沙箱新鲜度断言：脏沙箱 = 后面所有断言都不可信，必须立刻喊出来
  if [ -e "$DATA/settings.conf" ] || [ -e "$DATA/config.json" ]; then
    echo "  [harness][严重] 沙箱未清干净：$DATA 仍残留上一例的文件，后续断言不可信"
  fi
  cp -r "$SRC"/cmd "$R/cmd"; chmod +x "$R"/cmd/*
  mkdir -p "$R/ui/images"
  sed "s|/var/apps/openp2p|$R|g" "$SRC/app/ui/index.cgi" > "$R/ui/index.cgi"
  chmod +x "$R/ui/index.cgi"
  tar xzf "$PKG" -O app.tgz | tar xz -C "$R/target" --wildcards 'bin/openp2p_x86_64' 2>/dev/null
  echo "  [harness] 负载二进制已铺：$(ls "$R/target/bin" 2>/dev/null | tr '\n' ' ')"
  mv "$R/target/bin/openp2p_x86_64" "$DATA/openp2p"; chmod +x "$DATA/openp2p"
  : > "$R/apps.log"
  export OPENP2P_APPROOT="$R" TRIM_APPNAME=openp2p TRIM_APPDEST="$R/target" \
         TRIM_PKGVAR="$V" LOG_FILE="$R/apps.log" TRIM_TEMP_LOGFILE="$R/install.err"
}

# 模拟浏览器 POST：$1 = POST body
cgi(){ printf '%s' "$1" | CONTENT_LENGTH=${#1} REQUEST_METHOD=POST bash "$R/ui/index.cgi" 2>"$R/cgi.err"; }

say "H1 语法：index.cgi 必须是合法 bash"
bash -n "$SRC/app/ui/index.cgi" && res "bash -n 通过" 1 || res "bash -n 失败" 0

say "H2 降级分支（cmd/common 不存在）不得冒出 command not found（缺陷 N1）"
# 注意：必须先把沙箱铺好再做（早期版本漏了 stage，导致下面重定向到一个不存在的
# 目录、文件根本没生成，而 grep 又找不到错误文件 —— 变成"假通过"）。
# 教训（qa 第四轮抓到）：旧版这里把 sed 脚本写成 `s|\$R/cmd/common|...|`，在双引号里
# 转义后 sed 收到的是正则 `$R`（行尾锚点 + 字面 R）—— **永远匹配不到**，于是所谓
# "降级分支副本"与普通副本逐字节相同，H2 实际测的是普通分支，N1 的负向对照根本不存在。
# 现在分两步 sed，并对**每一处替换单独断言**（教训 T11：替换必须逐个验证，不能靠"整文件非空"）。
stage
sed "s|/var/apps/openp2p|$R|g" "$SRC/app/ui/index.cgi" > "$R/ui/index-fallback.cgi"
sed -i "s|$R/cmd/common|/nonexistent/cmd/common|g; s|$R/cmd/main|/nonexistent/cmd/main|g" \
    "$R/ui/index-fallback.cgi"
if [ -s "$R/ui/index-fallback.cgi" ]; then
    res "降级分支副本已生成（用例前置成立）" 1
else
    res "降级分支副本未生成，本用例无效" 0
fi
nc=$(grep -c '/nonexistent/cmd/common' "$R/ui/index-fallback.cgi")
nm=$(grep -c '/nonexistent/cmd/main' "$R/ui/index-fallback.cgi")
[ "${nc:-0}" -ge 1 ] && res "cmd/common 已真正改指到不存在的路径（$nc 处）" 1 \
    || res "cmd/common 降级替换未生效 → 测的仍是普通分支（用例无效）" 0
[ "${nm:-0}" -ge 1 ] && res "cmd/main 已真正改指到不存在的路径（$nm 处）" 1 \
    || res "cmd/main 降级替换未生效（用例无效）" 0
bash -n "$R/ui/index-fallback.cgi" && res "降级分支副本仍是合法 bash" 1 || res "降级分支副本语法错误" 0
printf '' | CONTENT_LENGTH=0 REQUEST_METHOD=GET bash "$R/ui/index-fallback.cgi" >"$R/fallback.out" 2>"$R/fallback.err"
if [ -s "$R/fallback.out" ]; then
    res "降级分支能正常渲染页面（证明它真的被执行了）" 1
else
    res "降级分支未产生输出，用例前置不成立" 0
fi
if grep -q 'command not found' "$R/fallback.err"; then
    res "降级分支泄漏 'command not found'（公共函数未补齐）：$(head -1 "$R/fallback.err")" 0
else
    res "降级分支无 command not found 泄漏" 1
fi
grep -q 'command not found\|未安装\|已停止' "$R/fallback.out" && res "降级分支给出可读的状态文案" 1 || res "降级分支页面缺少状态文案" 0
# ---- 对照组（本用例的鉴别力证明）----
# 用 -3 版（N1 修复前）的 index.cgi 跑**同一场景**：它必须真的泄漏 command not found。
# 没有这个对照，"无泄漏"就可能是"根本没进降级分支"造成的假绿 —— 这正是本轮的教训。
if [ -f "$LEGACY_UI/index.cgi.from-3" ]; then
    sed "s|/var/apps/openp2p|$R|g" "$LEGACY_UI/index.cgi.from-3" > "$R/ui/legacy3.cgi"
    sed -i "s|$R/cmd/common|/nonexistent/cmd/common|g; s|$R/cmd/main|/nonexistent/cmd/main|g" "$R/ui/legacy3.cgi"
    L3B="action=save&token=abc&serverport=99999"
    printf '%s' "$L3B" | CONTENT_LENGTH=${#L3B} REQUEST_METHOD=POST bash "$R/ui/legacy3.cgi" >/dev/null 2>"$R/legacy3.err"
    if grep -q 'command not found' "$R/legacy3.err"; then
        res "对照组：-3 版在同场景确实泄漏 'command not found'（证明本用例有鉴别力）" 1
    else
        res "对照组未复现旧缺陷 → 本用例无鉴别力（无法区分修没修）" 0
    fi
else
    res "对照组快照缺失 $LEGACY_UI/index.cgi.from-3（无法证明用例有鉴别力）" 0
fi

say "H3 界面校验必须与后端一致：越界端口/带宽要在界面就被拒绝（缺陷 N7）"
stage
OUT=$(cgi "action=save&token=123456789&serverport=99999")
grep -q '1-65535' <<<"$OUT" && res "serverport=99999 被界面拒绝并提示范围" 1 || res "越界端口未被界面拒绝（界面显示值≠生效值）" 0
grep -q '99999' "$DATA/settings.conf" 2>/dev/null && res "越界端口被写入 settings.conf（后端会静默回退，用户被误导）" 0 || res "越界端口未写入配置" 1
OUT=$(cgi "action=save&token=123456789&sharebandwidth=999999")
grep -q '0-100000' <<<"$OUT" && res "sharebandwidth=999999 被界面拒绝并提示范围" 1 || res "越界带宽未被界面拒绝" 0

say "H4 未运行时保存设置：不得谎报『已重启』（缺陷 N6）"
stage
OUT=$(cgi "action=save&token=123456789&node=my-nas")
grep -q '应用当前未运行' <<<"$OUT" && res "如实提示『应用当前未运行』" 1 || res "文案未如实反映未运行状态" 0
grep -q '已自动重启' <<<"$OUT" && res "未运行时却喊『已自动重启』（谎报）" 0 || res "未谎报已重启" 1

say "H5 运行中保存设置：既要真重启，也要如实回报（缺陷 N6/T9③）"
stage
printf 'token=123456789\nnode=my-nas\nsharebandwidth=10\nserverhost=api.openp2p.cn\nserverport=27183\nloglevel=1\n' > "$DATA/settings.conf"
bash "$R/cmd/main" start >/dev/null 2>&1; sleep 2
if pgrep -f "^$DATA/openp2p" >/dev/null; then
    OLD=$(pgrep -f "^$DATA/openp2p" | head -1)
    OUT=$(cgi "action=save&token=123456789&node=my-nas&sharebandwidth=10")
    grep -q '已自动重启' <<<"$OUT" && res "运行中保存 → 提示已自动重启" 1 || res "运行中保存未提示重启：$(grep -o '>[^<]*重启[^<]*<' <<<"$OUT" | head -1)" 0
    NEW=$(pgrep -f "^$DATA/openp2p" | head -1)
    if [ -n "$NEW" ] && [ "$NEW" != "$OLD" ] && [ "$(pgrep -f "^$DATA/openp2p" | wc -l)" = 1 ]; then
        res "确实完成了重启且只有 1 个实例（旧 $OLD → 新 $NEW）" 1
    else
        res "重启后实例数/进程号异常：old=$OLD new=$NEW count=$(pgrep -f "^$DATA/openp2p" | wc -l)" 0
    fi
else
    res "前置失败：应用未启动，本用例无法执行" 0
fi

say "H6 停止按钮：停掉后必须报『已停止』且真的没进程；进程仍在时不得谎报（T9②/N6）"
stage
printf 'token=123456789\nnode=my-nas\nsharebandwidth=10\nserverhost=api.openp2p.cn\nserverport=27183\nloglevel=1\n' > "$DATA/settings.conf"
bash "$R/cmd/main" start >/dev/null 2>&1; sleep 2
if pgrep -f "^$DATA/openp2p" >/dev/null; then
    OUT=$(cgi "action=stop")
    if ! pgrep -f "^$DATA/openp2p" >/dev/null; then
        grep -q '应用已停止' <<<"$OUT" && res "进程已清空且提示『应用已停止』" 1 || res "进程已清空但提示异常" 0
    else
        grep -q '未能停止' <<<"$OUT" && res "进程仍在时如实提示未停止" 1 || res "进程仍在却报『已停止』（谎报）" 0
    fi
else
    res "前置失败：应用未启动" 0
fi

# ---- 负向用例（qa 复核指出：旧版 H6 的"进程仍在"分支在沙箱里恒不可达，属假信心）----
# 做法：注入一个"stop 必定失败"的桩 main（模拟权限不足 / 停不掉），
# 此时进程仍在，界面**不得**报『已停止』，必须如实告警。方法同 qa 在 N6③ 的验证。
bash "$R/cmd/main" start >/dev/null 2>&1; sleep 2
if pgrep -f "^$DATA/openp2p" >/dev/null; then
    cat > "$R/cmd/main-stub" <<'STUB'
#!/bin/bash
# 桩：stop 永远失败（模拟跨用户 EPERM：进程还在，但 kill 不动）
case "${1:-}" in
  stop)  exit 1 ;;
  start) exit 0 ;;
  *)     exit 0 ;;
esac
STUB
    chmod +x "$R/cmd/main-stub"
    sed "s|^MAIN_SCRIPT=.*|MAIN_SCRIPT=\"$R/cmd/main-stub\"|" "$R/ui/index.cgi" > "$R/ui/index-stub.cgi"
    POST_STOP="action=stop"
    OUT2=$(printf '%s' "$POST_STOP" | CONTENT_LENGTH=${#POST_STOP} REQUEST_METHOD=POST bash "$R/ui/index-stub.cgi" 2>/dev/null)
    [ -n "$OUT2" ] || res "桩场景 CGI 无输出（用例自身失效）" 0
    grep -q '未能停止' <<<"$OUT2" \
        && res "注入『stop 失败』桩后：界面如实提示『未能停止』（不谎报）" 1 \
        || res "stop 失败时界面未给出『未能停止』告警（谎报成功）" 0
    grep -q '应用已停止' <<<"$OUT2" \
        && res "stop 失败却出现『应用已停止』文案（谎报）" 0 \
        || res "stop 失败时未出现『应用已停止』文案" 1
    # ---- 对照组：-2 版 index.cgi 的 stop 分支无条件喊「🛑 应用已停止」----
    # 用它跑同样的"stop 必定失败"场景，必须谎报，才能证明上面两条断言有鉴别力。
    # （qa 第四轮指出：此前仓库里没有旧 index.cgi 快照，H6 的"FAIL 于旧实现"不可复算。）
    if [ -f "$LEGACY_UI/index.cgi.from-2" ]; then
        sed "s|^MAIN_SCRIPT=.*|MAIN_SCRIPT=\"$R/cmd/main-stub\"|" "$LEGACY_UI/index.cgi.from-2" > "$R/ui/legacy2.cgi"
        sed -i "s|/var/apps/openp2p|$R|g" "$R/ui/legacy2.cgi"
        OUT3=$(printf '%s' "$POST_STOP" | CONTENT_LENGTH=${#POST_STOP} REQUEST_METHOD=POST bash "$R/ui/legacy2.cgi" 2>/dev/null)
        grep -q '应用已停止' <<<"$OUT3" \
            && res "对照组：-2 版在 stop 失败时确实谎报『应用已停止』（证明本用例有鉴别力）" 1 \
            || res "对照组未复现旧版谎报 → 本用例无鉴别力" 0
    else
        res "对照组快照缺失 $LEGACY_UI/index.cgi.from-2（无法证明用例有鉴别力）" 0
    fi
    pkill -f "^$DATA/openp2p" 2>/dev/null; sleep 1
else
    res "负向用例前置失败：进程不在，无法验证谎报" 0
fi

say "H7 启动按钮：未填 Token 也应启动成功，且文案说明暂不组网（T9①/B8）"
stage
OUT=$(cgi "action=start")
if pgrep -f "^$DATA/openp2p" >/dev/null; then
    grep -q '未填 Token' <<<"$OUT" && res "未填 Token 也能启动，并提示暂不组网" 1 || res "启动了但文案未说明 Token 状态" 0
else
    res "未填 Token 时未能启动（B8 回归）" 0
fi
grep -q '尚未填写 Token' <<<"$OUT" && res "状态卡给出填写 Token 的引导" 1 || res "缺少 Token 引导提示" 0

say "H8 界面不得再自造判活逻辑（B9/B10 回归）"
grep -qE '^[[:space:]]*[^#]*kill -0|^[[:space:]]*[^#]*pidof ' "$SRC/app/ui/index.cgi" \
    && res "index.cgi 仍有 kill -0/pidof 判活" 0 || res "index.cgi 无自造判活逻辑" 1
grep -q 'is_running || return 1' "$SRC/app/ui/index.cgi" \
    && res "running_pid 复用 cmd/common 的 is_running" 1 || res "running_pid 未复用公共实现" 0


say "H9 保存设置写失败：不得谎报『已保存』，也不得把裸错误泄漏到 CGI stderr（BLK-3/N-B）"
stage
printf 'token=123456789\nnode=my-nas\nsharebandwidth=10\n' > "$DATA/settings.conf"
chmod 500 "$DATA"          # 数据目录不可写 → 写入必然失败（沙箱内我们是属主，chmod 有效）
B='action=save&token=987654321&node=leak-test'
printf '%s' "$B" | CONTENT_LENGTH=${#B} REQUEST_METHOD=POST bash "$R/ui/index.cgi" >"$R/h9.out" 2>"$R/h9.err"
chmod 700 "$DATA"
grep -q '设置写入失败' "$R/h9.out" \
    && res "写失败时如实提示『设置写入失败』" 1 \
    || res "写失败却未给出失败提示（界面文案：$(grep -o '[✅❌⚠️][^<]*' "$R/h9.out" | head -1)）" 0
grep -q '设置已保存' "$R/h9.out" \
    && res "写失败却出现『设置已保存』文案（谎报）" 0 \
    || res "写失败时未出现『已保存』文案" 1
if [ -s "$R/h9.err" ]; then
    res "CGI stderr 被污染（应全量抑制）：$(head -1 "$R/h9.err")" 0
else
    res "CGI stderr 无泄漏" 1
fi
if grep -q '987654321' "$DATA/settings.conf" 2>/dev/null; then
    res "写失败却仍有内容落盘（状态矛盾）" 0
else
    res "旧设置未被破坏（失败时不留半截文件）" 1
fi
# ---- 对照组：-5 版（BLK-3 修复前）在同一场景必须既谎报又泄漏 ----
if [ -f "$LEGACY_UI/index.cgi.from-5" ]; then
    sed "s|/var/apps/openp2p|$R|g" "$LEGACY_UI/index.cgi.from-5" > "$R/ui/legacy5.cgi"
    # 关键（我第一次写错了，被本用例自己抓到）：目录 500 只挡「新建目录项」，
    # **不挡**改写已存在的文件。所以要让对照组真的失败，必须先删掉 settings.conf，
    # 逼旧版去「创建」文件；否则旧版改写现有文件成功、不报错，对照组自然复现不出泄漏。
    rm -f "$DATA/settings.conf"
    chmod 500 "$DATA"
    printf '%s' "$B" | CONTENT_LENGTH=${#B} REQUEST_METHOD=POST bash "$R/ui/legacy5.cgi" >"$R/legacy5.out" 2>"$R/legacy5.err"
    chmod 700 "$DATA"
    grep -q '设置已保存' "$R/legacy5.out" \
        && res "对照组：-5 版写失败时确实谎报『设置已保存』（证明本用例有鉴别力）" 1 \
        || res "对照组未复现旧版谎报 → 本用例无鉴别力" 0
    [ -s "$R/legacy5.err" ] \
        && res "对照组：-5 版确实泄漏裸错误到 CGI stderr（证明第二条断言有鉴别力）" 1 \
        || res "对照组未复现旧版 stderr 泄漏 → 本用例无鉴别力" 0
else
    res "对照组快照缺失 $LEGACY_UI/index.cgi.from-5（无法证明用例有鉴别力）" 0
    res "对照组快照缺失 $LEGACY_UI/index.cgi.from-5（无法证明用例有鉴别力）" 0
fi

say "H10 高级编辑保存：备份与写入必须『做了才算数』（N-B 同类）"
stage
# 情形 1：config.json 本来不存在 → 不得声称「已备份旧文件」
OUT=$(cgi "action=raw_save&rawjson=%7B%22network%22%3A%7B%22Token%22%3A123%7D%7D")
[ -f "$DATA/config.json" ] && res "config.json 确实写入" 1 || res "config.json 未写入" 0
grep -q '已备份旧文件' <<<"$OUT" \
    && res "原文件不存在却声称『已备份旧文件』（文案撒谎）" 0 \
    || res "原文件不存在时未谎称已备份" 1
[ -f "$DATA/config.json.bak" ] && res "原文件不存在却生成了 .bak（多余产物）" 0 || res "未生成多余的 .bak" 1
# 情形 2：原文件已存在 → 备份必须真生成，文案也必须说有备份
OUT=$(cgi "action=raw_save&rawjson=%7B%22network%22%3A%7B%22Token%22%3A456%7D%7D")
[ -f "$DATA/config.json.bak" ] && res "原文件存在时确实生成了 .bak" 1 || res "声称已备份但 .bak 不存在（文案撒谎）" 0
grep -q '已备份' <<<"$OUT" && res "有备份时提示已备份" 1 || res "有备份却未提示" 0
grep -q '456' "$DATA/config.json" 2>/dev/null && res "新内容确实写入 config.json" 1 || res "新内容未写入" 0
# 情形 3：目录不可写 → 不得谎报已保存，不得泄漏 stderr
chmod 500 "$DATA"
B='action=raw_save&rawjson=%7B%22network%22%3A%7B%22Token%22%3A789%7D%7D'
printf '%s' "$B" | CONTENT_LENGTH=${#B} REQUEST_METHOD=POST bash "$R/ui/index.cgi" >"$R/h10.out" 2>"$R/h10.err"
chmod 700 "$DATA"
grep -q '写入失败' "$R/h10.out" && res "raw_save 写失败时如实回报" 1 || res "raw_save 写失败却未报错" 0
grep -q '已保存' "$R/h10.out" && res "raw_save 写失败却出现『已保存』（谎报）" 0 || res "raw_save 写失败未谎报" 1
[ -s "$R/h10.err" ] && res "raw_save 泄漏 stderr：$(head -1 "$R/h10.err")" 0 || res "raw_save 无 stderr 泄漏" 1

say "H11 回调层同一纪律：设置写失败时回调必须以非零退出，不得报『安装完成/设置已更新』"
stage
# 构造写失败：把 settings.conf 变成一个**非空目录** → 数据目录本身仍可写，
# 这样 install_callback 的 fix_binary_arch（往 DATA_DIR 部署二进制）能正常通过，
# 失败只可能来自设置写入 —— 断言不会被"别的步骤先失败"蒙混过去。
mkdir -p "$DATA/settings.conf/blocker"
if [ "$(bash "$R/cmd/config_callback" >/dev/null 2>"$R/h11.err"; echo $?)" != "0" ]; then
    res "config_callback 写失败时以非零退出" 1
else
    res "config_callback 写失败仍 rc=0（谎报成功）" 0
fi
grep -q '写入失败' "$R/apps.log" && res "日志中如实记录写入失败" 1 || res "日志未记录写入失败"
[ -s "$R/h11.err" ] && res "config_callback 泄漏 stderr：$(head -1 "$R/h11.err")" 0 || res "config_callback 无 stderr 泄漏" 1
: > "$R/apps.log"
if [ "$(bash "$R/cmd/install_callback" >/dev/null 2>"$R/h11b.err"; echo $?)" != "0" ]; then
    res "install_callback 写失败时以非零退出" 1
else
    res "install_callback 写失败仍 rc=0（报『安装完成』）" 0
fi
grep -q '安装完成' "$R/apps.log" && res "写失败却记录『安装完成』（谎报）" 0 || res "写失败时未记录『安装完成』" 1
[ -s "$R/h11b.err" ] && res "install_callback 泄漏 stderr：$(head -1 "$R/h11b.err")" 0 || res "install_callback 无 stderr 泄漏" 1

say "H12 日志文件不可写时启动不得泄漏裸错误，且仍能启动（N-D）"
stage
rm -rf "$DATA/settings.conf"
printf 'token=123456789\nnode=my-nas\nsharebandwidth=10\nserverhost=api.openp2p.cn\nserverport=27183\nloglevel=1\n' > "$DATA/settings.conf"
mkdir -p "$R/ro" && chmod 500 "$R/ro"
( export LOG_FILE="$R/ro/apps.log"; bash "$R/cmd/main" start ) >/dev/null 2>"$R/h12.err"
chmod 700 "$R/ro"
if [ -s "$R/h12.err" ]; then
    res "启动时泄漏 stderr（日志不可写）：$(head -1 "$R/h12.err")" 0
else
    res "日志不可写时启动无 stderr 泄漏" 1
fi
pgrep -f "^$DATA/openp2p" >/dev/null \
    && res "日志不可写时依然成功启动（输出退回 /dev/null）" 1 \
    || res "日志不可写导致启动失败" 0
bash "$R/cmd/main" stop >/dev/null 2>&1


say "H13 保存设置写失败：不得把正在运行的应用留在停止态（P2-B）"
# 失败注入手法：把 settings.conf 换成**非空目录**（数据目录本身仍可写）。
# 这样失败只可能来自「改名到目标」这一步，不会顺带影响正在运行的应用，
# 断言不会被"应用因为目录不可写自己挂了"污染。
stage
printf 'token=123456789\nnode=my-nas\nsharebandwidth=10\nserverhost=api.openp2p.cn\nserverport=27183\nloglevel=1\n' > "$DATA/settings.conf"
bash "$R/cmd/main" start >/dev/null 2>&1; sleep 2
if pgrep -f "^$DATA/openp2p" >/dev/null; then
    rm -f "$DATA/settings.conf"; mkdir -p "$DATA/settings.conf/blocker"
    B='action=save&token=111222333&node=still-up'
    printf '%s' "$B" | CONTENT_LENGTH=${#B} REQUEST_METHOD=POST bash "$R/ui/index.cgi" >"$R/h13.out" 2>"$R/h13.err"
    grep -q '设置写入失败' "$R/h13.out" && res "写失败时如实报错" 1 || res "写失败未报错" 0
    if pgrep -f "^$DATA/openp2p" >/dev/null; then
        res "写失败后应用仍在运行（没有被无辜停掉）" 1
    else
        res "写失败却把应用停在那儿了（用户会看到『点一下保存，应用就不跑了』）" 0
    fi
    [ -s "$R/h13.err" ] && res "CGI stderr 泄漏：$(head -1 "$R/h13.err")" 0 || res "CGI stderr 无泄漏" 1
    # ---- 对照组：-6 版是「先停后写、失败不回头」→ 必须把应用留在停止态 ----
    if [ -f "$LEGACY_UI/index.cgi.from-6" ]; then
        sed "s|/var/apps/openp2p|$R|g" "$LEGACY_UI/index.cgi.from-6" > "$R/ui/legacy6.cgi"
        printf '%s' "$B" | CONTENT_LENGTH=${#B} REQUEST_METHOD=POST bash "$R/ui/legacy6.cgi" >"$R/l6.out" 2>/dev/null
        if pgrep -f "^$DATA/openp2p" >/dev/null; then
            res "对照组：-6 也未把应用停掉 → 本用例无鉴别力" 0
        else
            res "对照组：-6 确实把应用留在停止态（证明本用例有鉴别力）" 1
        fi
    else
        res "对照组快照缺失 $LEGACY_UI/index.cgi.from-6（无法证明用例有鉴别力）" 0
    fi
    pkill -f "^$DATA/openp2p" 2>/dev/null; sleep 1
    rm -rf "$DATA/settings.conf"          # 清掉注入的失败态，别污染下一个块
else
    res "前置失败：应用未启动，本用例无法执行" 0
fi

say "H14 高级编辑写失败：『先停后写』的应用必须被恢复运行（P2-B）"
stage
printf 'token=123456789\nnode=my-nas\nsharebandwidth=10\nserverhost=api.openp2p.cn\nserverport=27183\nloglevel=1\n' > "$DATA/settings.conf"
printf '{"network":{"Token":123456789}}\n' > "$DATA/config.json"
bash "$R/cmd/main" start >/dev/null 2>&1; sleep 2
if pgrep -f "^$DATA/openp2p" >/dev/null; then
    rm -f "$DATA/config.json"; mkdir -p "$DATA/config.json/blocker"
    B='action=raw_save&rawjson=%7B%22network%22%3A%7B%22Token%22%3A999%7D%7D'
    printf '%s' "$B" | CONTENT_LENGTH=${#B} REQUEST_METHOD=POST bash "$R/ui/index.cgi" >"$R/h14.out" 2>"$R/h14.err"
    grep -q '写入失败' "$R/h14.out" && res "写失败时如实报错" 1 || res "写失败未报错" 0
    grep -q '已保存' "$R/h14.out" && res "写失败却出现『已保存』（谎报）" 0 || res "写失败未谎报" 1
    # 说明：本注入（config.json 变成非空目录）会让「重启」这一步**本身**也失败
    # （cmd/main 的 ensure_token_in_conf 无法写入一个目录），所以这里不能断言"应用已运行"，
    # 而应断言**界面必须如实交代应用状态**：要么"已恢复运行"，要么"未能重新启动"。
    # 真正要防的是「静默把运行中的应用丢在停止态还什么都不说」（-6 的问题）。
    grep -q '恢复运行\|未能重新启动' "$R/h14.out" \
        && res "写失败分支如实交代了应用状态（已恢复运行 / 未能重新启动）" 1 \
        || res "写失败后只字不提交应用状态（把应用静默丢在停止态）" 0
    # ---- 对照组：-6 版「先停后写、失败不回头」→ 应用停在停止态且文案只字不提 ----
    if [ -f "$LEGACY_UI/index.cgi.from-6" ]; then
        rm -rf "$DATA/config.json"
        printf '{"network":{"Token":123456789}}\n' > "$DATA/config.json"
        bash "$R/cmd/main" start >/dev/null 2>&1; sleep 2
        sed "s|/var/apps/openp2p|$R|g" "$LEGACY_UI/index.cgi.from-6" > "$R/ui/legacy6b.cgi"
        rm -f "$DATA/config.json"; mkdir -p "$DATA/config.json/blocker"
        printf '%s' "$B" | CONTENT_LENGTH=${#B} REQUEST_METHOD=POST bash "$R/ui/legacy6b.cgi" >"$R/l6b.out" 2>/dev/null
        if pgrep -f "^$DATA/openp2p" >/dev/null; then
            res "对照组：-6 也未把应用丢在停止态 → 本用例无鉴别力" 0
        else
            res "对照组：-6 确实把应用静默丢在停止态（证明本用例有鉴别力）" 1
        fi
        grep -q '恢复运行\|未能重新启动' "$R/l6b.out" \
            && res "对照组：-6 也交代了应用状态（用例无鉴别力）" 0 \
            || res "对照组：-6 只字未提应用状态" 1
    else
        res "对照组快照缺失 $LEGACY_UI/index.cgi.from-6（无法证明用例有鉴别力）" 0
        res "对照组快照缺失 $LEGACY_UI/index.cgi.from-6（无法证明用例有鉴别力）" 0
    fi
    rm -rf "$DATA/config.json"
    [ -s "$R/h14.err" ] && res "CGI stderr 泄漏：$(head -1 "$R/h14.err")" 0 || res "CGI stderr 无泄漏" 1
    pkill -f "^$DATA/openp2p" 2>/dev/null; sleep 1
else
    res "前置失败：应用未启动，本用例无法执行" 0
fi

say "H15 数据目录不可写时，安装/升级回调不得泄漏裸命令错误（P2-A）"
stage
# ⚠️ 这一步是**用例成立的前提**：真实 fnOS 上包内二进制始终躺在 TRIM_APPDEST/bin
# （不会被搬走），而 stage 为了其它用例方便把它 `mv` 进了 DATA_DIR —— 于是
# fix_binary_arch 会走「包内无该架构二进制 → 沿用数据目录已有二进制」分支，**根本不做 cp**，
# 本用例就测了个寂寞（对照组因此复现不出泄漏，被本套用例自己的对照组抓出来）。
tar xzf "$PKG" -O app.tgz | tar xz -C "$R/target" --wildcards 'bin/openp2p_x86_64' 2>/dev/null
rm -f "$DATA/openp2p"
[ -f "$R/target/bin/openp2p_x86_64" ] \
    && res "前置成立：包内负载二进制就位（$R/target/bin）" 1 \
    || res "前置不成立：包内负载二进制缺失，本用例无效" 0
[ ! -e "$DATA/openp2p" ] \
    && res "前置成立：数据目录里没有现成二进制，逼 fix_binary_arch 真的去复制" 1 \
    || res "前置不成立：数据目录已有二进制，会被『沿用』分支短路" 0
chmod 500 "$DATA"
bash "$R/cmd/upgrade_callback" >/dev/null 2>"$R/h15.err"; rc=$?
chmod 700 "$DATA"
[ -s "$R/h15.err" ] && res "回调泄漏 stderr：$(head -1 "$R/h15.err")" 0 || res "回调无 stderr 泄漏" 1
[ "$rc" != 0 ] && res "二进制部署失败时以非零退出（rc=$rc）" 1 || res "部署失败仍 rc=0（谎报）" 0
# ---- 对照组：-6 版 common 的 cp/mv 未抑制 → 必须泄漏裸 "cp: ...Permission denied" ----
if [ -f "$LEGACY_CMD/common.from-6" ]; then
    rm -rf "$R/legacy"; mkdir -p "$R/legacy"
    cp -r "$R/cmd" "$R/legacy/cmd"
    cp "$LEGACY_CMD/common.from-6" "$R/legacy/cmd/common"; chmod +x "$R/legacy/cmd/common"
    chmod 500 "$DATA"
    bash "$R/legacy/cmd/upgrade_callback" >/dev/null 2>"$R/h15b.err"
    chmod 700 "$DATA"
    [ -s "$R/h15b.err" ] \
        && res "对照组：-6 版确实泄漏 cp/mv 裸错误（$(head -1 "$R/h15b.err")）→ 证明本用例有鉴别力" 1 \
        || res "对照组未复现泄漏 → 本用例无鉴别力" 0
else
    res "对照组快照缺失 $LEGACY_CMD/common.from-6（无法证明用例有鉴别力）" 0
fi

say "H16 含 Token 的临时文件必须与进程 umask 无关地以 0600 创建（P2-D 同类 · 本轮自查新发现）"
# 为什么这条不能用「最终 settings.conf 是 600」来证明：
#   P2-D 指出的正是「chmod 600 发生在 mv 之后」—— 最终权限没问题，
#   **创建那一刻**的临时文件却是按进程 umask（通常 0644，最坏 0666）建的。
# 手法：把 umask 设成 000（最恶劣），再用**同名函数桩**打死 mv（逼进"改名失败"分支）
#   与 rm（不许清理现场）→ 临时文件真的留在磁盘上，可以 stat 它创建时的权限位。
stage
probe_tmp(){
    local cm="$1" t
    for f in $(find "$R" -name 'settings.conf.tmp.*' 2>/dev/null); do rm -f "$f"; done
    ( umask 000
      . "$cm" 2>/dev/null
      openp2p_token=987654321
      mv(){ return 1; }        # 原子改名失败（真实的磁盘满 / 目标不可写也会走到这里）
      rm(){ return 1; }        # 不让它把证据删掉
      apply_settings_env >/dev/null 2>&1
    )
    t=$(find "$R" -name 'settings.conf.tmp.*' 2>/dev/null | head -1)
    if [ -n "$t" ]; then stat -c%a "$t" 2>/dev/null || echo 000; else echo 000; fi
}
m=$(probe_tmp "$R/cmd/common")
if [ "$m" = 000 ]; then
    res "临时文件未留在磁盘上，本用例前置不成立（无法判定创建时的权限）" 0
else
    res "用例前置成立：改名失败时临时文件确实残留（权限 $m）" 1
    [ "$m" = 600 ] \
        && res "umask=000 下临时文件仍是 0600（不以进程 umask 创建）" 1 \
        || res "umask=000 下临时文件是 $m —— 含 Token 的明文在改名成功前对组/其他用户可读" 0
fi
# ---- 对照组：-6 版 common（P2-D 修复前）用同一手法必须留下 0644/0666 的临时文件 ----
if [ -f "$LEGACY_CMD/common.from-6" ]; then
    m6=$(probe_tmp "$LEGACY_CMD/common.from-6")
    [ "$m6" != 600 ] && [ "$m6" != 000 ] \
        && res "对照组：-6 版留下的临时文件是 $m6（证明本用例有鉴别力）" 1 \
        || res "对照组未复现过宽权限（实测 $m6）→ 本用例无鉴别力（或 -6 已带该修复）" 0
else
    res "对照组快照缺失 $LEGACY_CMD/common.from-6（无法证明用例有鉴别力）" 0
fi

say "H17 日志轮转必须沿用原文件权限（同类隐患：> 重定向按进程 umask 新建文件）"
stage
probe_rotate(){
    local cm="$1" lf="$R/rot.log"
    rm -f "$lf" "${lf}.tmp"
    head -c 6000000 /dev/zero | tr '\0' 'x' > "$lf"   # 6MB，越过 5MB 阈值
    chmod 600 "$lf"
    ( umask 000; . "$cm" 2>/dev/null; LOG_FILE="$lf"; rotate_log >/dev/null 2>&1 )
    echo "$(stat -c%a "$lf" 2>/dev/null || echo 000) $(stat -c%s "$lf" 2>/dev/null || echo 0) $([ -e "${lf}.tmp" ] && echo tmp-left || echo clean)"
}
set -- $(probe_rotate "$R/cmd/common"); rm_mode=$1; rm_size=$2; rm_tmp=$3
# tail -c 2097152 之后还会追加一行"日志已轮转"，所以上限取 2097152+256；下限 2000000
[ "$rm_size" -le 2097408 ] 2>/dev/null && [ "$rm_size" -ge 2000000 ] 2>/dev/null \
    && res "轮转生效且精确：6000000 → $rm_size 字节（尾部 2MB + 一行轮转记录）" 1 \
    || res "轮转大小不符预期（$rm_size，应落在 2000000..2097408）" 0
[ "$rm_mode" = 600 ] && res "轮转后权限仍为 600（原 600 未被 umask 放宽）" 1 || res "轮转后权限变成 $rm_mode（原 600 被放宽）" 0
[ "$rm_tmp" = clean ] && res "轮转不留 ${R##*/}/rot.log.tmp 残渣" 1 || res "轮转后残留 .tmp 文件" 0
# ---- 对照组：-6 版在同一手法下必须把 600 变成 666（证明用例有鉴别力） ----
if [ -f "$LEGACY_CMD/common.from-6" ]; then
    set -- $(probe_rotate "$LEGACY_CMD/common.from-6"); l6_mode=$1
    [ "$l6_mode" != 600 ] \
        && res "对照组：-6 版轮转后权限是 $l6_mode（证明本用例有鉴别力）" 1 \
        || res "对照组未复现权限放宽（实测 $l6_mode）→ 本用例无鉴别力" 0
else
    res "对照组快照缺失 $LEGACY_CMD/common.from-6" 0
fi

say "H18 打错的 Token 不得被原样回显进日志（qa 第五轮 N5-1，日志是 0644）"
stage
# 探针值：故意含字母，必定触发 safe_num 失败；取值要"独特"到不会与其它日志文本撞车
probe_token_echo() {   # $1 = cmd/common 路径；回显日志里探针值出现次数
    local cm="$1" d="$R/echo.$$" val="abc8proxy9zz"
    rm -rf "$d"; mkdir -p "$d"
    ( OPENP2P_APPROOT="$d" TRIM_APPNAME=openp2p TRIM_PKGVAR="$d/var" \
      TRIM_APPDEST="$d/target" LOG_FILE="$d/app.log"
      . "$cm" 2>/dev/null
      openp2p_token="$val"
      apply_settings_env >/dev/null 2>&1 )
    grep -c "$val" "$d/app.log" 2>/dev/null || true
}
n=$(probe_token_echo "$R/cmd/common"); n=${n:-0}
[ "$n" = 0 ] && res "非法 Token 未出现在日志里（0 次）" 1 \
             || res "非法 Token 被原样写进日志（$n 次，日志文件是 0644）" 0
grep -q 'Token 只接受数字' "$R"/echo.*/app.log 2>/dev/null \
    && res "前置成立：确实走进了 Token 校验分支（日志有忽略提示）" 1 \
    || res "前置不成立：日志里没有 Token 校验记录，本用例可能是假绿" 0
# ---- 对照组：把回显行为机械变异回来（= 修复前的那一行），必须复现泄漏 ----
# T23 教训：机械变异后**必须过一遍 bash -n**。我这版第一稿的 sed 把行尾的 `; fi` 一起
# 吞掉了，变异体自己就是语法错误、source 不进来 → 日志当然是空的 → 表现为
# "对照组没复现"（看起来像用例没鉴别力），实际是**变异体坏了**。
cp "$R/cmd/common" "$R/cmd/common.echo"
sed -i 's|warn_msg "⚠️ Token 只接受数字.*|warn_msg "⚠️ Token 只接受数字，已忽略输入：「${v}」"; fi|' "$R/cmd/common.echo"
grep -q '已忽略输入：「\${v}」"; fi' "$R/cmd/common.echo" \
    && res "变异已生效（对照组确实恢复了回显原值）" 1 \
    || res "变异未生效，本对照组无效" 0
bash -n "$R/cmd/common.echo" 2>/dev/null \
    && res "变异体语法合法（否则对照组失败会被误读成『无鉴别力』）" 1 \
    || res "变异体语法损坏 → 本对照组结论无效" 0
n=$(probe_token_echo "$R/cmd/common.echo"); n=${n:-0}
[ "$n" != 0 ] && res "对照组：回显写法下 Token 确实写进日志（$n 次）→ 证明本用例有鉴别力" 1 \
              || res "对照组未复现泄漏 → 本用例无鉴别力" 0

say "H19 冷启动写 config.json 必须一创建就是 0600（qa 第五轮 N5-2）"
# 手法（与 H16 同源）：umask 设 000，并把 `chmod` 打成失败的函数桩 ——
# 这样"事后 chmod 600"这条路被堵死，文件留在磁盘上的就是**创建那一刻**的权限。
# 只测"最终权限是 600"是测不出这个缺陷的：旧写法最终也是 600，问题在那个窗口。
probe_tok_perm() {   # $1 = cmd/common 路径；回显 config.json 的创建时权限
    local cm="$1" d="$R/tp.$$"
    rm -rf "$d"; mkdir -p "$d"
    ( umask 000
      OPENP2P_APPROOT="$d" TRIM_APPNAME=openp2p TRIM_PKGVAR="$d/var" \
      TRIM_APPDEST="$d/target" LOG_FILE="$d/app.log"
      . "$cm" 2>/dev/null
      chmod() { return 1; }
      ensure_token_in_conf 123456789 >/dev/null 2>&1 )
    stat -c%a "$d/shares/openp2p/config.json" 2>/dev/null || true
}
m=$(probe_tok_perm "$R/cmd/common"); m=${m:-000}
[ -f "$R"/tp.*/shares/openp2p/config.json ] \
    && res "前置成立：冷启动路径确实写了 config.json" 1 \
    || res "前置不成立：没写出 config.json，本用例无效" 0
[ "$m" = 600 ] && res "umask=000 下新写的 config.json 创建时即 600" 1 \
               || res "config.json 创建时权限受进程 umask 影响（实测 $m，应 600）" 0
if [ -f "$LEGACY_CMD/common.from-6" ]; then
    m=$(probe_tok_perm "$LEGACY_CMD/common.from-6"); m=${m:-000}
    [ "$m" != 600 ] && [ "$m" != 000 ] && res "对照组：-6 版写出的 config.json 是 $m（存在宽权限窗口）" 1 \
                    || res "对照组未复现宽权限（实测 $m）→ 本用例鉴别力不足" 0
else
    res "对照组快照缺失" 0
fi

say "H20 安装/升级失败提示不得截断 fnOS 的进度文件（qa 第五轮 N5-3）"
stage
pf="$R/progress.txt"
run_cb_with_fail() {   # $1 = install_callback 路径；$2 = 进度文件
    : > "$2"; printf 'fnOS 框架写的既有进度内容\n' > "$2"
    mkdir -p "$DATA/settings.conf"; : > "$DATA/settings.conf/x"   # 让设置写入必定失败
    TRIM_TEMP_LOGFILE="$2" bash "$1" >/dev/null 2>&1
    rm -rf "$DATA/settings.conf"
}
run_cb_with_fail "$R/cmd/install_callback" "$pf"
grep -q 'fnOS 框架写的既有进度内容' "$pf" \
    && res "失败提示是追加的，框架既有进度没被截断" 1 \
    || res "框架写进进度文件的内容被 > 清掉了（用户只会看到我们那一行）" 0
[ -s "$pf" ] && res "失败提示确实写进了进度文件（非空）" 1 || res "失败提示没写进进度文件" 0
# ---- 对照组：把 >> 变异回 >（= 修复前的一字符之差），必须复现截断 ----
cp "$R/cmd/install_callback" "$R/cmd/install_callback.trunc"
sed -i 's|2>/dev/null >> "${TRIM_TEMP_LOGFILE|> "${TRIM_TEMP_LOGFILE|' "$R/cmd/install_callback.trunc"
grep -q '^ *> "${TRIM_TEMP_LOGFILE' "$R/cmd/install_callback.trunc" \
    && res "变异已生效（对照组恢复成 > 截断写法）" 1 \
    || res "变异未生效，本对照组无效" 0
run_cb_with_fail "$R/cmd/install_callback.trunc" "$pf"
grep -q 'fnOS 框架写的既有进度内容' "$pf" \
    && res "对照组未复现截断 → 本用例无鉴别力" 0 \
    || res "对照组：> 写法确实清掉了框架内容 → 证明本用例有鉴别力" 1

say "H21 数据目录结构性 0700 + 保存失败文案按实测状态推导（qa 第五轮真机发现 / N5-4）"
stage
d="$R/dd.$$"; rm -rf "$d"; mkdir -p "$d"
( umask 022
  OPENP2P_APPROOT="$d" TRIM_APPNAME=openp2p TRIM_PKGVAR="$d/var" \
  TRIM_APPDEST="$d/target" LOG_FILE="$d/app.log"
  . "$R/cmd/common" 2>/dev/null
  ensure_data_dir >/dev/null 2>&1 )
dm=$(stat -c%a "$d/shares/openp2p" 2>/dev/null || echo 000)
[ "$dm" = 700 ] && res "0755 的数据目录被收紧到 700（组/其他人权限被摘掉）" 1 \
                || res "数据目录权限是 $dm，未达结构性保护" 0
# 反方向断言（同样重要）：**只收紧、不放开**。运维把目录设成 0500 时不许被改回来。
d3="$R/dd3.$$"; rm -rf "$d3"; mkdir -p "$d3"
( umask 022
  OPENP2P_APPROOT="$d3" TRIM_APPNAME=openp2p TRIM_PKGVAR="$d3/var" \
  TRIM_APPDEST="$d3/target" LOG_FILE="$d3/app.log"
  . "$R/cmd/common" 2>/dev/null
  mkdir -p "$d3/shares/openp2p"; chmod 500 "$d3/shares/openp2p"
  ensure_data_dir >/dev/null 2>&1 )
dm3=$(stat -c%a "$d3/shares/openp2p" 2>/dev/null || echo 000)
[ "$dm3" = 500 ] && res "运维设的只读目录 0500 **未被**改成可写（只收紧不放开）" 1 \
                 || res "只读目录被擅自放开成 $dm3 —— 推翻了运维意图" 0
if [ -f "$LEGACY_CMD/common.from-6" ]; then
    d2="$R/dd6.$$"; rm -rf "$d2"; mkdir -p "$d2"
    ( umask 022
      OPENP2P_APPROOT="$d2" TRIM_APPNAME=openp2p TRIM_PKGVAR="$d2/var" \
      TRIM_APPDEST="$d2/target" LOG_FILE="$d2/app.log"
      . "$LEGACY_CMD/common.from-6" 2>/dev/null
      mkdir -p "$DATA_DIR" 2>/dev/null )
    dm6=$(stat -c%a "$d2/shares/openp2p" 2>/dev/null || echo 000)
    [ "$dm6" != 700 ] && res "对照组：-6 版建出的数据目录是 $dm6（无结构性保护）" 1 \
                      || res "对照组也是 700，本用例鉴别力不足" 0
fi
# 文案按状态推导：应用**没在跑** + 写失败 → 必须说"停止状态"，不许出现"仍在运行"
body='action=save&token=111222&node=fnos&sharebandwidth=10&serverhost=api.openp2p.cn&serverport=27183&loglevel=1'
mkdir -p "$DATA/settings.conf"; : > "$DATA/settings.conf/x"
out=$(printf '%s' "$body" | CONTENT_LENGTH=${#body} REQUEST_METHOD=POST bash "$R/ui/index.cgi" 2>"$R/h21.err")
rm -rf "$DATA/settings.conf"
echo "$out" | grep -q '写入失败' && res "写失败时如实报错" 1 || res "写失败时未如实报错" 0
echo "$out" | grep -q '停止状态' && res "未运行时文案标注『当前为停止状态』（按实测推导）" 1 \
                                 || res "未运行时文案没有交代真实状态" 0
echo "$out" | grep -q '仍在运行' && res "未运行却声称『仍在运行』（硬编码的谎话）" 0 \
                                 || res "没有撒谎：未运行时不说『仍在运行』" 1

pkill -f "^$DATA/openp2p" 2>/dev/null
echo
echo "=========== 块 H 汇总：PASS=$P  FAIL=$F ==========="
[ "$F" = 0 ] || exit 1
