# 可移植性阻塞项修复复核（第 7 轮 · 对抗性） —— openp2p_3.25.11-9_all.fpk

- 角色：`qa`（只审不改，**报告型**）
- 日期：2026-10-07（+0800）
- 被审对象：`dist/openp2p_3.25.11-9_all.fpk`
  - sha256 `6bbc7ae0b1c65df8240eb7421e0c8fa915b919e50ab9654cea6ca51ac414d5c4`（**实测复算一致**）
  - md5 `86f5ead6fff63946c3608f94216d507e`　size 16387068 B
  - 包内 `manifest.version = 3.25.11-9`、`checksum = d4dde19e2c8616cdcdb99fdff86401b7` **= 实测 `md5(app.tgz)`** ✓
- 上轮基线：`qa/qa-portability-review.md`（B1/B2/B3 三条阻塞项，裁定"有条件可以"）
- 本轮作者自测：`qa/exec-I.sh` + `exec-I.log`（21 PASS/0 FAIL）—— 我**独立重跑复现**（21/0），但**不信自述**，另设计了 20+ 个新用例试图打穿。
- 纪律声明：工作区（`projects/`、`dist/`、`teams/`）**只读**；破坏性实验一律在 `/tmp/qar7/`（并配合 `unshare -rmn` 私有 mount/net namespace）。**未读写 `/var/apps`、`/volN/@appshare` 真机内容**（仅 `ls -l`/`readlink` 只读观测）。事故披露见 §7。

---

## 1. 结论

**有条件可以给陌生人用；阻塞项 1 条**（B3 只修了一半，仍有一条会挂死的残洞；触发条件比原 B3 窄，但正是原 B3 点名的"只读/磁盘异常"）**。另建议同批处理 1 条交付卫生项（仓库自测脚本对 -9 报 2 个失败）。**

- **B1（卸载删配置）**：核心已修好。符号链接、路径穿越、白名单外目标、全盘/根目录、其他应用数据目录、删到一半失败、只读目标 —— **8 类打穿尝试全部被守住**（详见 §4.1）。仅剩 2 个非阻塞瑕疵（白名单 `$APPDIR/*` 过宽、`$APPDIR` 是符号链接时"误判为拒绝"）。
- **B2（Token 合并写入）**：核心已修好。空文件/空白/数组/符号链接/只读/`Token:0`/字符串 Token/非法 Token/并发 120 写 —— **没有丢 `apps[]`、没有写出非法 JSON、没有放宽权限**（详见 §4.2）。剩 3 个非阻塞瑕疵。
- **B3（启动锁挂死）**：**只修了"锁目录建不出来"这一半**（这条确实从"永不返回"变成立刻 `rc=1`）。**"锁目录已存在且删不掉"的另一半仍是死循环**，而且是**无 `sleep` 的忙等**：实测 8 秒刷 1045 行日志、10 秒刷 1309 行、`main start`/`stop`/界面 `rc=124` 永不返回（§2 B3、§4.3）。

---

## 2. 阻塞项

### B3'【阻塞 · 条件触发】陈旧锁 + 锁目录删不掉 → `start`/`stop`/界面仍然无限挂死（忙等，比原版更耗 CPU）

**现象**：`$PKGVAR/.o2p.lock` 已存在、`mtime` 早于 60 秒（陈旧）、但 `rm -rf` 删不掉时，`acquire_lock` 进入**无 `sleep` 的死循环**：每次都判定"陈旧"→ 清理失败 → `i=0; continue` → 直接回到下一轮，**既不累加 `waited`、也不限时、也不 sleep**。`main start`/`stop` 与界面请求（都走 `main`）全部永不返回。

**代码根因**（`src/openp2p/cmd/common: 390` 起，`acquire_lock`）：

```sh
while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    if [ ! -d "$LOCK_DIR" ]; then            # A) 建不出来 → 快速失败（已修好）
        log_msg "❌ 无法创建运行时锁目录…"; return 1
    fi
    if [ "$((i % 5))" -eq 0 ]; then
        if mtime=$(stat -c %Y "$LOCK_DIR" 2>/dev/null); then
            age=$(( $(date +%s) - mtime ))
            if [ "$age" -gt 60 ]; then
                log_msg "⚠️ 清理陈旧启动锁（已存在 ${age} 秒）"
                rm -rf "$LOCK_DIR" 2>/dev/null   # ← 删不掉时下面这行是致命的
                i=0
                continue                          # ← 跳过 waited++ 与 sleep，i 归零后又命中 i%5==0
            fi
        fi
    fi
    i=$((i + 1)); waited=$((waited + 1))
    if [ "$waited" -ge "$max_ticks" ]; then ...return 1; fi
    sleep 0.2
done
```

失败分支（A）修好了；**成功进入 `if` 后 `rm` 失败**这条路径没有出口：`continue` 让 `max_ticks`（600×0.2s=120s）永远累不到。

**触发条件**（以真机 root 身份复核过）：`$PKGVAR` 所在文件系统对 root 也拒绝 `unlink`，且里面残留一个 >60s 的锁目录。现实中：
- **只读挂载**（EROFS）—— 正是原 B3 点名的"只读"场景；
- 锁目录是**挂载点**（EBUSY）；
- 锁目录里有 **immutable** 文件（`chattr +i`）/ `@appdata` 卷 `errors=remount-ro`。

> 注意区分：**不是**"父目录权限位只读"。真机应用以 **root** 跑，root 有 `CAP_DAC_OVERRIDE`，`chmod 500` 的父目录照样删得掉（我在 `unshare -rn` 里当 uid 0 时 `rm` 就成功了，没复现）；必须把整个 FS 挂成 `ro` 才卡住 root。这点我已实测区分（§4.3）。

**证据（命令 + 观测）**：

```bash
# 非 root（uid 868）下，父目录 chmod 500 即可让 root 之外的身份复现（§4.3 E3-e）
# 更忠实的是把 PKGVAR 放到只读 bind mount 上，以 root 复现：
unshare -rmn bash -c '
  mkdir -p /tmp/qar7/e5/rofs/var/.o2p.lock; touch -d "10 minutes ago" /tmp/qar7/e5/rofs/var/.o2p.lock
  mount --bind /tmp/qar7/e5/rofs /tmp/qar7/e5/rofs; mount -o remount,bind,ro /tmp/qar7/e5/rofs
  rm -rf /tmp/qar7/e5/rofs/var/.o2p.lock        # → rm: cannot remove ...: Read-only file system ; rc=1 残留=yes
  TRIM_APPNAME=openp2p TRIM_PKGVAR=/tmp/qar7/e5/rofs/var OPENP2P_APPROOT=/tmp/qar7/e5/app \
    LOG_FILE=/tmp/qar7/e5/o.log timeout 10 bash /…/src/openp2p/cmd/main start; echo rc=$?
'
```

原始观测：

```
remount ro ok
rm: cannot remove '/tmp/qar7/e5/rofs/var/.o2p.lock': Read-only file system
rm rc=1 残留=yes
--- main start（timeout 10s）---
rc=124（124=挂死未返回） 耗时=10s 输出字节=0
日志行数=1309
--- 同样场景下 stop ---
stop rc=124
```

非 root 侧面复现（父目录 500，`rm` 失败）：

```
E3-e 陈旧锁+删不掉: timeout rc=124  输出=
8 秒内日志行数=1045（若巨大 = 忙等死循环）
日志前两行: …⚠️ 清理陈旧启动锁（已存在 600 秒）|…⚠️ 清理陈旧启动锁（已存在 600 秒）|
```

**影响**：用户/界面看到"点启动没反应"，进程 100% CPU 空转、日志以约 130 行/秒膨胀（若 LOG_FILE 落在可写盘，可把盘刷满——从"挂死"升级为"挂死 + 塞满磁盘"）。**这正是原 B3 想要根治的症状**。

**最小修复建议**（改 2 行）：只有**确认锁真的没了**才 `continue`/清 `i`；否则落到计数与 `sleep` 分支：

```sh
if [ "$age" -gt 60 ]; then
    log_msg "⚠️ 清理陈旧启动锁（已存在 ${age} 秒）"
    rm -rf "$LOCK_DIR" 2>/dev/null
    if [ ! -d "$LOCK_DIR" ]; then i=0; continue; fi   # ← 删成功才重置；删不掉就往下走计数/超时
fi
```

（可选加固：清理连续失败 N 次后直接 `return 1` 并写明"锁目录无法清理，疑似只读挂载/被占用"。）

---

## 3. 非阻塞问题（按严重度排序）

### N1【高 · 交付卫生】仓库自带自测 `test/simulate-fnos.sh` 对 **-9 会报 2 个 FAIL**，README §七却让用户跑它

- **现象**：实测 `bash test/simulate-fnos.sh` → `通过 26 项，失败 2 项`、`exit 1`。
- **是什么**：第 8 步 "清空 Token 后应拒绝启动" 的断言**已过时**（它期望"无 Token 就不启动"）。但 `-8` 的 B8 已把行为改成"**无 Token 也照常启动**"（`main:100-101`），于是同一步内自相矛盾：前半句 `start(no-token) 优雅返回 0` ✅，后半句却要 `status=3`/`nprocs=0` ❌。
- **不是安全回归**：我单独验证了"旧 Token 不会复活"——清空 `settings.conf` 后 `main start` 会把 `config.json` 的 `Token` 改写成 **0**（`尚未配置 Token` 日志 1 条），进程按设计照起（§4.3 E6）。
- **证据**：
  ```
  === 8) 清空 Token 后应拒绝启动（settings.conf 为唯一权威）===
     ✅ start(no-token) 优雅返回 0
     ❌ status exit=0（旧 Token 复活了）
     ❌ 竟然起了进程（nprocs=1）
  ```
- **建议**：把第 8 步断言改成"清空后 `config.json.Token == 0`、进程照起、`status==0`"（这才与 B8 一致）；否则陌生人按 README 跑自测会以为包坏了。

### N2【中 · 可移植性】仓库内 `tests/qa-harness/exec-A…H.sh` **9/9 硬编码 `/path/to/...` 与 `-8` 包名**，陌生 clone 跑不起来；本轮 `exec-I.sh` **不在 git 仓库里**

- 证据：`grep -l '/path/to' tests/qa-harness/exec-*.sh` → A/B/C1/C2/D/E/F/G/H 共 9 个；`exec-H.sh:14` 还硬编码 `/path/to/workspace/teams/.../qa`。
- `exec-I.sh` 自身路径解析（`find_root`）**是好的**：我把它拷到 `cwd=/` 且不带 `OPENP2P_ROOT` 跑，仍 `rc=0 / 21 PASS`（§4.5）。但它位于 **agent 工作区** `teams/…/qa/`，`git ls-files | grep -c exec-I` = **0** —— 陌生人 clone 仓库根本拿不到这个执行器。
- 只有 `test/simulate-fnos.sh` 是自解析的（`PROJ="$(cd "$(dirname "$0")/.." && pwd)"`，取 `dist/` 最新 fpk）——但它对 -9 报 2 失败（N1）。
- **建议**：把 `exec-I.sh` + `legacy-8-cmd/` 快照纳入仓库（与 `tests/qa-harness/` 同级或替换旧的占位脚本）；老脚本统一改成 `ROOT="${OPENP2P_ROOT:-…自解析}"`。

### N3【中 · 文档】README 与 docs 仍写 **-8**，且**全仓库没有任何地方记录 -9 的哈希**

- `README.md:6`、`README.md:16`：`openp2p_3.25.11-8_all.fpk`（交付物实为 -9）。
- `docs/VALIDATION.md:3,13`：`v3.25.11-8`。
- 全仓库 grep 不到 `6bbc7ae0…`（-9 的 sha256）→ 陌生用户无法核对下载物。
- **建议**：README/VALIDATION 版本号随 `build.sh` 顶部 VERSION 走；在 Release 说明或 VALIDATION 里补 -9 的 sha256/md5。

### N4【低 · 隐私】提交进仓库的日志残留作者真实网段 `10.<lan>.165.211`，与 VALIDATION.md 的"已脱敏"声明相冲突

- `tests/qa-harness/exec-B.log:48`、`tests/qa-harness/round5-rerun/exec-B.rerun.log:48`：`INFO PublicIP:10.<lan>.165.211`。
- `docs/VALIDATION.md:7` 声称"开发机相关信息（主机名、账号名、公网 IP）已做脱敏替换"——这个 10.x 私有地址没脱敏（RFC1918，危害低，但自相矛盾）。
- **包内干净**：`grep` -9 解包树（含 `app.tgz`）无 `/Users/`、`/home/`、`vincent`、`appuser`、`ZD3XW7`、`10.<lan>.` 等（§6）。
- 作者真实主机名 `my-fnos` **未**出现在仓库任何文件里（grep 命中 0）。

### N5【低 · 加固】`remove_data_dir` 白名单里 `"${APPDIR}"/*` 过宽：`$APPDIR` 下**任何**子目录都能被删

- 证据（`/tmp` 沙箱，§4.1 E1-2）：把 `shares/openp2p` 指向 `$APPDIR/target`（应用的安装目录）→ `remove_data_dir` 返回 0 并把整个 `target/` 删掉。
- 现实可达性：需要有人把该符号链接指过去（root 权限），fnOS 不会这么建 → **低危**。但语义上它允许删"应用目录下任何东西"，比"只删数据目录"宽。
- **建议**：把第一分支收窄为 `"${APPDIR}/shares/${APPNAME}"`（精确匹配），保留 `*/@appshare/<app>`、`*/@appdata/<app>`。

### N6【低 · 误判】`$APPDIR` 本身是符号链接时，`remove_data_dir` 会**拒绝**删除（"删配置"静默变"保留"）

- 证据（§4.1 E1-8）：`APPDIR=.../applink`（→ `.../appreal`）、`DATA_DIR=.../applink/shares/openp2p` 时，`readlink -f` 给出 `.../appreal/shares/openp2p`，与字面 `${APPDIR}/*` 不匹配（也不含 `@appshare/openp2p`）→ 拒绝、返回 1。
- 真机无碍：`/var/apps` 是**真实目录**（实测 `readlink -f /var/apps` = `/var/apps`），且真机真实路径以 `/@appshare/openp2p` 结尾，命中第二条白名单。
- **建议**：把 `${APPDIR}` 也先 `readlink -f` 规范化后比对。

### N7【低 · 语义】`ensure_token_in_conf`：`config.json` 是符号链接时会被**替换成普通文件**（原目标文件保留）

- 证据（§4.2 E2-d）：`config.json -> realconf.json` → 改写后 `-L config.json` 为假，`realconf.json` 内容不变。是"脱链"而非"删数据"，低危。
- 另：`config.json` 权限 400（只读文件、目录可写）时仍会被改名覆盖并 `chmod 600`（§4.2 E2-e）；目录只读时才失败并保留原文件（正确）。

### N8【低 · 语义】`config.json` 有 `apps` 但**没有 `network` 段**时，`apps` 会被移到 `config.json.broken`，活动配置换成最小配置

- 证据（§4.2 E2-m）：原文件保留在 `.broken` 并有日志，但运行中的 openp2p 读的是新最小配置（`apps` 不在生效配置里）。
- 与 README §六"本封装**不会覆盖**你手写的 `apps`"存在措辞落差（虽未"覆盖"、但"移出"了）。openp2p 自身总会写 `network`，现实概率低。

### N9【低 · 观察】`acquire_lock` 的"陈旧"只按**创建时刻**算，不刷新；真正持有者 >60s 会被夺锁

- 证据（§4.3 E3-h）：A 持锁后把锁 `mtime` 改成 5 分钟前，B 调用 `acquire_lock` → B 清掉 A 的锁并成功获取（A 仍以为自己持锁）→ 这正是锁要防的"重复实例"窗口。
- 现实可达性：start/stop 持锁都在 ~15s 内，需异常慢（如 `$BIN -v` 卡住）才会 >60s → 低危。

### N10【低 · 观察】`$PKGVAR/.o2p.lock` 是个**普通文件**时，`acquire_lock` 快速失败但**永不清理**

- 证据（§4.3 E3-g）：`rc=1`、6ms 返回、日志"无法创建运行时锁目录"，但那个同名文件一直在 → start/stop 被**永久**挡住，需人工删。建议对"同名非目录"也给一条明确指引或尝试 `rm -f`。

---

## 4. 三条修复的独立验证结果（含"试图打穿却没成功"的实验）

### 4.0 双源确认 + 越界检查

| 检查 | 命令 | 结果 |
|---|---|---|
| `-9` 包 `cmd/` 与源码树逐字节一致 | `diff -r /tmp/qar7/pkg9/cmd src/openp2p/cmd` | **无输出（IDENTICAL）** ✓ |
| `wizard/`、`config/` 一致 | `diff -r` | 无输出 ✓ |
| `manifest.checksum` 自洽 | `md5sum app.tgz` vs manifest | 相等 `d4dde19e…` ✓ |
| **越界检查**：-9 相对 -8 的差异文件 | `diff -rq pkg8 pkg9` | 仅 `cmd/common`、`cmd/main`、`cmd/uninstall_callback`、`manifest`、`app.tgz`（内容级 `diff -rq` 对解包后的 `app/` **无差异**，只是 gzip 元数据） → **恰好只含本次三条修复涉及的文件，无越界** ✓ |
| **四架构二进制 -8/-9 完全一致** | `md5sum` ×4 | `150c30a4…/802ff9a3…/4afa700d…/d658d53a…` 两包**逐一相同**，且与 `NOTICE` 记载一致 ✓ |

### 4.1 B1（`real_data_dir` / `remove_data_dir` / `uninstall_callback`）—— 打穿尝试：12 个用例，守住 10，暴露 2 非阻塞

| # | 攻击场景 | 期望 | 实测 | 判定 |
|---|---|---|---|---|
| E1-1 | DATA_DIR 链接指向工作区外 `…/outside` | 拒绝、不删 | rc=1，目标存活，日志"路径形态与 openp2p 不符" | ✅ 守住 |
| E1-2 | 链接指向 `$APPDIR/important` | 拒绝 | **rc=0，被删** | ⚠️ N5（`$APPDIR/*` 过宽） |
| E1-3 | DATA_DIR → `/` | 拒绝 | rc=1，`/etc` 存活 | ✅ 守住 |
| E1-4 | 链接指向 `…/@appshare`（父目录本身） | 拒绝 | rc=1 存活 | ✅ 守住 |
| E1-5 | 链接指向**别的应用** `…/@appshare/EasyTier` | 拒绝 | rc=1 存活 | ✅ 守住 |
| E1-6 | 链接指向 `…/@appshare/x/y`（两层） | 拒绝 | rc=1 存活 | ✅ 守住 |
| E1-7 | 正常真机形态 `…/@appshare/openp2p` | 删干净 | rc=0，目录删、链接清 | ✅ |
| E1-8 | `$APPDIR` 是符号链接 | 删干净 | **rc=1 拒绝**（目标保留） | ⚠️ N6（fail-safe 误判） |
| E1-9 | DATA_DIR 含 `..`（`app/../etc`） | 拒绝 | rc=1 存活 | ✅ 守住 |
| E1-10 | DATA_DIR 是真实目录 | 删干净 | rc=0 | ✅ |
| E1-11 | 目标 0500（删到一半失败） | 如实报残留 | **rc=1 + "数据目录未能完全删除"** | ✅ 不谎报 |
| E1-12 | DATA_DIR 为空串 | 拒绝 | rc=1 存活 | ✅ 守住 |
| 集成 | `uninstall_callback`（真机形态符号链接）删 token | 删净 + 如实日志 | rc=0，真实目录/链接都没了，`grep 314159265358` 0 命中，日志"已按用户选择删除配置…真实位置 …" | ✅ |
| 对照 | 旧实现（`legacy-8-cmd`）同场景 | 应留下 Token | Token 明文仍在数据卷（LEAK） | ✅ 用例有鉴别力 |
| 集成 | 「保留配置」分支 | 数据完好 | 数据完好，日志仅述"保留配置" | ✅（副作用见 N10/§7） |

**结论**：`rm -rf` 只此一处、白名单双层、删完自检、日志按实测说话 —— 核心目标达成，**没能把 Token 留住的打穿**。

### 4.2 B2（`ensure_token_in_conf`）—— 打穿尝试：13 个用例，守住 13，暴露 3 非阻塞

| # | 攻击输入 | 期望 | 实测 | 判定 |
|---|---|---|---|---|
| E2-a | 空文件 | 不覆盖、有记录 | rc=0，最小配置，`.broken` 留存 | ✅ |
| E2-b | 仅空白 | 同上 | rc=0，`.broken` 留存 | ✅ |
| E2-c | 顶级数组 `[1,2,3]` | 同上 | rc=0，`.broken=[1,2,3]` | ✅ |
| E2-d | 符号链接 | 不丢内容 | rc=0，符号链接被换成普通文件，**原目标文件内容不变** | ⚠️ N7 |
| E2-e | 只读文件 400 | — | rc=0，被覆盖 + `chmod 600`（目录可写故 `mv` 成功） | ⚠️ N7 |
| E2-f | 目录只读 500 | 保留原文件 | **rc=1，原文件不变，无 `.tmp` 残留**，日志明说 | ✅ |
| E2-g | `"Token":0` | 换值、保 `apps` | rc=0，`apps` 在 | ✅ |
| E2-h | `"Token":"123"`（字符串） | 改成不带引号数字 | rc=0，`"Token": 666`，`apps` 在 | ✅ |
| E2-i | `"Token":"abc"`（旧 O4 坑） | **不写坏 JSON** | **rc=1，原文件保持合法 JSON 不变**，无 `.tmp` | ✅（旧 O4 已被 `json_ok` 兜住） |
| E2-j | `apps` + 多个其他键 | 仅改 Token | 逐字节保留其余，仅 Token 变 | ✅ |
| E2-k | **120 个并发进程同时写** | 不丢 `apps`、合法 JSON | 最终合法 JSON、`apps` 在、无 `.tmp` 残留、权限 600 | ✅ |
| E2-l | 入参 `12a`（非数字） | 拒绝 | rc=1，文件未动 | ✅ |
| E2-m | 有 `apps` 无 `network` | 不覆盖 | rc=0，`apps` 移到 `.broken`、活动配置换最小配置 | ⚠️ N8 |

**结论**：**没有一次**丢 `apps[]`、写出非法 JSON、放宽权限或 unlink 用户文件；`.bak`（600）每次改写前都有。旧 O4（sed 把 `"Token":"abc"` 改坏）现被 `json_ok` 校验拦下。

### 4.3 B3（`acquire_lock`）—— 打穿：**命中 1 条阻塞残洞** + 若干有界行为

| # | 场景 | 期望 | 实测 | 判定 |
|---|---|---|---|---|
| E3-a | 父目录不可建（`/proc` 下） | 立即失败 | rc=1，**4ms**，日志可读 | ✅（原 B3 已修） |
| E3-b | 陈旧锁、可删 | 清理并获取 | rc=0，10ms，日志"清理陈旧启动锁（600 秒）" | ✅ |
| E3-c | 锁被另一进程持有，其释放后 | 等到释放再获取 | rc=0，耗时 1834ms（持有者 1.7s 后释放） | ✅ |
| E3-d | 新鲜锁、无人释放 | 有界（≤120s） | **rc=0，62s**（锁在 60s 变陈、被接管）→ 有界 | ✅（语义见 N9） |
| E3-e | 陈旧锁 + **删不掉**（父目录 500） | 有界失败 | **rc=124 忙等，8s 刷 1045 行日志** | ❌ **B3'** |
| E5 | 只读 FS + 陈旧锁，**root 身份** | 有界失败 | **`start` rc=124 / 10s，日志 1309 行；`stop` rc=124** | ❌ **B3'**（忠实现场） |
| E3-f | 锁 `mtime` 在未来 | 有界失败 | rc=1，122s（走满 120s 超时） | ✅ 有界 |
| E3-g | 锁位置是普通文件 | 快速失败 | rc=1，6ms | ✅（N10：永不清理） |
| E3-h | 活锁被"变陈旧"后 | — | B 清掉 A 的锁并获取（夺活锁） | ⚠️ N9 |
| E3-i | 4 进程并发抢锁 | 同刻仅 1 个 owner | 依次 `grabbed`，无重叠 | ✅ |
| E4-6 | 两进程并发 `main start` | 只起 1 个 | 日志"启动成功"×1 + "已在运行…跳过"×1，沙箱实例数 =1 | ✅ |
| E4-1..5 | start/status/stop 主流程（真二进制） | 正常 | start rc=0、status rc=0、重复 start 幂等、stop rc=0、停后 status rc=3 | ✅ |

**区分"权限位只读"vs"文件系统只读"**：在 `unshare -rn`（uid 0）里父目录 `chmod 500` 时 `rm` **成功**（root 有 `CAP_DAC_OVERRIDE`）→ 不挂死；只有把 FS 挂成 `ro`（`mount -o remount,bind,ro`）才遮住 root，见 E5。**所以 B3' 是真机 root 也会中的**。

### 4.4 信息泄漏检查

- `main start` 后 `grep 12345678` 日志命中 **0**（E4-7）。
- 三条修复的失败路径 stderr：`remove_data_dir`（白名单外）、`ensure_token_in_conf`（目录只读）、`acquire_lock`（父目录不可建）、`uninstall_callback delete`（LOG_FILE 不可写）→ **stderr 字节均为 0**（E7）。无 `cp: Permission denied` 之类裸错误。
- 新增的"真实绝对路径"只出现在**日志**（root 可读 `…/var/log/apps/openp2p.log`）与卸载日志（`数据目录真实位置 …`）里，非 stderr/非界面 → 可接受。

### 4.5 真机形态与自测可跑性

- 真机只读观测：`/var/apps`=真实目录，`/var/apps/openp2p/shares/openp2p -> /volN/@appshare/openp2p`，安装版本 `3.25.11-7`。
- `exec-I.sh` 自解析：拷到 `cwd=/`、不带 `OPENP2P_ROOT` 跑 → **rc=0 / 21 PASS**（`find_root` 有效）。
- `test/simulate-fnos.sh`：自解析有效（自动选到 -9），但 **2 FAIL**（N1）。

---

## 5. 文档-实现一致性核对表

| 文档原话（位置） | 实现事实 | 判定 |
|---|---|---|
| `README.md:6,16`：产物 `openp2p_3.25.11-8_all.fpk` | 交付物是 `-9`（sha256 `6bbc7ae0…`） | ❌ 版本号过期（N3） |
| `docs/VALIDATION.md:3,13`：`v3.25.11-8` | 现交付 `-9` | ❌ 过期（N3） |
| README §五：删除配置"连 Token 一起清掉"、"会真的删到数据卷上…已修复" | `uninstall_callback` 解析真实路径 + 白名单 + 自检，实测删净 | ✅ 一致 |
| README §六（Token 泄露）："只落在 `config.json` 和 `settings.conf`，两者 600，目录 go-rwx" | `ensure_token_in_conf`/`apply_settings_env` 均 `umask 077`+`chmod 600`；`ensure_data_dir` `chmod go-rwx` | ✅ 一致（O2 已修） |
| README §六（apps）："不会覆盖 `apps`：只替换 `Token` 字段（没有就插入），改写前留 `config.json.bak`，结果须是合法 JSON" | 三种分支：换 Token / 插 Token / 结构异常→`.broken`+最小配置；`.bak` 有；`json_ok` 守卫 | ✅ 基本一致（`无 network` 分支措辞见 N8） |
| README §六（点启动没反应）："看日志，最后几行会写明原因" | 多数路径写了；**但 B3' 路径日志只刷"清理陈旧启动锁"且永不返回** | ⚠️ 基本一致，B3' 修后更准 |
| README §六："保存时若在运行会自动重启" | `index.cgi` save/raw_save 用 `stop`+`start` 实现 | ✅ 一致 |
| README §七："运行时自测：`bash test/simulate-fnos.sh`" | 脚本能自解析并跑，但对 -9 **失败 2 项** | ❌ 不一致（N1） |
| README §八："253 断言 PASS / 0 FAIL、14 组对照组" | 未复核 253 口径；但自测脚本自身 -2 | ⚠️ 未核（与 N1 观感冲突） |
| README §三 路径表列 `config.json` 为"应用设置" | `install_callback` 不生成，首次 `start` 才有（O6） | ⚠️ 仍缺"首次启动后生成"一句 |
| README §一 三项可留空 / §一 架构 / §四 升级保留配置 | 与 `wizard/install`、`detect_cpucore`、`upgrade_callback` 一致 | ✅ 一致 |
| `wizard/uninstall` 字段 `openp2p_data_action`（keep/delete） | `uninstall_callback` 读同一变量名 | ✅ 一致 |

---

## 6. 隐私与可移植性核对

- **包内（`-9` 解包树 + `app.tgz`）**：0 命中 `/Users/`、`/home/<user>`、`vincent`、`appuser`、`ZD3XW7`、`10.<lan>.`、`3.25.11-8`。`NOTICE` md5 与包内四二进制一致 ✓。
- **仓库代码**：`src/**` 无个人残留；`node` 缺省回落 `fnos-nas` 是通用兜底（非作者机名）；作者真实主机名 `my-fnos` 在仓库 **0 命中**。
- **仓库测试日志**：`tests/qa-harness/exec-B.log:48`、`round5-rerun/exec-B.rerun.log:48` 含 `PublicIP:10.<lan>.165.211`（RFC1918）→ N4。
- **脱敏**：`docs/VALIDATION.md:7` 声明用 `my-fnos`/`demo-user`/`203.0.113.38`（TEST-NET-3）替换 → 大部分已做，仅 N4 一条漏网。
- **脚本可跑性实测**：
  - `test/simulate-fnos.sh`：自解析 ✅、跑起来（26 通过/2 失败）→ N1；
  - `tests/qa-harness/exec-A…H.sh`：9/9 硬编码 `/path/to` → **陌生 clone 跑不起来**（N2）；
  - `exec-I.sh`：自解析 ✅ 但**不在 git 仓库内**（N2）；
  - fpk 内 tar 记录属主为作者 uid `868/901`、`cmd/*` 为 `711`、`ui/index.cgi` 为 `700`：`tar` 以非 root 解包会警告 `Cannot change ownership to uid 868`（我在 userns 里复现），但 fnOS 安装器会归一化为 `root:root`+ACL（上轮 O7 已证）→ 非阻塞。
- **包内是否引用不存在的东西**：`cmd/*` 只依赖 `TRIM_*` 与常见外部命令（bash/hostname/readlink/stat/date/awk/sed/tr/cut/pgrep/nohup/sleep/timeout/python3（可选））；`manifest`/`config/resource`/`wizard` 字段与 fnOS 约定一致，未见指向不存在的文件。

---

## 7. 剩余未闭环项

1. **B3'（本轮唯一阻塞）**：`acquire_lock` 的"陈旧锁 + 删不掉"忙等死循环 —— 代码级可判定，非真机依赖，**建议同批修**。
2. **真机整机重启后自启**：无重启观测条件，只能在用户机器上验（沿用上轮未验证项）。
3. **真机安装/升级 `-9`**：真机现装 `-7`，`upgrade_init/callback` 的 fnOS 实参时序未在真机走通。
4. **真机卸载时 `openp2p_data_action` 的实际实参**：沙箱按约定显式传参；若真机不传则 `action` 缺省 `keep`（"删除配置"静默变"保留"，性质同 B1 但方向相反）——**真机验证一次即可闭环**。
5. **组网真正跑通**（`login ok`/`sdwan init ok`/端口转发连通）：沙箱用假 Token，未验证。
6. **armv8l/armv7/i386 原生运行**：仅在 x86_64 实跑。
7. **N1 自测脚本断言**：需作者把第 8 步改成与 B8 一致后复测。
8. **N4 脱敏**：需作者决定是否从提交日志里清掉 `10.<lan>.165.211`。

**过程纪律披露（如实）**：
- 所有破坏性实验只在 `/tmp/qar7/`（配合 `unshare -rmn`）内；**未读写 `/var/apps`、`/volN/@appshare`、`/volN/@appmeta` 真机内容**（仅 `ls -l`/`readlink` 只读）。
- 测试用**真机同款二进制**（`src/openp2p/app/bin/openp2p_x86_64`）跑 start/stop，放在 `unshare -rn` 私有网络里，避免与真机 `pid 405435` 抢 1025 端口；结束确认真机 `openp2p` 进程仍在、1025 仍在监听。
- 结束时清理 `/tmp/qar7`、`/tmp/fnos-sim`、`/tmp/qaI`、`/tmp/qar7cp`。**另清理了上一轮遗留的 `/tmp/port/`（上轮报告附录引用的沙箱）** —— 该目录在 `/tmp` 且属临时性质，但确实减少了上轮的一手证据，特此披露。

---

## 8. 我实际执行过的命令清单（可复算）

```bash
# 完整性 / 双源 / 越界
sha256sum dist/openp2p_3.25.11-9_all.fpk          # 6bbc7ae0… ✓
md5sum   dist/openp2p_3.25.11-9_all.fpk           # 86f5ead6…
W=/tmp/qar7; mkdir -p $W/pkg8 $W/pkg9
tar -xzf dist/openp2p_3.25.11-8_all.fpk -C $W/pkg8
tar -xzf dist/openp2p_3.25.11-9_all.fpk -C $W/pkg9
tar -xzf $W/pkg{8,9}/app.tgz -C $W/pkg{8,9}app
diff -rq $W/pkg8 $W/pkg9                           # 仅 common/main/uninstall_callback/manifest/app.tgz(元数据)
diff -r $W/pkg9/cmd src/openp2p/cmd               # 无输出 = IDENTICAL
for f in openp2p_x86_64 openp2p_aarch64 openp2p_armv7 openp2p_i386; do
  md5sum $W/pkg8app/bin/$f $W/pkg9app/bin/$f; done # 两包逐一同值
md5sum $W/pkg9/app.tgz | awk '{print $1}'          # = manifest.checksum d4dde19e…

# 真机只读观测
readlink -f /var/apps; ls -ld /var/apps/openp2p/shares/openp2p
grep version /var/apps/openp2p/manifest            # 3.25.11-7

# 独立重跑作者自测
OPENP2P_ROOT=…/projects/fnos-openp2p bash …/qa/exec-I.sh    # 21 PASS / 0 FAIL

# 我自建的对抗用例（脚本，均在 /tmp/qar7/）
bash /tmp/qar7/e1.sh          # remove_data_dir 白名单 12 例
bash /tmp/qar7/e1b.sh         # $APPDIR/* 过宽（删掉 target/）
bash /tmp/qar7/e2.sh          # ensure_token_in_conf 13 例（含 120 并发）
bash /tmp/qar7/e3.sh          # acquire_lock 10 例（含陈旧+删不掉忙等）
unshare -rn bash /tmp/qar7/e4.sh     # start/stop 集成 + 并发 + 卸载分支
unshare -rmn bash /tmp/qar7/e5.sh    # 只读 FS + 陈旧锁，root 身份下 start/stop 挂死
unshare -rn bash /tmp/qar7/e6.sh     # 清空 Token 后旧 Token 是否复活
bash /tmp/qar7/e7.sh          # 失败路径 stderr 泄漏 = 0
cd / && env -u OPENP2P_ROOT bash …/qa/exec-I.sh      # 自解析，rc=0
bash test/simulate-fnos.sh                           # 26 通过 / 2 失败（N1）

# 隐私 / 可移植性 grep
grep -rnE '/Users/|/home/[a-z]|vincent|appuser|10\.<lan>\.|ZD3XW7' $W/pkg9/   # 空
git ls-files -z | xargs -0 grep -nE '([0-9]{1,3}\.){3}[0-9]{1,3}' | grep -v …   # 命中 10.<lan>.165.211
grep -l '/path/to' tests/qa-harness/exec-*.sh        # 9 个
git ls-files | grep -c exec-I                        # 0（不在仓库）
```

**一句话交付结论**：B1/B2 的修复经对抗测试站得住，陌生人不会因此丢 Token 或丢 `apps[]`；**但 B3 只修了"建不出来"一半，剩下"陈锁删不掉"仍是忙等死循环**（只读/异常文件系统上 `start`/`stop`/界面照旧挂死），这是给陌生人用之前**唯一必须堵上**的口子；另请顺手把 `test/simulate-fnos.sh` 第 8 步的过时断言改掉（否则陌生人一跑自测就看到 2 个 FAIL）。
