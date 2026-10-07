# testcases.md · fnOS openp2p fpk 测试用例矩阵

- **run_id**: 20260930-openp2p-fpk
- **来源**：`brief.md`（R1–R8）、`api.md`（I1–I5、CLI/校验/架构契约）
- **门禁**：G3 —— P0/P1 全部通过；每条缺陷须可独立复现

## 测试环境约定

```bash
export APPROOT=/tmp/t/openp2p                       # 沙箱根，等价 /var/apps/openp2p
export OPENP2P_APPROOT="$APPROOT"                   # api.md §2 允许覆写，供测试
export APPDEST="$APPROOT/target"
export PKGVAR="$APPROOT/var"
export DATA_DIR="$APPROOT/shares/openp2p"
export BIN="$DATA_DIR/openp2p"
export CONF="$DATA_DIR/config.json"
export SETTINGS="$DATA_DIR/settings.conf"
export PID_FILE="$PKGVAR/app.pid"
export LOG_FILE=/var/log/apps/openp2p.log
export PKG=dist/openp2p_3.25.11-1_all.fpk
```

通用准备/清理（下称 `#PREP` / `#CLEAN`）：

```bash
#PREP:  rm -rf "$APPROOT" && mkdir -p "$APPROOT" "$PKGVAR" \
        && tar xzf "$PKG" -C "$APPROOT" && tar xzf "$APPDEST/app.tgz" -C "$APPDEST"
#CLEAN: "$APPDEST/cmd/main" stop; rm -rf "$APPROOT"
```

---

## 用例矩阵

| ID | 优先级 | 覆盖 | 前置条件 | 操作步骤（命令） | 预期结果 |
|---|---|---|---|---|---|
| TC-01 | P0 | R1, I1 | `#PREP`；已配合法 Token（`echo 'token=12345678' > $SETTINGS`） | `"$APPDEST/cmd/main" start; echo "rc=$?"; "$APPDEST/cmd/main" status; echo "rc=$?"` 然后 `sleep 5`；`ps -o pid,ppid,cmd -p "$(cat $PID_FILE)"`；`ls -l /proc/$(cat $PID_FILE)/exe` | `start` rc=0；`status` rc=0；5 秒后 PID 仍存活（常驻）；`/proc/<pid>/exe` 指向 **`$DATA_DIR/openp2p`**（不是 `$APPDEST/bin/*`，满足 I1） |
| TC-02 | P0 | R1, CLI 契约 | `#PREP`，未启动 | `"$APPDEST/cmd/main" status; echo "rc=$?"` 再 `"$APPDEST/cmd/main" bogus-arg; echo "rc=$?"` | 未运行时 `status` **rc=3**；未知参数 rc=1 且 stdout/stderr 打印 Usage 文本；两命令均不产生进程 |
| TC-03 | P0 | I2 | 已 `start` 成功一次（Token 已配） | `ls -l "$CONF"; ls -l "$DATA_DIR/log"; find "$APPDEST" -name config.json` | `$DATA_DIR/config.json` 存在且 mtime 为运行后更新；`$DATA_DIR/log/` 存在；`find "$APPDEST" -name config.json` **无输出**（config.json 不得出现在 APPDEST） |
| TC-04 | P0 | R2 | `#PREP`；先 `start` 一次 | 模拟界面保存：`OPENP2P_NODE=mynas-01 OPENP2P_SHAREBANDWIDTH=50 "$APPDEST/cmd/config_callback"; "$APPDEST/cmd/main" stop; "$APPDEST/cmd/main" start; sleep 3`；`cat "$SETTINGS"`；`ps -o cmd= -p "$(cat $PID_FILE)"` | `config_callback` rc=0；`$SETTINGS` 内含 `node=mynas-01`、`sharebandwidth=50`；重启后进程命令行 flags 仍为 `-node mynas-01 -sharebandwidth 50`（设置生效且**重启不丢**） |
| TC-05 | P0 | R2, I4 | `#PREP`；`echo 'token=12345678' > $SETTINGS` | `"$APPDEST/cmd/config_callback"; stat -c '%a %U' "$SETTINGS"; "$APPDEST/cmd/main" stop; "$APPDEST/cmd/main" start`；`cat "$SETTINGS"` | `settings.conf` 权限 **600**；重启后 Token 与其余字段仍在，未被子进程/回调覆盖为空 |
| TC-06 | P0 | R3, I3 | 已配 Token + `apps[]`：`echo '{"network":{"Token":12345678},"apps":[{"name":"web","protocol":"tcp","dstPort":8080}]}' > $CONF`；记录 `md5sum "$SETTINGS" "$CONF"` | 覆盖安装模拟：`tar xzf "$PKG" -C "$APPROOT"`（覆盖 `$APPDEST`）→ `"$APPDEST/cmd/upgrade_init"; "$APPDEST/cmd/upgrade_callback"; echo "rc=$?"`；再次 `md5sum "$SETTINGS" "$CONF"` | 两个回调 rc=0；`settings.conf` 与 `config.json` 的 md5 **与升级前完全一致**；`config.json` 中 `apps[]` 与 Token 均未丢失（I3） |
| TC-07 | P0 | R3, R5 | `#PREP`，已配 Token + `apps[]`；`rm -f "$DATA_DIR/openp2p"`（模拟包内二进制已被清空） | 修复重装：`"$APPDEST/cmd/install_callback"; echo "rc=$?"`；`ls -l "$BIN"`；`cat "$CONF"` | rc=0；`$BIN` 重新落地在 `$DATA_DIR`；原 `config.json`（Token + `apps[]`）**未被覆盖/重建为最小配置** |
| TC-08 | P0 | R5 | `#PREP`；`uname -m` 可 mock（`PATH` 前置桩脚本） | 对 4 种架构分别执行：`(uname() { echo x86_64; }; export -f uname; "$APPDEST/cmd/install_callback")`，依次换成 `aarch64` / `armv7l` / `i686`；每次 `"$BIN" -v`；`md5sum "$BIN"` | 4 次 rc=0；`$BIN` 分别等于 `openp2p_x86_64` / `_aarch64` / `_armv7` / `_i386` 的 md5；`"$BIN" -v` 均能打印版本（落盘前自检通过） |
| TC-09 | P0 | R5 | `$DATA_DIR/openp2p` 已有可用二进制；包内 **无**匹配架构（mock `uname -m` 为 `riscv64`） | `(uname() { echo riscv64; }; export -f uname; "$APPDEST/cmd/install_callback"; echo "rc=$?")`；`md5sum "$BIN"` | rc=0；`$BIN` 沿用旧二进制（md5 不变），**不删除、不覆盖**；日志中有"沿用已有二进制"记录 |
| TC-10 | P0 | R5, R4 | `$DATA_DIR/openp2p` 不存在；包内无匹配架构（mock `uname -m` = `riscv64`） | `rm -f "$BIN"; (uname() { echo riscv64; }; export -f uname; "$APPDEST/cmd/install_callback"; echo "rc=$?")`；`"$APPDEST/cmd/main" start; echo "rc=$?"`；`grep -i arch "$LOG_FILE"` | 回调不因缺二进制而崩溃；**不启动任何进程**；日志含明确的"无可用二进制/架构不支持"错误行；`status` rc=3 |
| TC-11 | P0 | R5, R1 | `#PREP` | 损坏二进制：`head -c 1024 "$DATA_DIR/openp2p" > /tmp/trunc && cp "$DATA_DIR/openp2p" /tmp/good.bin && cp /tmp/trunc "$BIN" && chmod +x "$BIN"`；`"$APPDEST/cmd/main" start; echo "rc=$?"`；`ps aux \| grep -c '[o]penp2p'` | `start` **rc=1**；无进程残留；日志/输出含"**架构不匹配或文件损坏**"级别提示（非静默）；`$BIN` 内容仍为截断文件（未写入半截新文件） |
| TC-12 | P0 | R5 | `#PREP`，已装好可用的 `$BIN`；包内候选二进制损坏（`truncate -s 1024 "$APPDEST/bin/openp2p_$(arch)"`） | `"$APPDEST/cmd/install_callback"; echo "rc=$?"`；`"$BIN" -v`；`md5sum "$BIN"` | 候选二进制 `-v` 自检失败 → **不落盘替换**；`$BIN` 仍为原可用二进制（md5 不变），服务仍可 `start` |
| TC-13 | P0 | I5 | 已 `start` 成功（Token=12345678） | `tr '\0' ' ' < /proc/$(cat $PID_FILE)/cmdline; echo`；`ps -ww -o args= -p "$(cat $PID_FILE)"`；`pgrep -af openp2p` | 命令行含 `-node/-sharebandwidth/-serverhost/-serverport/-loglevel/-installpath`，**不含 `-token` 也不含 Token 数值**（I5）；`config.json` 内 Token 已由 `ensure_token_in_conf()` 写入 |
| TC-14 | P1 | I5, I2 | 已 `start` 成功；`grep -rn "12345678" "$LOG_FILE" "$DATA_DIR"` 前先记录 | `stat -c '%a' "$CONF" "$SETTINGS"`；`grep -rn '12345678' "$LOG_FILE" "$DATA_DIR/log" 2>/dev/null; echo "hits=$?"`；`grep -rn '12345678' "$DATA_DIR" --include='*' -l` | `config.json` 与 `settings.conf` 权限均为 **600**；日志文件中 **0 处** Token 明文（`hits=1`，即未匹配）；Token 仅出现在 `config.json` |
| TC-15 | P1 | R4, CLI 契约 | `#PREP`；**无** `settings.conf` 且 `config.json` 无 Token | `"$APPDEST/cmd/main" start; echo "rc=$?"`；`"$APPDEST/cmd/main" status; echo "rc=$?"`；`tail -20 "$LOG_FILE"` | `start` **rc=0**（优雅跳过，非报错）；`status` **rc=3**（进程未起，不空转）；日志/`TRIM_TEMP_LOGFILE` 有用户可见提示"未配置 Token，跳过启动" |
| TC-16 | P1 | I4 | `config.json` 内有旧 Token；`settings.conf` 存在但 **token 为空**（用户在界面清空） | `echo '{"network":{"Token":12345678}}' > "$CONF"`；`printf 'token=\nnode=x\n' > "$SETTINGS"`；`"$APPDEST/cmd/main" start; echo "rc=$?"`；`"$APPDEST/cmd/main" status; echo "rc=$?"` | `settings.conf` 存在即为**唯一权威**，**不回退**读 `config.json` 旧 Token → 进程**未启动**，`status` rc=3（禁止出现"清空了还在跑"） |
| TC-17 | P1 | R7 | 已配 Token；服务未运行 | `"$APPDEST/cmd/main" start & "$APPDEST/cmd/main" start & "$APPDEST/cmd/main" start & wait`；`sleep 3`；`pgrep -c -f 'openp2p'`；`cat "$PID_FILE"` | 三次 `start` 全部 **rc=0**（幂等）；实际只有 **1 个** openp2p 进程；`app.pid` 唯一且与 `pgrep` 结果一致 |
| TC-18 | P1 | R6 | 服务运行中 | `"$APPDEST/cmd/main" stop; echo "rc=$?"`；`pgrep -af openp2p; echo "pgrep_rc=$?"`；`"$APPDEST/cmd/main" status; echo "rc=$?"` | `stop` rc=0；无任何 openp2p 进程残留（`pgrep` 无输出）；`status` rc=3；再次 `stop` 仍 rc=0（"本来就没运行"） |
| TC-19 | P1 | R6, R3 | 服务运行中，`$DATA_DIR` 内有 `config.json` / `settings.conf` / `log/` | `"$APPDEST/cmd/uninstall_init"; echo "rc=$?"`；`pgrep -af openp2p; echo "rc=$?"`；`ls -l "$CONF" "$SETTINGS" "$DATA_DIR/log"` | `uninstall_init` rc=0；进程已停止；**用户数据全部保留**（`config.json`、`settings.conf`、`log/` 仍存在，md5 不变）——卸载不删数据 |
| TC-20 | P2 | R6 | 同 TC-19，且走"删除数据"分支 | `"$APPDEST/cmd/uninstall_callback"; echo "rc=$?"`；`"$APPDEST/cmd/uninstall_init"; echo "rc=$?"`；`ls -la "$DATA_DIR" 2>&1; ls -la "$APPROOT" 2>&1`；`pgrep -af openp2p` | 选择删除数据时：`$DATA_DIR`（二进制/`config.json`/`settings.conf`/`log/`）被清理，`$APPROOT` 下无残留数据目录；无进程残留；两个回调 rc=0 |
| TC-21 | P2 | R8 | 服务运行过（含一次异常退出） | `ls -l "$LOG_FILE"`；`tail -50 "$LOG_FILE"`；`grep -c '12345678' "$LOG_FILE"` | `$LOG_FILE` 存在且非空、可读；含启动/停止/参数生效等可诊断信息；Token 出现次数为 **0** |
| TC-22 | P1 | 校验契约, R4 | `#PREP`，无有效配置 | 非法 token/node：`OPENP2P_TOKEN='12ab34' "$APPDEST/cmd/config_callback"; echo "rc=$?"`；`OPENP2P_NODE='bad name!*' "$APPDEST/cmd/config_callback"; echo "rc=$?"`；`cat "$SETTINGS"`；`"$APPDEST/cmd/main" status; echo "rc=$?"` | 非法值**被拒绝**：token 留空且不启动（`status` rc=3）；node 回退为 NAS 主机名或 `fnos-nas`；非法值**未**写入 `settings.conf`、**未**传给 openp2p；`TRIM_TEMP_LOGFILE` 与 `$LOG_FILE` 有用户可见拒绝提示（非静默） |
| TC-23 | P1 | 校验契约 | `#PREP` | 越界值：`OPENP2P_SHAREBANDWIDTH=100001`、`OPENP2P_SERVERPORT=0`、`OPENP2P_SERVERPORT=65536`、`OPENP2P_LOGLEVEL=9` 分别 `"$APPDEST/cmd/config_callback"`；`cat "$SETTINGS"` | 全部被拒绝并回退默认值：sharebandwidth→`10`、serverport→`27183`、loglevel→`1`；无越界值写入配置；每次拒绝均有日志提示；脚本不因非法数值报错退出（rc=0） |
| TC-24 | P0 | 校验契约, I5 | `#PREP`；先 `touch /tmp/inject_marker` 并记录 `md5sum` | 命令注入尝试：`OPENP2P_TOKEN='12345678; rm -rf /tmp/inject_marker' "$APPDEST/cmd/config_callback"`；`OPENP2P_NODE='$(touch /tmp/pwned)' "$APPDEST/cmd/config_callback"`；`OPENP2P_SERVERHOST='api.openp2p.cn`id`' "$APPDEST/cmd/config_callback"`；`ls /tmp/pwned 2>&1; ls -l /tmp/inject_marker` | 三次均不执行任何 shell 片段：`/tmp/inject_marker` 仍存在（md5 不变）、`/tmp/pwned` **不存在**；字段被判非法并回退（serverhost→`api.openp2p.cn`）；无 `id`/`rm` 等命令输出；注入字符串**未**出现在任何配置或日志中 |
| TC-25 | P1 | R1, R7, CLI 契约 | `#PREP`；制造脏 PID：`echo 999999 > "$PID_FILE"`（进程不存在）；另备 `echo $$ > "$PID_FILE"`（指向无关存活进程） | `"$APPDEST/cmd/main" status; echo "rc=$?"`；`"$APPDEST/cmd/main" stop; echo "rc=$?"`；`"$APPDEST/cmd/main" start; echo "rc=$?"`；`cat "$PID_FILE"`；`ps -p $(cat "$PID_FILE") -o cmd=` | 脏 PID 不被误判为运行中：`status` rc=3；`stop` rc=0 且**不 kill 无关进程**（`$$` 对应的 shell 仍存活）；`start` rc=0 并重写 `app.pid` 为真实新 PID |
| TC-26 | P2 | 包结构契约, R5 | 有 `$PKG`（未解包） | `tar tzf "$PKG" \| sort`；`md5sum "$(tar xzf "$PKG" -O app.tgz > /tmp/app.tgz; echo /tmp/app.tgz)"`；`grep -i checksum <(tar xzf "$PKG" -O manifest)`；`tar xzf "$PKG" -O ICON.PNG \| file -`；`tar xzf "$PKG" -O ICON_256.PNG \| file -` | 包内文件齐全（`manifest`/图标/`config/`/`cmd/` 10 个脚本/`wizard/`/`app.tgz`）；`manifest.checksum == md5(app.tgz)`；`ICON.PNG` 为 **64×64**、`ICON_256.PNG` 为 **256×256**，均 ≤1024 KB；`app.tgz` 内 `bin/openp2p_{x86_64,aarch64,armv7,i386}` 四架构齐备 |

---

## 覆盖对照

| 需求/不变量 | 用例 |
|---|---|
| R1 启动常驻 + status 正确 | TC-01, TC-02, TC-11, TC-25 |
| R2 设置生效、重启不丢 | TC-04, TC-05 |
| R3 升级/重装不丢配置 | TC-06, TC-07, TC-19 |
| R4 未配 Token 不空转 | TC-10, TC-15, TC-22 |
| R5 四架构 + 装错不瞎跑 | TC-07, TC-08, TC-09, TC-10, TC-11, TC-12, TC-26 |
| R6 停止/卸载无残留 | TC-18, TC-19, TC-20 |
| R7 重复启动幂等 | TC-17, TC-25 |
| R8 日志可查 | TC-21 |
| I1 二进制在 DATA_DIR | TC-01 |
| I2 config.json 只在 DATA_DIR | TC-03, TC-14 |
| I3 升级不覆盖配置 | TC-06 |
| I4 settings.conf 权威 | TC-05, TC-16 |
| I5 Token 不入命令行 | TC-13, TC-14, TC-24 |

## 异常路径清单（非 happy path 自查）

非法输入 TC-22 ｜ 越界值 TC-23 ｜ 命令注入 TC-24 ｜ 脏 pid 文件 TC-25 ｜ 损坏二进制 TC-11、TC-12 ｜
重复启动 TC-17 ｜ 未配 Token TC-15、TC-16 ｜ 卸载保留数据 TC-19 / 删除数据 TC-20 ｜
未知子命令 TC-02 ｜ 无匹配架构 TC-09、TC-10 ｜ 日志泄密 TC-14、TC-21


---

## 第四轮新增用例（产物 `3.25.11-6`）

> 触发来源：独立 QA 对 `-5` 的第三轮复核（BLK-1/2/3、N-B/N-D/N-E）。
> 遵循一条硬规则：**每个新断言都必须配一个「旧版本必须失败」的对照组**，否则 PASS 不计分。

### 块 H 追加（界面 / 回调层）

| 用例 | 断言 | 对照组（必须失败/被拒） |
|---|---|---|
| **H2（修正）** | 降级分支替换**真的生效**（`cmd/common` 2 处、`cmd/main` 1 处，逐处断言），且不泄漏 `command not found` | `qa/legacy-ui/index.cgi.from-3` 在同场景**必须**泄漏 |
| **H6（追加）** | `stop` 失败时不得谎报「已停止」 | `index.cgi.from-2` 的 stop 分支无条件喊「🛑 应用已停止」→ 必须复现谎报 |
| **H9** | 保存设置写失败：如实报错、不出现「已保存」、CGI stderr 零污染、**旧设置不被破坏**（不留半截文件） | `index.cgi.from-5` 必须**既谎报又泄漏** |
| **H10** | `raw_save`：无原文件时不得声称「已备份旧文件」；有原文件时 `.bak` 必须真生成；写失败时不得报「已保存」、不得泄漏 stderr | （同源断言，`-5`/`-3` 的同类文案问题见 §BLK-3） |
| **H11** | `config_callback` / `install_callback` 在设置写失败时必须**非零退出**、不得记录「安装完成/设置已更新」、不得泄漏 stderr（构造手法：把 `settings.conf` 变成非空目录，使数据目录本身仍可写，失败只可能来自设置写入） | 旧版无条件 `exit 0` 并报成功 |
| **H12** | 日志文件不可写时 `start` 不得泄漏裸错误，**且仍能启动成功**（`rc=0`） | `-5` 会泄漏（`repro.log` R6 描述的是同一断言） |

### 新增独立复现集 `qa/repro.sh`（不依赖测试框架，任何人都能跑）

| 项 | 断言 | 对照组 |
|---|---|---|
| **R1** | 四种重定向写法的泄漏与否（`2>/dev/null` 位置决定一切） | 自身即对照（旧写法必须泄漏） |
| **R2a/R2b** | 产品代码无「目标文件在 `2>/dev/null` 之前」的写法（同行 + 跨行组两种形态） | — |
| **R2c** | `log_msg/warn_msg` 在日志不可写时零泄漏 | `-4` 必须泄漏（实测 299 字节） |
| **R3** | 界面保存写失败的三条纪律 | `-5` 必须谎报 + 泄漏 |
| **R4** | `find_all_pids` 拒绝 `exec -a <BIN> sleep` 伪装（BIN 路径真实存在，排除"因 BIN 不存在才被拒"） | `-4` 必须认领 |
| **R5** | 数据目录为符号链接时 `is_our_pid`=TRUE（真机根因 B11） | `-1` 必须为 FALSE |
| **R6** | 日志不可写时 `start` 零泄漏且 `rc=0` | — |

> 用例的**前置条件本身也要断言**（教训 T11/T19）：例如 H2 必须先断言替换真的命中，"
> 否则「无泄漏」可能只是「根本没走到那个分支」造成的假绿。

## 第五轮新增用例（产物 `3.25.11-7`）

针对独立 QA 对 `-6` 提的 P2-A / P2-B / P2-D 三条，补三条**带对照组**的回归用例
（P2-C 是"索引自身可复算性"问题，属元层面，已由 `qa/make-index.py` 从根上重构，见 §证据索引）。

### 块 H 追加（回调层 / 界面层）

| 用例 | 断言 | 对照组（必须失败/被拒） |
|---|---|---|
| **H13** | `save` 写设置**失败**时，运行中的应用**必须仍在运行**（P2-B：新实现「先写盘、确认写好再动应用」），文案必须交代"应用未被改动" | `qa/legacy-ui/index.cgi.from-6` 在同场景必须**把应用丢在停止态**且不提 |
| **H14** | `raw_save`（必须先停后写）写失败时**必须恢复运行**，并在文案中如实交代当前状态 | `-6` 停完就不管了 → 服务停着、用户不知情 |
| **H15** | 数据目录不可写时，`install_callback` / `upgrade_callback` 的 `fix_binary_arch` **零字节泄漏**（`cp` / `mv` / `rm` 的 stderr 全部抑制） | `qa/legacy-cmd/common.from-6` 必须泄漏 `cp: ... Permission denied`（实测 96 字节） |
| **H16** | 含 Token 的临时文件与**进程 umask 无关**地以 0600 创建（把 umask 设 000 也不能放宽；`chmod 600` 落在 `mv` **之后**不算修好） | `common.from-6` 在 umask=000 下必须留下 **666** 的临时文件（手法见下） |
| **H17** | 日志轮转后**沿用原文件权限**（600 不能被 `>` 重定向放宽）、大小落在尾部 2MB 区间、无 `.tmp` 残留 | `common.from-6` 轮转后必须变成 **666** |

**H16 的构造手法（值得复用）**：把 `umask` 设成 `000`，再用**同名 shell 函数桩**接管
`mv`（逼进"原子改名失败"分支）与 `rm`（不许它清理现场）——这样临时文件会**真的留在磁盘上**，
于是可以直接 `stat` 到它**创建那一刻**的权限位。
只断言"最终 `settings.conf` 是 600"是**测不出这个缺陷的**：P2-D 指出的恰恰是"最终没问题、中间有问题"。

### 本轮新增测试纪律（登记进 bugs.md 的 T 系列）

| # | 教训 |
|---|---|
| **T20** | 沙箱 `stage()` 必须先 `chmod -R u+rwX` 再 `rm -rf`。上轮因为没做，只读目录（`chmod 500`）残留污染了下一个块的现场，导致 H4/H5 **误报 FAIL**——"测试自己的卫生问题"会被读成"产品缺陷"。 |
| **T21** | 用例的前置条件必须与产品代码的**实际分支**对齐：H15 首版把负载二进制 `mv` 进了数据目录，使 `fix_binary_arch` 走"已存在 → 沿用"分支，根本没执行到 `cp`——**测了个寂寞还显示 PASS**。修正为先让目标路径不存在，并断言"确实走了拷贝分支"。 |
| **T22** | 「统一纪律」必须靠**枚举**落实，不能靠记忆：先写出纪律的判据（本轮 = "用 `>` / `cat >` 新建文件的每一处"），用一条命令列出全部命中点逐个改，改完反向 grep 确认零命中。凭印象"我觉得都改过了"已经连错三次（N-B → P2-A → P2-D 同类）。 |
| **T23** | **机械变异之后必须过一遍 `bash -n`**：H18 第一稿的 sed 把行尾的 `; fi` 一起吞了，变异体自己语法损坏（source 不进来）→ 日志当然是空的 → 表现为"对照组没复现"，看起来像用例没鉴别力，**实际是变异体坏了**。现在每个变异体都要额外断言"语法合法"。 |

## 第七轮新增用例（产物 `3.25.11-8`，针对 qa 第五轮的 N5-1~N5-6）

| 用例 | 断言 | 对照组（必须失败/被拒） |
|---|---|---|
| **H18** | 打错的 Token **不得**被原样回显进日志（日志是 0644，任何本机用户可读） | 把回显行为机械变异回来 → 必须复现泄漏；**并断言变异体语法合法**（T23） |
| **H19** | 冷启动写 `config.json` **创建那一刻**就是 0600（手法：umask=000 + 把 `chmod` 打成失败桩，堵死"事后收紧"这条路） | 旧写法在 chmod 桩下暴露"创建时权限受 umask 影响" |
| **H20** | 安装/升级的失败提示必须是**追加**，不得截断 fnOS 写进进度文件的既有内容 | 机械变异回 `>` → 必须清掉框架内容 |
| **H21** | 数据目录结构性保护：0755 → 摘掉组/其他人权限；**且不得把运维设的 0500 改成可写**（只收紧、不放开） | `-6` 版建出的目录保持 755（无结构性保护） |

> **为什么 H19 要打死 `chmod`**：旧写法的**最终**权限也是 600（因为后面补了 chmod），
> 所以"只看最终权限"的用例永远绿 —— 缺陷在**中间那个窗口**。
> 把事后收紧的路堵死，才能观测到"创建时"的权限。这与 H16 的手法同源，可复用。

> 结论性纪律：**"没走进被测分支"和"走进了但表现正确"在日志里必须长得不一样。**
> 每个新用例除对照外，还要有一条"分支已命中"的断言（T11/T21 的合并版）。

