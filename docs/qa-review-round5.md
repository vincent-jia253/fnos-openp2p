# QA 第五轮定向复核报告 — `openp2p_3.25.11-7_all.fpk`

- **复核人**：独立 QA 复核员（dev-squad `qa` 角色），**只报不修**
- **复核时间**：2026-09-30 19:12 ~ 19:30（+0800）
- **复核身份**：`octop-native`（uid 868，**非 root**）；真机上应用以 root 运行
- **主机**：`my-fnos`，Debian 12 / 内核 6.18.18.c1107-trim / x86_64
- **被测产物**：`projects/fnos-openp2p/dist/openp2p_3.25.11-7_all.fpk`
- **我的证据与复跑记录**：`qa/round5-rerun/`（本轮新增，见 §12）
- **约定**：本报告凡标 **[实测]** 的，都是我本轮自己跑出来的；标 **[读到]** 的是我读代码/读别人的结论得到的，未独立复现。

---

## 裁定：**有条件通过**

| 项目 | 结论 |
|---|---|
| 产物本身（包 ↔ 源码一致、清单自洽、235 条断言可复现） | **通过** |
| 阻塞交付的缺陷 | **0 条** |
| 交付前需处理 / 需确认（Q-list，§14） | **6 条**（Q1–Q6，全部低危：4 条产品级低危 + 1 条可维护性 + 1 条证据卫生） |
| 我新发现的产品级问题（低危） | **3 条**：N5-1 非法 Token 明文进 0644 日志 / N5-2 `ensure_token_in_conf` 冷启动"先建后 chmod" / N5-3 回调失败提示 `>` 截断 + 可裸泄漏 |
| 我新发现的写法脆弱点 | **1 条**：N5-4 `save` 失败文案硬编码"应用未被改动" |
| 我新发现的证据口径问题 | **2 条**：N5-5 `repro.sh` 仍锁 `-6` / N5-6 `repro.log` 首行标签过期 |
| 我新发现的**真机专属风险** | **1 条**：§10-2 `@appshare` 树上进程 umask 被文件系统吞掉（沙箱已复现，真机必须专项探测） |
| 我无法沙箱替代、必须真机验收 | §11（6 步最小清单 + 1 条专项探测） |

> 与前四轮不同：**本轮我没有找到能推翻"`-7` 是当前最可信产物"的证据**。
> 235/235 PASS 我自己重跑复现；H13–H17 五条的对照组我都独立重放并看到了"旧版必红"；
> 4 个变异全部把对应断言打红；包内 `cmd/`、`ui/` 与源码树**逐字节一致**。
> **对你的重点怀疑（"-7 交付前曾重建过一次"）**：重建为真，且我把 `-6`/`-7` 两个包**逐字节对拆**（§1.6）——
> 全树差异只有 4 个文件（`cmd/common`、`cmd/main`、`manifest`、app.tgz 内的 `ui/index.cgi`），
> 每一处都能对上一条已登记缺陷（P2-1/P2-B/P2-D），**无夹带、无意外改动，二进制零改动**。
> 剩余问题都在"证据卫生 / 文案 / 真机专属行为"层面，不影响 `-7` 上机冒烟。

---

## 1. 硬绑定（针对"重建过一次"这个重点怀疑对象）**[实测]**

### 1.1 包本体哈希 —— 与索引 §1 逐项一致

| 产物 | md5 | sha256 | 大小 | mtime |
|---|---|---|---|---|
| `-7`（我实测） | `3608a54efe1b966d6e80e93195e815d1` | `6fb75699f1870e7340fb3dae0c8dfd33ad48a8a6c0289f928648cc65054fa651` | 16382785 | 2026-09-30 19:05:47 |
| `-7`（索引声称） | 同 | 同 | 同 | 同 |

`-6/-5/-4/-3/-2` 五个包我也全部重算，md5 / sha256 / 大小 / mtime **与索引 §1 完全一致**。
`openp2p_3.25.11-1_all.fpk` 确实不在工作区（索引标注"文件不在工作区"，一致）。

### 1.2 包内清单自洽

```
$ tar -xOf …-7_all.fpk manifest | grep -E '^(version|checksum)'
version               = 3.25.11-7
checksum              = ad690f7bc19526db8022c23fe2969fa8
$ md5sum app.tgz
ad690f7bc19526db8022c23fe2969fa8            # 与 checksum 一致 ✅
$ tar tzf …-7_all.fpk | sort                # manifest/图标/config/{privilege,resource}/cmd 10 脚本/wizard 3 文件/app.tgz，无 app/ 目录
```

### 1.3 包 ↔ 源码树（**"重建"最该出错的地方**）

```
$ diff -r src/openp2p/cmd   /tmp/qa5/cmd      → 无输出（rc=0）
$ diff -r src/openp2p/app/ui /tmp/qa5/app/ui  → 无输出（rc=0）
$ diff -r src/openp2p/config app/config       → 无输出；wizard/、ICON.PNG、ICON_256.PNG 亦一致
$ diff src/openp2p/app/bin 与包内 app/bin      → 一致
```
（`src/openp2p/manifest` 与包内 manifest 不同是**预期**：模板 `version = 3.25.11-1`，由 `build.sh` 用 `sed` 改写并追加 checksum。此点我已核对 `build.sh` 第 3 步逻辑，**[读到]**。）

### 1.4 重建时序一致性 **[实测]**

- `src` 下**没有任何文件**比 `-7` 包的 mtime（19:05:47）新 → 不存在"打完包又改了源码"。
- 最新一次源码改动（`find -newer` 全树扫描）：`cmd/common` 19:04:03（比包早 1 分 44 秒）、`cmd/main` 18:51:09、`app/ui/index.cgi` 18:50:54。**下一项 18:16:36**（断档明显 → 说明这轮只动了这 3 个文件，是一次小范围重建）。
- 工作区内只有**一个** `openp2p_3.25.11-7_all.fpk`（无第二份重名/陈旧副本，`find` 全盘扫描确认）。
- 9 个 `exec-*.sh` 全部硬编码指向 `dist/openp2p_3.25.11-7_all.fpk`（`grep` 计数 = 9）。

### 1.5 两处"我声称已修"的定点核对 —— 我读的是**包内解出来的那份**

```
$ sha256sum /tmp/qa5/cmd/common  src/openp2p/cmd/common
e5d2f15facf5545ffcc1c150956dbc1976e01d1a9743fc33c592a7ff12c6bcbd  （两者相同）

# ① apply_settings_env 的 heredoc —— 确实在 ( umask 077; … ) 子壳里
cmd/common:414   if ( umask 077; cat > "$tmp" <<EOF
…
cmd/common:431           ) 2>/dev/null \
cmd/common:432           && [ -s "$tmp" ] \
cmd/common:433           && { mv -f "$tmp" "$SETTINGS"; } 2>/dev/null \
cmd/common:434           && [ -f "$SETTINGS" ]; then

# ② rotate_log —— 确实有权限沿用逻辑（chmod 落在 mv 之前）
cmd/common:72    mode=$(stat -c%a "$LOG_FILE" 2>/dev/null || echo 600)
cmd/common:73    if ( umask 077; tail -c 2097152 "$LOG_FILE" 2>/dev/null > "${LOG_FILE}.tmp" ) \
cmd/common:74       && [ -s "${LOG_FILE}.tmp" ]; then
cmd/common:75        { chmod "$mode" "${LOG_FILE}.tmp" 2>/dev/null; } || true
cmd/common:76        mv -f "${LOG_FILE}.tmp" "$LOG_FILE" 2>/dev/null || rm -f …
```
两条断言**成立**。`ui/index.cgi` 的 `save`（:162-175）与 `raw_save`（:280-311）同款写法（`( umask 077; … ) 2>/dev/null > "$tmp"`）。

### 1.6 「交付前重建过一次」——**把两个包逐字节对拆，证实且只改了该改的** **[实测]**

这是本轮对你重点怀疑项最直接的回答：我把 **`-6`（上一版、已作废）** 与 **`-7`（当前交付）** 两个 fpk 各自完整解包，做全树 `diff -r`。

```
$ for v in 6 7; do tar -xf dist/openp2p_3.25.11-$v_all.fpk -C /tmp/qa5/d67/s$v; done
$ diff -rq /tmp/qa5/d67/s6 /tmp/qa5/d67/s7
Files …/s6/app.tgz      and …/s7/app.tgz      differ
Files …/s6/cmd/common   and …/s7/cmd/common   differ
Files …/s6/cmd/main     and …/s7/cmd/main     differ
Files …/s6/manifest     and …/s7/manifest     differ
                      ← 全树差异**只有这 4 个文件**

$ tar xzf …/-6/app.tgz -C u6 ; tar xzf …/-7/app.tgz -C u7 ; diff -rq u6 u7
Files …/u6/ui/index.cgi and …/u7/ui/index.cgi differ
                      ← app.tgz 内部**只差** ui/index.cgi

$ diff …/s6/manifest …/s7/manifest
version  = 3.25.11-6   →   3.25.11-7
checksum = 8d2e3bbf…   →   ad690f7b…（= 各自 app.tgz 的 md5，已验）
```

`cmd/common` 与 `ui/index.cgi` 的**逐处差异**（`diff -r` 全文，我逐条对到已登记的缺陷编号上）：

| 文件 | `-6` | `-7` | 对应缺陷 |
|---|---|---|---|
| `cmd/common` `rotate_log`（:67-77） | `tail … > "${LOG_FILE}.tmp" && mv …`（裸 `>`） | 增 `mode=$(stat -c%a …)` + `( umask 077; … )` + `chmod "$mode"` 落在 `mv` **之前** + 失败 `rm -f` | **P2-D 同类**（日志轮转降权） |
| `cmd/common` `fix_binary_arch`（:330-354） | `cp -f "$src" "$cand" \|\| { log_msg … }`、`mv -f "$cand" "$BIN" \|\| …` —— **stderr 直通** | `if ! cp -f … 2>/dev/null; then …`、`mv … 2>/dev/null`、`rm -f … 2>/dev/null` | **P2-1**（回调 stderr 泄漏，第四轮实测 96 B / 本轮复现 110 B） |
| `cmd/common` `apply_settings_env`（:395-429） | `if { cat > "$tmp" <<EOF … } 2>/dev/null` | `if ( umask 077; cat > "$tmp" <<EOF … ) 2>/dev/null` | **P2-D**（含 Token 临时文件 0600） |
| `cmd/main`（:77、:142） | `rm -f "$PID_FILE"` / `rm -f "$PID_FILE" "$START_FILE"` | 各补 `2>/dev/null` | 同**P2-1** 纪律收尾（清理路径，非泄漏源） |
| `ui/index.cgi` `save` | 先 `stop` 再写盘；写失败文案无"应用未被改动" | 先写盘确认成功**才**动应用；失败文案加"；应用未被改动" | **P2-B**（保存失败把应用丢在停止态） |
| `ui/index.cgi` `save`/`raw_save` | `{ printf … } 2>/dev/null > "$tmp"` | `( umask 077; printf … ) 2>/dev/null > "$tmp"` | **P2-D** |
| `ui/index.cgi` `raw_save` | 写失败只报错，**不提应用状态** | 写失败 `if was_running → 恢复运行` 并按 `stopped`/`running_pid` 如实拼文案 | **P2-D/半装态** |

**这一节的三个结论**：
1. **"重建过一次"为真，且重建是干净的**：差异**只有 4 个文件**，每一处都能对上一条已登记缺陷（P2-1 / P2-B / P2-D），**没有任何夹带的无关改动**，`manifest` 的改动仅为 version+checksum（预期）。
2. **二进制与其余全部负载零改动**：`app.tgz` 内除 `ui/index.cgi` 外，`bin/openp2p_{x86_64,i386,armv7,aarch64}`、`config/`、`wizard/`、`ICON*.PNG`、`ui/images/*` 在两个包之间**逐字节相同** → 不存在"顺手换了二进制"这种最难查的重建风险。
3. **时间线与差异自洽**：`-6` 构建于 `18:17:47`，而上述 3 个被改文件 mtime 分别是 `18:50:54`（index.cgi）、`18:51:09`（main）、`19:04:03`（common）—— 全部**晚于 `-6`、早于 `-7` 的 `19:05:47`**。即"改 3 个文件 → 重新打包一次"完整闭环，没有第三份中间产物（`dist/` 下 `-7` 只有一个副本）。
3. **我的 H13–H17 对照组是"真·上一版实物"，不是我自己编的旧代码**（两条独立链，都验过哈希）：
   ```
   # 链路 1：cmd/common（H15/H16/H17 对照组）
   qa/legacy-cmd/common.from-6   = fa434ac271882a5bad67637100849c86a99a246bc423c6da10b12b5ef73a287f
   -6 包内解出的 cmd/common      = fa434ac2…   （同一份；-7 是 e5d2f15f…）
   # 链路 2：ui/index.cgi（H13/H14 对照组）
   qa/legacy-ui/index.cgi.from-6 = f0527a8bb491f9484b838dbc8b7578886cf95b3fad354c7337e51f754b695c7b
   -6 包内解出的 ui/index.cgi    = f0527a8b…   （同一份；-7 是 c1164ca2…）
   ```
   即对照组 = **`-6` 交付物里那份原物**，而 `-7` 恰好在这两处都改了 → "把修复回退就会变红"这条论证**用真实上一版实物就能成立**，无需依赖变异体（变异体只是额外交叉验证）。这也是本轮"旧版本会不会失败"的答案：**会** —— `-6` 版的实物在同一注入下确实输出 666 / 泄漏 `cp: Permission denied` / 静默停在停止态。
   （索引 §4 自己就声称这两份快照"来源 = `-6` 包内"，我这次是**用解包哈希把它验证了一遍**，不是照抄。）

---

## 2. 索引自检 + "让它说谎" **[实测]**

```
$ cd qa && python3 make-index.py --check
OK: evidence-index.md 与实物一致（200 行）    rc=0
```
我另外**逐条重算**了索引 §3 的 12 个脚本 sha256（`while read f h; do sha256sum`）：**12/12 全 OK**；并重算了 §4 的 5 个对照组快照（`legacy-cmd/common.from-6`、`legacy-ui/index.cgi.from-{2,3,5,6}`）**5/5 与索引一致**，包括按索引给的"文件名+内容喂同一 sha256"配方复算的 `legacy-3.25.11-1-cmd/`（10 文件）聚合值 `dd95771a…` —— **完全复现**。

**说谎实验（两种都做了，rc 我都取了真实值）**：
1. 往 `exec-H.sh` 追加一行注释 → 重跑 `--check`：打印 `DIFF`，并**逐行指出** `exec-H.sh` 的 sha256 应由 `b034195fd58a2d585dc189293399be167f79bef7e16ce6f0000811a259944345`（索引）变为 `0f45daf9f18c32a51759e60fb87d0675a16c6fe42a66c0d4eee3c1793681a510`（实物），**`rc=1`** ✅
2. 只 `touch exec-E.log`（内容一字未改，只动 mtime `19:08:13` → 当前时刻）→ 同样 `DIFF`：sha256 列**一字不变**，只有 mtime 列被标出，**`rc=1`** ✅（证明索引把 mtime 也绑进去了）
3. 测完复原（`cp -a` 还原 exec-H.sh 的字节与 mtime；`touch -d "2026-09-30 19:08:13"` 还原 exec-E.log 的 mtime）→ `sha256(exec-H.sh)` 回到 `b034195f…`，`--check` **OK / rc=0** ✅

结论：索引**不可静默腐化**，且覆盖内容变更与纯 mtime 变更两种形态。这是本轮唯一让我对"元证据"放心的机制。

---

## 3. 全套重跑（日志我自己生成，不看旧日志内容）**[实测]**

`bash exec-A.sh … exec-H.sh`（逐个重跑，输出重定向到日志）+ `bash repro.sh`。

| 块 | 我重跑的 PASS/FAIL | 索引 §2/§5 声称 | 一致? |
|---|---|---|---|
| A | 26 / 0 | 26 / 0 | ✅ |
| B | 30 / 0 | 30 / 0 | ✅ |
| C1 | 18 / 0 | 18 / 0 | ✅ |
| C2 | 26 / 0 | 26 / 0 | ✅ |
| D | 3 / 1 | 3 / 1 | ✅ |
| E | 21 / 0 | 21 / 0 | ✅ |
| F | 16 / 0 | 16 / 0 | ✅ |
| G | 29 / 0 | 29 / 0 | ✅ |
| H | 69 / 0 | 69 / 0 | ✅ |
| **合计（不含 D）** | **235 / 0** | **235 / 0** | ✅ |
| repro | **OK=17 / BAD=0** | 17 / 0 | ✅ |

**哈希漂移（我自己重跑 vs 冻结日志）**：

| 日志 | 冻结 sha256（索引 §2） | 我重跑 sha256 | 漂移原因 |
|---|---|---|---|
| exec-A | `c9cd1098…` | `e3ec4a51…` | PID / 时间戳 |
| exec-B | `1f3db940…` | `108fcbd4…` | 同上 |
| exec-C1 | `73689491…` | `73689491…` | **完全相同**（确定性） |
| exec-C2 | `cde2da59…` | `146b00f3…` | PID |
| exec-D | `80c1d9ae…` | `0178552c…` | qemu-i386 崩溃文本不同（"mallocgc…" vs "runtime·unlock: lock count"），**结论不变** |
| exec-E | `0d27c29b…` | `9d174d13…` | 时间戳 |
| exec-F | `012661d7…` | `012661d7…` | **完全相同** |
| exec-G | `865d0656…` | `abfbcea0…` | PID |
| exec-H | `3aae71f9…` | `2fc95751…` | PID |
| repro | `edee877e…` | `4b49888f…` | 时间/PID/inode |

我逐字对比了 A–H 的旧日志与新日志：**差异仅为 PID、时间戳、i386 崩溃文本**，`[PASS]/[FAIL]` 行与汇总行**完全一致**。

> **处置说明（重要）**：重跑会覆盖 `qa/exec-*.log`，从而让 `--check` 变成 DIFF。为了不让仓库进入"索引自称一致、实物已变"的状态，我把自己的重跑日志**另存**为 `qa/round5-rerun/exec-*.rerun.log` + `repro.rerun.log`，
> 然后 `cp -a` 还原了原冻结日志并复验 `--check` = OK。两份日志都在，谁都能自行比对。

**repro 集**：我只差 7 处（运行时间 + 5 处 PID/inode + 1 处对照路径），`OK=17 BAD=0` 一致。

---

## 4. H13–H17 的鉴别力（**每条都手工独立重放，不依赖 exec-H.sh**）**[实测]**

我另写了 5 个独立 harness（`qa/round5-rerun/h13.sh … h17_manual.sh`），自己搭沙箱、自己注入失败。

| 用例 | 我的独立复现（新版 `-7`） | 对照组实测值（证据） | "把修复回退会不会变红" |
|---|---|---|---|
| **H13** 保存写失败时应用必须仍在运行 | 应用**仍在运行**（pid 未变），文案 `❌ 设置写入失败：…本次设置未生效；应用未被改动`，CGI stderr **0 字节** | `legacy-ui/index.cgi.from-6`：应用**被静默停掉**（进程消失），文案只有"本次设置未生效"、**只字不提交应用状态** | **会红**：把 `save` 改回"先 stop 再写"（变异 b）→ 我的 harness 立刻报"被丢在停止态" ✅ |
| **H14** `raw_save` 写失败必须恢复运行 / 如实交代 | 注入"`config.json` 变非空目录"（重启也会失败）→ 文案 `…原文件未改动；且应用未能重新启动，请查看下方日志`（**如实**）；换成"数据目录 500"注入（更贴近磁盘满/只读）→ 文案 `…；应用已恢复运行`，应用**真的在运行** | `from-6` 对照组由 `exec-H` 实测"静默丢在停止态 + 只字不提" | **会红**：删掉失败分支的恢复逻辑（变异 d）→ 文案不再交代应用状态 ✅ |
| **H15** 数据目录不可写时回调零泄漏 | **前置①** 包内 `bin/openp2p_x86_64` 在位 ✅；**前置②** 数据目录内无现成二进制 ✅（否则走"沿用"分支，等于没测）；`upgrade_callback` rc=1，stderr **0 字节**；**分支命中证据**：日志出现 `❌ 复制二进制到数据目录失败：…openp2p.new.<pid>`，且失败后数据目录无二进制、无 `openp2p.new.*` 残留 | 把 `cmd/common` 换成 `common.from-6` 同场景：stderr **110 字节**，首行 `cp: cannot create regular file '…openp2p.new.<pid>': Permission denied` | **会红**（对照已实测出泄漏）✅ |
| **H16** 含 Token 的临时文件与 umask 无关地 0600 | 手法：`umask 000` + 同名函数桩打死 `mv`/`rm`，临时文件真的留在盘上；`settings.conf.tmp.<pid>` 权限 = **600**（属主 octop-native，大小 636，含 Token 明文） | `common.from-6` 同手法 → **666**（`-rw-rw-rw-`） | **会红**：删掉 `umask 077`（变异 a）→ **666** ✅ |
| **H17** 日志轮转沿用原权限 | 6 MB 日志 + `chmod 600` + `umask 000` → 轮转后 **600**，大小 2097224（尾部 2 MB + 一行轮转记录），无 `.tmp` 残留 | `common.from-6` 同手法 → **666** | **会红**：删掉权限沿用（变异 c）→ **666** ✅ |

> **对照组 = 真实上一版实物（我在 §1.6 验过哈希）**：`qa/legacy-cmd/common.from-6` 的 sha256 = `fa434ac2…` = **`-6` 包内解出的 `cmd/common` 的 sha256**，而 `-7` 的 `cmd/common` 是 `e5d2f15f…`。所以上表"旧版 666 / 泄漏 110 B"读的是**上一版交付物本身**，不是我自己伪造的旧代码 —— "修复回退即变红"因此是硬结论。

**关于 H15 的"前置条件"**：我特别确认了 exec-H.sh 里那两行前置断言不是摆设 —— 并且我自己复现时**故意走了一遍**：若包内二进制不在位，`fix_binary_arch` 会命中"沿用数据目录中已有二进制"分支（`src` 不存在 → return 0），`cp` 根本不执行，用例会**假绿**。exec-H.sh 的第 2 条前置断言正是防这个（T21 的教训落实到位了）。

---

## 5. 变异测试（在 `/tmp` 副本上做，未动仓库）**[实测]**

变异体保存在 `qa/round5-rerun/mutants/`。

| # | 变异（相对 `-7` 源码） | 目标断言 | 实测结果 | 结论 |
|---|---|---|---|---|
| a | `cmd/common:414` 去掉 `umask 077;` | H16 | 临时文件 **666** | **变红** ✅ |
| b | `ui/index.cgi` 的 `save` 在写盘**之前**插入"先 stop"（还原旧顺序） | H13 | 保存失败后应用**被丢在停止态** | **变红** ✅ |
| c | `cmd/common::rotate_log` 去掉权限沿用（退回 -6 的裸 `>` 写法） | H17 | 轮转后 **666** | **变红** ✅ |
| d | `ui/index.cgi` 的 `raw_save` 失败分支删掉"恢复运行/如实交代"逻辑 | H14 | 文案**只字不提**应用状态 | **变红** ✅ |
| e | `cmd/main` 把 `-token "$TOKEN"` 加回命令行 | 我新增的 Token 泄漏断言（§9） | `ps` 全机进程表命中该 Token **1 行**（明细可见 `-token 314159265358`） | **对照组成立** ✅ |

> 顺带一个**设计脆弱点（低危，非缺陷）**：变异 b 下，失败分支仍打印"…本次设置未生效；**应用未被改动**"——这句是**硬编码断言**，不是从状态推导的。当前控制流下它成立（所以不是缺陷），但一旦有人再动这段顺序，文案会立刻变成谎话。见观察项 N5-4。

---

## 6. 横向搜索"同类漏改"（你说你连错三次，我替你逐条批）**[实测 + 读到]**

判据：`cmd/*` + `app/ui/index.cgi` 里**所有**新建/写入文件的重定向点。我的枚举（逐条列出，另附 1 个删除点）：

| # | 位置 | 写什么 | stderr 抑制 | 权限纪律 | 裁定 |
|---|---|---|---|---|---|
| 1 | `common:35` `{ echo …; } 2>/dev/null >> "$LOG_FILE"` | 日志 | ✅ `2>/dev/null` 在前 | 进程 umask（日志设计上不含 Token） | ✅ 但见 **N5-1** |
| 2 | `common:42` `{ echo "$*"; } 2>/dev/null >> "$TRIM_TEMP_LOGFILE"` | fnOS 安装进度 | ✅ | 同上 | ⚠️ **N5-1**（会写非法 Token 输入） |
| 3 | `common:73` `( umask 077; tail … > "${LOG_FILE}.tmp" )` | 日志尾部 | ✅ | ✅ umask 077 + `chmod` 在 `mv` 前 | ✅ |
| 4 | `common:121` `{ echo "$p" > "$PID_FILE"; } 2>/dev/null` | PID | ✅ | 无敏感信息 | ✅ |
| 5 | `common:261` `printf '{"network":{"Token":%s}}\n' … > "$CONF"` | **含 Token 的 config.json** | ✅ | ❌ **先按进程 umask 创建、第 263 行才 `chmod 600`** | ⚠️ **N5-2（同 P2-D 类，仅窗口，非最终态）** |
| 6 | `common:289` `{ echo "$$"; } 2>/dev/null > "${LOCK_DIR}/owner"` | 锁属主 | ✅ | 无敏感信息 | ✅ |
| 7 | `common:414` `( umask 077; cat > "$tmp" <<EOF …)` | **含 Token 的 settings 临时文件** | ✅ | ✅ | ✅ |
| 8-9 | `install_callback:19,25` / `upgrade_callback:19,25` `echo … > "${TRIM_TEMP_LOGFILE:-/dev/stderr}"` | 失败提示 | ❌ 无抑制（**有意**） | — | ⚠️ **N5-3**（`>` 会截断进度文件；文件不可写则裸泄漏） |
| 10 | `main:119` `{ : >> "$LOG_FILE"; } 2>/dev/null`（可写性探针） | 探针 | ✅ | — | ✅ |
| 11 | `main:127` `nohup … >> "$log_target" 2>&1` | 子进程输出 | 由 10 的探针保证 | — | ✅ **残留 TOCTOU**（探针与真正打开之间理论上可被打断），低危 |
| 12-14 | `main:129,130,218,236` PID / start_time | 运行文件 | ✅ | 无敏感信息 | ✅ |
| 15-16 | `index.cgi:162` `) 2>/dev/null > "$tmp"`（save） | **含 Token 的 settings 临时文件** | ✅ | ✅ `umask 077` 子壳内 | ✅ |
| 17 | `index.cgi:280` `( umask 077; printf … > "$tmp" ) 2>/dev/null`（raw_save） | **含 Token 的 config.json 临时文件** | ✅ | ✅ | ✅ |
| 18 | `common`（`fix_binary_arch` 末尾）`rm -f "${PAYLOAD_BIN}"/openp2p_* 2>/dev/null` | 安装后清掉包内负载二进制 | ✅ | — | ✅ 顺带登记（**这是"删除点"，不在 17 个"写入点"口径里**；装了新版后 `app/bin/` 会被清空，所以**真机上"包内二进制还在"这个前提只在安装前成立**，H15 的前置断言必须在解包目录上做） |

**三个专项**：
> 补充（来自 §1.6 的 `-6`→`-7` 对拆）：`main:77` / `main:142` 的两处 `rm -f …` 也是这轮补的 `2>/dev/null`。它们**不是写入点**，所以不在上表 21 处里；`rm` 失败只往 stderr 打一行，不构成泄漏源，属于纪律收尾（同 P2-1）。我确认这两处**没有**引入"目标文件写在 `2>/dev/null` 之前"之类的新写法。

- **"chmod 落在 mv 之后"**：全量列了 `chmod` 与 `mv`（见 §1.5 与上表）。除 **#5** 外，所有 `chmod` 都落在"创建或 `mv` **之前**"（#3、#7、#15、#17），或者作用在本来就已经是 600 的文件上（`common:434`、`index.cgi:175/311`、`main:136`）—— 是幂等加分项，不算隐患。**唯一同类漏网：`ensure_token_in_conf` 的冷启动 `>` + 事后 `chmod`**。
- **"`2>/dev/null` 在目标文件之后"**：我按行扫了全部写入点，**0 命中**（与 `repro.sh` 的 R2a/R2b 结论一致，且 R2b 的跨行组检查也 0 命中）。
- **"目标文件出现在重定向之前"**：同上，0 命中；唯二例外是 #8-9（有意不抑制）与 #11（有探针兜底）。

### N5-1（**新发现，产品级，低危**）：被拒绝的 Token 明文会进 0644 日志 **[实测]**

```
$ … ( . cmd/common; openp2p_token='abc123456789' openp2p_node='bad name!*' apply_settings_env )
$ cat $LOG_FILE  (权限 644)
[2026-09-30 19:23:03] [openp2p] ⚠️ Token 只接受数字，已忽略输入：「abc123456789」
$ cat $TRIM_TEMP_LOGFILE  (权限 644)
⚠️ Token 只接受数字，已忽略输入：「abc123456789」
$ grep -c 'abc123456789' $LOG_FILE $TRIM_TEMP_LOGFILE   → 1 / 1
```
- **性质**：`apply_settings_env` 对非法输入用 `warn_msg "…「${v}」"` 回显原值（`common:376/380/384/388/392/396` 六处，Token 只是其一）。
- **与既有结论的冲突**：`TC-14`/`TC-21` 的验收条款写的是"日志中 Token 出现次数为 **0**"——那只对**合法**（纯数字）Token 成立。用户手滑粘进一个含字母/符号的真实 Token 片段，就会落进 0644 的日志与安装进度文件。
- **危害**：凭据"部分泄露"（拒绝的值不是可用凭据，但可能是真 Token 的错字版本）；且日志文件本身是 0644。
- **建议**：回显改为**不回显原值**（如"Token 只能包含数字"），或对 Token 字段单独脱敏（`mask_token` 已有现成实现）。**不阻塞交付**。

### N5-2（**新发现，低危**）：`ensure_token_in_conf` 冷启动仍然是"先建后 chmod" **[实测]**

```
# 探针：把 chmod 换成函数桩，观察 chmod 被调用那一刻的权限
[probe1] 即将 chmod 600 到 …/config.json，此刻该文件权限 = 666        ← 进程 umask 000 的现场
# 再试：chmod 变成空操作（模拟 chmod 失败/进程在 chmod 前被杀）
最终 config.json 权限 = 666, 内容 = {"network":{"Token":314159265358}}
```
- `common:261` 用 `printf > "$CONF"` **按进程 umask 创建含 Token 的文件**，`263` 才 `chmod 600`。这与 P2-D 的判据（"含 Token 的文件必须**一创建就是 0600**，不能等事后 chmod"）是同一类，只是对象从"临时文件"换成了"冷启动的最终文件"。
- **危害**：窗口期极短（`printf` 与 `chmod` 之间无 I/O），真机 umask 通常 022 → 窗口内 0644。**最终态仍是 600**（我实测 start 前后 config.json 都是 600，且 openp2p 二进制回写它时也没有放宽权限）。
- **建议**：改成 `( umask 077; printf … > "$CONF" )`，与另外三处保持一致（T22 的"靠枚举、不靠记忆"应该把这处也网进去）。
- **不阻塞交付**，但下一版应修。

### N5-3（**新发现，低危**）：回调的失败提示自身有"截断 + 裸泄漏"两个小毛病 **[实测]**

```
# 场景 A：TRIM_TEMP_LOGFILE 可写
$ echo "旧的安装进度内容（fnOS/wizard 先写的）" > install.err
$ TRIM_TEMP_LOGFILE=install.err bash cmd/install_callback
$ cat install.err
openp2p 二进制部署失败（当前架构 x86_64），安装中止。详情见 …/apps.log      ← 旧内容被 `>` 截断
rc=1  stderr=0 字节
# 场景 B：TRIM_TEMP_LOGFILE 所在目录不可写
$ TRIM_TEMP_LOGFILE=/…/ro/x.err bash cmd/install_callback
rc=1  stderr=91 字节
/…/cmd/install_callback: line 18: /…/ro/x.err: Permission denied        ← 裸错误泄漏到回调 stderr
```
- `install_callback:19/25`、`upgrade_callback:19/25` 用的是 `>` 而非 `>>`，会**抹掉 fnOS/向导先前写进进度文件的内容**；且这条重定向**没有** `2>/dev/null` 兜底 —— 恰是 P2-1/P2-A 那一类"裸错误泄漏"，只是发生在"报错本身也失败"的二阶路径上。
- H15 只注入"数据目录不可写"，覆盖不到这条。**不阻塞交付**（应用中心看得到日志文件，且概率低）。

### N5-4（观察项，防御性写法）：`save` 失败文案是硬编码事实断言

"…本次设置未生效；**应用未被改动**"这句话不由状态推导。当前控制流下成立（H13 实测通过），但变异 b 表明一旦顺序被改回，"应用未被改动"立刻变成谎话。建议下一版改为按 `was_running`/`stopped` 事实拼装，或干脆删掉这句。

---

## 7. 索引/证据链自身的两个口径问题 **[实测]**

### N5-5：`repro.sh` 仍把被测产物写成 **`-6`**（已作废的包），且断言文案里写着"-6 如何如何"

```
$ head -35 repro.sh | grep -n '3.25.11'
31: echo "被测产物：$DIST/openp2p_3.25.11-6_all.fpk"
32/33: md5/sha256 = 8cfa0380…（= 索引 §1 里标注"作废"的那个包）
$ bash repro.sh | head -4
被测产物：…/dist/openp2p_3.25.11-6_all.fpk
  md5    = 8cfa038075a2cfd51b6a4cf96484562a
```
**实际被测的代码**：R2c/R4/R5/R6 用的是 `$SRC/cmd/common`（**源码树 = `-7` 内容**），R3 用的是 `$SRC/app/ui/index.cgi`；`-6` 包**只被用来打印 md5**，`-4` 包被用作对照组解包。所以**结论实质无误**，但这行横幅会让人误以为"这份 repro 证据属于 `-6`"（而索引 §1 明写 `-6` 已作废），且 §6 的"当前 17 OK/0 BAD"没有写明"实际是对当前源码树跑的"。
**建议**：改成读 `$DIST/openp2p_3.25.11-7_all.fpk` 并打印 `-7` 的 md5；断言文案里的"-6"改成动态标签/去掉。

### N5-6：`repro.log` 的"被测产物"一行与索引 §2/§6 的绑定语义不匹配（同源问题）

索引 §2 把 `repro.log` 与其 sha256 绑定、§6 宣称"换人换机可复现出同样结论"，但打开 `repro.log` 第一行写的是 `-6`。**证据本身没造假**（见上），只是标签过期。与 N5-5 一并修即可。

---

## 8. 语义与文案判断（第 7 条的三问）

### 8.1 `install_callback` / `upgrade_callback` 在设置写失败时 `exit 1` —— 会不会半装？**结论：行为可接受，文案需补一句**

**[实测]** 构造"二进制能部署、设置写不了"（`settings.conf` 变非空目录）：

```
$ bash cmd/install_callback     → rc=1, stdout=0, stderr=0
$ cat $TRIM_TEMP_LOGFILE
设置写入失败：/…/settings.conf 不可写（请检查存储空间与权限）。详情见 /…/apps.log
$ ls -la $DATA_DIR
-rwx--x--x 1 … 10371072 openp2p        ← 二进制**已经落地**
drwxr-xr-x … settings.conf             ← 设置没写成
drwxr-xr-x … log
$ bash cmd/main status → rc=3
```
**补测（半装态下用户点"启动"到底会发生什么）**：`cmd/main` 的 `resolve_settings()` 对"`settings.conf` 缺失"是**优雅降级**的（`main:28-47`，`else` 分支 :39-46 回退去读 `config.json` 的 `Token/Node/…`，缺失则用默认值），因此**不存在"跳过启动"**。我构造半装态（`settings.conf` 不存在）直接跑 `main start`，两个子场景实测如下：

```
# 场景 A：全新安装失败后（连 config.json 都没有）
$ bash cmd/main start   → rc=0；pid=3507532 存活=yes；main status → rc=0（运行中）
  apps.log: ⚠️ 尚未配置 Token：应用将启动但不会登录组网，请在应用界面填写 Token 后保存。
  apps.log: 启动中：node=my-fnos server=api.openp2p.cn:27183 sharebandwidth=10 loglevel=1
  apps.log: 2026/09/30 19:29:23 … ERROR c.Network.Token == 0 skip save     ← 二进制自己报"Token==0"
  argv: …/openp2p -node my-fnos -sharebandwidth 10 -serverhost … -installpath …
  config.json 内容: {"network":{"Token":0}}

# 场景 B：从旧版升级失败后（config.json 里有旧 Token=314159265358）
$ bash cmd/main start   → rc=0；pid=3508282 存活=yes；main status → rc=0
  apps.log: 启动中：node=nas-old …（沿用 config.json 里的旧设置）
  config.json 旧 Token 被**保住**：{"network":{"Token":314159265358,"Node":"nas-old",…}}
```

**事实**：
1. **确实会留下半装状态**：二进制、`log/` 目录已建，`settings.conf` 缺失/异常。此时应用中心显示"已安装"，用户点启动 **`main start` 返回 0、进程真的起来、`main status` 也返回 0（运行中）** —— 即界面与状态检测**都会显示"运行中"**。两个子场景的差别：
   - **场景 A（全新装、无 `config.json`）**：Token 被写成 `0`，二进制自己打 `ERROR c.Network.Token == 0 skip save` → **进程活着但不登录组网**（"运行中"是假象，功能为零）。这是半装态真正的危害：**静默功能失效**。唯一线索是 `apps.log` 里那句 `⚠️ 尚未配置 Token…` —— 而它写在**日志文件**里，界面不会弹。
   - **场景 B（从旧版升级、`config.json` 尚存）**：旧设置（含旧 Token）被沿用，应用照常工作 → 实际影响很小，属于"升级失败但仍能用旧配置跑"。
   > 注：`main start` 在无 Token 时仍启动是**有意设计**（B8 修复，见 `main:92-98` 注释：无 Token 也照常启动，否则"Token 只能在启动后的界面里填"会死锁）—— 本观测**不构成对 B8 修复的异议**，只说明半装态下它会放大成"看起来运行、实际不组网"。
2. 失败信息进了 `TRIM_TEMP_LOGFILE`（fnOS 安装进度界面用的那个文件）——**能不能真的被展示，我无法在沙箱验证**（需要真机 root + 应用中心 UI）。我只能确认**代码确实把提示写进去了**。
3. `exit 1` 的价值：应用中心会把这次安装/升级标成失败，不会骗用户"装好了"。
**判断**：**行为可接受**（失败要能被感知，比旧版"exit 0 + 报成功"好得多）；**文案建议补一句**：明确指出"二进制已部署、仅设置未写入；请检查存储空间/权限后，用应用中心的『修复』重试"，并且**补上第 1 条的坑**——即"此时若点『启动』，界面会显示『运行中』，但未填 Token 时并不会真正登录组网"。理由：现在这句话只说了"设置写不了"，没告诉用户"包其实装了一半、怎么收拾、以及'运行中'可能是假象"。
**风险等级**：低（安装失败本身已 exit 1 并在应用中心可见；用户正常会在应用界面补 Token）。`upgrade_callback` 的情形更缓和（旧 `settings.conf` 原样保留，应用仍能用旧设置跑；我实测旧 `config.json` 里的 Token 也被保住）。

### 8.2 `save` 改成"先写盘再动应用"后，有没有"落盘了但没生效"的窗口？**结论：有，但文案说清了**

**[实测/读到]** 四种分支的文案（`index.cgi:168-205`）：
| 情形 | 行为 | 文案 |
|---|---|---|
| 应用本来没跑 | 只写盘，不碰应用 | `✅ 设置已保存（应用当前未运行）` |
| 应用在跑，停旧成功、起新成功 | 真重启 | `✅ 设置已保存，应用已自动重启` |
| 停旧失败 | 保设置，不硬启 | `⚠️ 设置已保存，但未能停止旧进程…请到应用中心重启后生效` |
| 起新失败 | 保设置 + 明确告警 | `⚠️ 设置已保存，但应用未能启动，请查看下方日志` |
**判断**：**文案足够**。"落盘了但没生效"的窗口只出现在"未运行"（本来就不需要生效）与"启动失败/停止失败"（文案明确要求用户去应用中心重启）两种情形。`raw_save` 同款（且额外说明"需先停再写"的原因）。
唯一小瑕疵：重启成功与否用的是 `running_pid`（`is_our_pid` 复核过的进程），而不是"参数是否真的变了"——这不是缺陷，只是"生效"的判据是"进程起来了"。可接受。

### 8.3 符号链接数据目录（真机 `%TRIM_PKGVAR%` 形态）下 `tmp + mv` 原子改名还工作吗？**结论：工作，且我构造了跨文件系统沙箱验证**

**[实测]** 真机形态 = `/var/apps/openp2p/shares/openp2p → /vol4/@appshare/openp2p`，而本机 `/`（nvme0n1p2）与 `/vol4`（dm mapper）**确实是两个不同文件系统**，所以我在同形布局上验证：

```
布局: /tmp/qa5/sbx/sym/app/shares/openp2p -> /vol4/@appshare/octop-native/qa5-sym-real
      device(/) = 66306   device(/vol4) = 64769   ← 跨文件系统，与真机同形
[probe mv] 真实目录(tmp)=/vol4/@appshare/octop-native/qa5-sym-real  dev=64769
           真实目录(target)=/vol4/@appshare/octop-native/qa5-sym-real dev=64769  同一目录=YES
→ apply_settings_env rc=0；落地在 /vol4/… 的真实目录，权限 600，无 .tmp 残留
→ index.cgi save  rc=0  文案「✅ 设置已保存」 ；settings.conf 600，无 .tmp 残留
→ index.cgi raw_save rc=0 文案「✅ config.json 已保存」 ；config.json 600，无 .tmp 残留
→ install_callback 经符号链接部署二进制：rc=0，stderr 0 字节，二进制出现在真实目录且可执行
→ is_our_pid 经符号链接 → TRUE（B11 现场）
```
**判断**：`tmp` 与目标落在**同一个真实目录**（同一设备号），`mv` 就是同分区 `rename(2)`，**原子性成立**；跨文件系统的只是"符号链接前后的路径字符串"，不构成 `EXDEV`。真机根因 B11 的现场（符号链接）在新版下不再导致重复实例。

---

## 9. 我新增的独立断言：Token 不得进入"日志 / 运行文件 / ps argv / 数据目录其它文件" **[实测]**

我另写了 `token_leak.sh`（手法：用**产品代码** `apply_settings_env` 写入 settings，再启动真实二进制，然后逐位置搜索 Token 明文 `314159265358`）。

| 检索位置 | `-7` 结果 | 说明 |
|---|---|---|
| `$LOG_FILE` + `$DATA_DIR/log/` | **0 命中** ✅ | 二进制自身日志（含 `login error`）也不含 Token |
| `TRIM_TEMP_LOGFILE`（fnOS 进度文件） | **0 命中** ✅ | 合法 Token 场景 |
| 运行文件（`app.pid`/`start_time`/锁/`owner`） | **0 命中** ✅ | |
| `ps -eo pid,args=` 全机进程表快照 | **0 命中** ✅ | 启动命令行为 `-node … -sharebandwidth … -installpath …`，无 `-token` |
| `/proc/<pid>/cmdline` | **0 命中** ✅ | 同上 |
| 数据目录中除 `config.json`/`settings.conf` 外的文件 | **0 命中** ✅ | |
| `config.json`（应含） | 1 命中；权限 **600** ✅ | |
| `settings.conf`（应含） | 1 命中；权限 **600** ✅ | |
| **对照组**（变异 e：改回 `-token "$TOKEN"` 走命令行） | `ps` 命中 **1 行**，明细 `-token 314159265358` ✅ | **证明本断言有鉴别力** |

> 注意：你原始要求里的对照组是"`-1` 版把 token 走命令行 → argv 里必须能查到"。**这个前提不成立**：`qa/legacy-3.25.11-1-cmd/main` 第 99 行注释（"Token 只写进 config.json，不走命令行 —— 命令行参数会暴露在 ps 里"）与第 112 行起的 `nohup "$BIN" -node … -sharebandwidth … -installpath …` **都证实 `-1` 同样不传 `-token`**（我逐行看过）。所以 `-1` 不能当 argv 对照，我改用**自建变异体**（`mutants/main.token-in-argv`）当对照 —— 这条路才真能证明断言有鉴别力。

---

## 10. 沙箱里"看起来一样、结论不一样"的两处坑（供后续轮次复用）**[实测]**

1. **我自己踩了噪声**：第一版 `token_leak.sh` 把 `apply_settings_env` 写在 `export TRIM_APPNAME=openp2p …` **之前**，于是 `cmd/common` 算出 `/var/apps/octop-native/…` → 写失败（rc=1）→ 断言全部"看起来正常"但其实**根本没测到目标目录**。修好后 rc=0。**你的警告是真的，值得写进测试纪律。**
2. **更值得警惕的一条（我未能在文档里找到登记）**：`/vol4/@appshare/<app>/` 这棵树上**进程 umask 不生效**，新建文件/目录**直接继承父目录的权限**：

```
（全部实测）
/vol4/@appshare/octop-native                 umask077→705  umask000→705  mkdir→705
/vol4/@appshare/octop-native/data            umask077→700  umask000→700  mkdir→700
/vol4/@appdata/octop-native                  umask077→600  umask000→666  mkdir→755   ← 正常
/vol4/@apphome|@appconf|@apptemp|@appcenter|@appmeta/octop-native  同上，正常
/tmp（根分区）                               umask077→600  umask000→666  mkdir→755   ← 正常
# 父目录权限继承矩阵（在 @appshare 树内，显式 chmod 过的父目录）
parent=777→子文件 777 / parent=755→755 / parent=750→750 / parent=701→701 / parent=700→700 / parent=705→705
```
  - **含义**：在真机数据目录 `DATA_DIR = /var/apps/openp2p/shares/openp2p → /vol4/@appshare/openp2p` 上，`umask 077`（P2-D 的修法）**不是权威机制**；临时文件的实际权限 = 数据目录的权限。
  - **现状**：真机的 `/vol4/@appshare/openp2p` 是 `drwx------ openp2p:openp2p`（700，我只读探测过 ACL：`user::rwx group::--- other::---`）→ 临时文件会是 **700**，**不会泄露**。所以 H16 的**意图**在真机上成立。
  - **风险**：若数据目录将来是 0755（应用框架改默认、或用户手改），同一次 `save` 就会把含 Token 的临时文件建成 **755（人人可读）**，而 `umask 077` 一点忙都帮不上 —— 事后 `chmod 600` 只保住了最终文件。
  - **建议（低危）**：把"0600"从"靠 umask"改成"**显式**"：例如 `: > "$tmp" 2>/dev/null && chmod 600 "$tmp" && cat > "$tmp"`（或 `install -m 600 /dev/null "$tmp"`），四个写入点统一。这样在"umask 被文件系统吞掉"的环境里也成立。
  - **必须真机复核**（见 §11-7）。

---

## 11. 真机不可替代的验收项（只列，我不做）

1. **应用中心覆盖安装/升级 `-7`**（**勿卸载**，保留原配置）→ 装完看应用中心是否报成功。
2. **装完立刻点「停止」再「启动」** → `ps -ef | grep '[o]penp2p'` **必须只剩 1 个**实例（现在真机跑着 **2 个** root 残留：PID 2795664 / 2800553，我非 root 杀不掉，如实登记）。
3. **重启 NAS** → 应用自动起来、仍只有 1 个实例、日志无 `bind: address already in use`。
4. **界面填 Token → 保存** → 文案为"✅ 设置已保存，应用已自动重启"；CGI 无裸 `Permission denied`；`ls -l /var/apps/openp2p/shares/openp2p/settings.conf` 与 `…/config.json` 均为 `-rw-------`。
5. **不填 Token 直接打开界面** → 必须能进（B8 回归）；文案含"尚未填写 Token"引导。
6. **卸载一次（选"保留数据"）+ 重装** → 配置不丢；再选"删除数据"卸载 → 数据目录被清、无孤儿进程。
7. **专项探测（本轮新增，沙箱无法替代）**：在真机上执行
   `R=/vol4/@appshare/openp2p; umask 077; touch $R/.qa-probe; stat -c '%a' $R/.qa-probe; rm -f $R/.qa-probe`
   → 若得到 **755/705**（而不是 600/700），说明 §10-2 的"umask 被文件系统吞掉"在真机数据目录同样成立，此时请务必确认数据目录**始终是 700**，否则临时文件会短暂对他人可读。
8. **半装态文案**（§8.1）：真机上故意把数据目录设成不可写再装一次，确认应用中心/进度界面**能看到** `设置写入失败：… 详情见 /var/log/apps/openp2p.log` 这句话（我在沙箱只能确认代码写进了 `TRIM_TEMP_LOGFILE`，看不到 UI）。

---

## 12. 我的证据哈希（全部我本轮实测产出）

### 12.1 产物 / 源码
```
-7_all.fpk        md5 3608a54efe1b966d6e80e93195e815d1
                  sha256 6fb75699f1870e7340fb3dae0c8dfd33ad48a8a6c0289f928648cc65054fa651   16382785 B (19:05:47)
包内 & 源码 cmd/common     sha256 e5d2f15facf5545ffcc1c150956dbc1976e01d1a9743fc33c592a7ff12c6bcbd
包内 & 源码 app/ui/index.cgi sha256 c1164ca2cf79e3a80937b1a55c5803be963777bdbd87154b70381ca9b26cb890
manifest.version 3.25.11-7 ；manifest.checksum = md5(app.tgz) = ad690f7bc19526db8022c23fe2969fa8
```

### 12.1b 「重建」对拆证据（§1.6 用到的六个哈希，全部我本轮算的）
```
-6_all.fpk        md5 8cfa038075a2cfd51b6a4cf96484562a      ← 与索引 §1 一致（标注"作废"）
-6 包内 cmd/common   sha256 fa434ac271882a5bad67637100849c86a99a246bc423c6da10b12b5ef73a287f
-6 包内 app.tgz      md5 8d2e3bbfdc481b32010c97c9333f4172   = -6 manifest.checksum
-7 包内 & 源码 cmd/common sha256 e5d2f15facf5545ffcc1c150956dbc1976e01d1a9743fc33c592a7ff12c6bcbd
-7 包内 app.tgz      md5 ad690f7bc19526db8022c23fe2969fa8   = -7 manifest.checksum
qa/legacy-cmd/common.from-6  sha256 fa434ac2…（= -6 包内原物，见上）
-6 vs -7 全树 diff 结果：仅 cmd/common、cmd/main、manifest、app.tgz(内 ui/index.cgi) 四处不同
```

### 12.2 我重跑的日志（`qa/round5-rerun/`，冻结日志已还原）
```
e3ec4a510f99c42333863924629935142cb31b4298dd811e13e59681b6313d67  exec-A.rerun.log   (26/0)
108fcbd446fea4fd1f183d2299a16c30680a97d4f9c5a0ad6facca3f451900b2  exec-B.rerun.log   (30/0)
73689491dc74edc525722b19bb3c0f45ca953a42a6447ac1858af1c0526b6f4a  exec-C1.rerun.log  (18/0)
146b00f3f6f8cf6d4dec2df3501af07c2c15732560e45bec23ac4beff2d34969  exec-C2.rerun.log  (26/0)
0178552c916003a6ec1cbc80e211f3897dde946446a4c1630ad2875e818a3071  exec-D.rerun.log   (3/1)
9d174d13ad2a95e02a71f7b35e0f064698a40afe72151d6f3a0e30b0403ac1b8  exec-E.rerun.log   (21/0)
012661d7db9c528d0270544660a020f88a846de9826a2a7d7927f6edc76164eb  exec-F.rerun.log   (16/0)
abfbcea068b08ea1896e92d1f034b6c16045d0b403d3bfdd3c0b9431911a1e80  exec-G.rerun.log   (29/0)
2fc957513810a15f346b9bd9d7c597ce3c26949868b1b09ae837e574684073e5  exec-H.rerun.log   (69/0)
4b49888f03ed8738db35d9b5a69db0765a1b9359735a13f7b6e8db338d7981a6  repro.rerun.log    (17 OK/0 BAD)
```

### 12.3 我的手工 harness 与变异体（`qa/round5-rerun/`）
```
ceb7a72528a1dfb22eb0bad6039cb19b86ceb1a2aac776f0734ecbc7787ba036  h13.sh
10ac2b0d72c694fc5940b816561b2a498dbb344c71db467599b3483890a6b18a  h14.sh
b720e246e9ece790a7550e9e9334a7590bb2bd23b5118536f30e03940fb28fa6  h15.sh
4f35a8f01107170e9aa7eb00a8848cbf3523b4a24b88c283296f8cedc7fbaf39  h16_manual.sh
727d5d0273e7db0a1c85b41663ad622cf16092372d3014248b6aa4e39c3a1d86  h17_manual.sh
568f0da73a7e6a0705becb3bb6d935566d0a5cd44dc91bed732161c61b38187e  token_leak.sh
7bf14d6e143611d3dd0a60419b81cac719b0ec6442e4368c22fcad11d627a86f  symlink.sh     (T1–T4)
10752e5e67ca9b2c673dba3f38261013e596be9b70e991a5fb5fcd864c596862  symlink3.sh    (install_callback 经符号链接)
ec59abf3c0dd3c48947d3cb5262008d1e17ce4b333a2b76cf3bbe7cc00d75227  halfinstall.sh (§8.1 半装态：设置写失败)
785788725edb7ac480bc06fb4a37ccdb876b42c664a1d4b49372e51bad89cb37  halfstart.sh   (§8.1 半装态：用户点启动后到底发生什么)
4c1bc10079acf704949af3a304e3a348d41fa458d2e7360e923b181549194b14  halfstart.log  (halfstart.sh 的输出，两个子场景)
e57edc7e68f47478b5a59bde35a8905d9d68ce2b788c93b1f749c4ebadfa3fc3  confwin.sh     (§6 N5-2 探针)
53767a1439dfd758aa4e51efe77468ae6558e36b924874d92ad7db81a9d8c1d0  leak.sh        (§6 N5-1)
42fdffcc19c684a5608168cf7545a89e6fe1493a2f8e419fa0efc4c6d05be5c0  acl.sh         (§10-2 权限继承矩阵)
2a11f296dac5f3a01c978eba682e028dbb4bd951a5636e132704861007a76332  symlink2.sh    (辅助：符号链接排查，未直接用于结论)
4c2c249b0ff2ce9eb14c8e85988a72feac67d268367a25c309f01efefc1b3432  dbg.sh         (辅助：调试脚手架，未直接用于结论)
e22a18bffb9bd05986b89bec10c9b05206dc55f54049940dc89f9c3b41d3bbf2  mutants/common.mutA
4b7d587dbbed47402c4a23e220f7c65578db0cb669f1f06ef016f4f6813fa57b  mutants/common.mutC
fdf1d000574744630510d72765875ac30f0e700de018fd9396933000dc377844  mutants/index.cgi.mutB
2432c80ae912c932f4677747b5fa4e2fe98bf66e4a44fdf8445350698ac5d123  mutants/index.cgi.mutD
0e7290ff94c5fca866e0d55b7538a263049921b72609fba15aaae980292311cf  mutants/main.token-in-argv
```
> `qa/round5-rerun/` 是新增目录，`make-index.py` 不会索引它 → `--check` 仍为 **OK**（我复验过）。

---

## 13. 我**没能**验证的项（不要把沙箱结论当已验收）

| # | 项目 | 原因 |
|---|---|---|
| V1 | 真机应用中心对 `exit 1` 回调的表现（是否展示 `TRIM_TEMP_LOGFILE`、是否回滚、UI 文案） | 需真机 root + UI |
| V2 | 真机 `/vol4/@appshare/openp2p` 上"新文件是否继承父目录权限"（§10-2） | 该目录属 `openp2p:openp2p` 700，我非 root，只能只读探测；我在**同文件系统的兄弟目录**实测到了该行为 |
| V3 | 真机 umask（root 启动 `cmd/main` 时的实际 umask） | 无法在真机取到 root 进程的 umask；影响 §6-N5-2 的窗口位宽（644 vs 600） |
| V4 | 真机 NAS 重启后自启、应用中心安装/升级/修复/卸载全流程 | 需重启机器 |
| V5 | i386 原生执行（块 D 的那 1 条 FAIL） | 本机无 386 内核；qemu-i386 下**官方 Go 386 二进制同样崩**，故不能据此判定包损坏（我复核了 exec-D 的这个对照实验） |
| V6 | arm 真机 | 无 arm 设备。包内只带 `bin/openp2p_{aarch64,armv7,i386,x86_64}` 四个二进制；`detect_cpucore` 把 `armv8l` 映射到 `armv7`（`common` 里这条我[读到]过，但**没有 arm 设备实测**） |
| V7 | 跨用户（root 进程）的 `is_our_pid` / `proc_exe_is_bin` 退路（argv0 判据） | 非 root 无法构造跨 uid 现场（`repro.sh` R4 用 `exec -a` 同 uid 伪装近似覆盖） |
| V8 | `hidepid=2` 等非常规 `/proc` 挂载 | 本机默认挂载 |
| V9 | 真机 `TRIM_*` 变量的真实取值（我只用固定值覆盖验证了"被覆盖时不误判"） | 需真机 root |
| V10 | ENOSPC（磁盘真满）路径 | 无 quota/mount 权限，用"目录不可写"近似 |
| V11 | 真机两个 root 残留实例（PID 2795664 / 2800553）能否被新版 `stop` 一次清掉 | **我无权限 kill**（如实登记，不在这上面耗时） |

---

## 14. 交付前建议处理清单（按优先级）

| # | 项 | 类型 | 建议 |
|---|---|---|---|
| Q1 | N5-5/N5-6：`repro.sh` 横幅与断言文案仍写 `-6` | 证据卫生 | 改成 `-7`（或动态取版本），并让 `repro.log` 首行自证被测产物 |
| Q2 | N5-1：非法 Token 明文进 0644 日志 | 产品（低危） | 不回显原值 / 用 `mask_token` 脱敏；补一条"非法输入不进日志"的用例（现有 TC-14/21 只覆盖合法 Token） |
| Q3 | N5-2 + §10-2：含 Token 文件的 0600 由 `umask` 保证（在 @appshare 树上 umask 被文件系统吞掉） | 产品（低危） | 四个写入点改成显式 `chmod 600` 后再写内容；并做 §11-7 的真机探测 |
| Q4 | N5-3：回调失败提示用 `>` 截断进度文件、且无 stderr 抑制 | 产品（低危） | 改 `>>`；重定向加 `2>/dev/null` 或 `|| true` |
| Q5 | N5-4：`save` 失败文案硬编码"应用未被改动" | 可维护性 | 由 `was_running/stopped` 推导 |
| Q6 | §8.1 文案 | 文案 | 安装/升级失败提示补"二进制已部署、仅设置未写入，请检查权限后用『修复』重试" |

**结论重申**：`Q1–Q6` 无一条阻塞 `-7` 上真机冒烟；`-7` 的硬绑定与 235 条断言我已独立复现，可作为当前交付基线。
