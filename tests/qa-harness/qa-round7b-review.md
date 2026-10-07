# 第 7b 轮 · 对抗性复验（定向）—— openp2p_3.25.11-10_all.fpk

- 角色：`qa`（只审不改）。对象：`dist/openp2p_3.25.11-10_all.fpk`
  sha256 `4b970e66…d6e0` / md5 `ee7a6e56…52d2` **实测复算一致**；包内 `manifest.checksum`
  `df9e8fdc…` = 实测 `md5(app.tgz)` ✓；`diff -r pkg10/cmd src/openp2p/cmd` **无输出（逐字节一致）**；
  `-10` 相对 `-9` 仅 `cmd/common` 一个文件不同（无越界）。
- 纪律：破坏性实验全在 `/tmp/qa10/` + `unshare -rmn`；未读写 `/var/apps`、`/volN/@appshare` 真机内容。

---

## 1. 裁定

**有条件可以给陌生人用；阻塞项 0 条。** 上一轮唯一阻塞项 **B3' 已真正堵住**，N5/N6/N7/N9/N10 五条
加固逐条生效（均独立复现，见 §2）。但我用定向攻击在**新代码**里挖出 4 条**非阻塞**问题（N11–N14），
其中 **N11 是 B3 同类的“无界挂死”**，只是触发需要能往锁目录里写东西——**若 fnOS 以 umask 0/002 启动
应用，则普通本机用户即可触发**（实测锁目录 777/775）。建议随下版一并修；不阻塞交付。

## 2. 我实际做的证伪实验清单（命令 + 观测）

### 2.1 声称 1（B3'）：陈旧锁 + 删不掉 → 有界；注入点可用 ✔（试打穿：部分成功，见 2.5）
```bash
# 只读 mount + 陈旧锁（无 owner），-10 vs -9（legacy-9-cmd），log 行数=忙等判据
unshare -rmn bash /tmp/qa10/h.sh
# v10 ticks=600 timeoutrc=124 wall=8.00s loglines=10  errbytes=864   ← 限频、非忙等
# v9  ticks=600 timeoutrc=124 wall=8.00s loglines=1039 errbytes=0    ← 原忙等（约 130 行/秒）
# v10 ticks=15  timeoutrc=0   wall=2.88s  out=rc=1 loglines=5        ← 总时限真的累得到 ✔
# v9  ticks=15  timeoutrc=124 wall=8.00s                             ← 注入点被 continue 旁路
```
**打穿失败**（各 ~2.9s 返回 rc=1，errbytes=0）：owner=活 pid / 死 pid / 垃圾串 / 权限000 / 悬空符号链接；
owner 是目录（rc=0 立即）。活进程持有超龄锁 → **不夺锁**（N9 ✔）。

### 2.2 声称 2（N5/N6，`remove_data_dir` 收窄）：该删的仍删、该拒的真拒 ✔
```bash
bash /tmp/qa10/e.sh   # 每条 errbytes=0，无裸错误
```
| 场景 | 结果 |
|---|---|
| 真机形态 `…/@appshare/openp2p`（经 `$APPDIR/shares/openp2p` 链接）| rc=0 删净 ✔ |
| `APPDIR` 含尾斜杠 / 相对路径 / 路径含 `//` | rc=0 删净 ✔ |
| 真实目录（非链接）/ `@appdata` 形态 | rc=0 删净 ✔ |
| 链接 → `$APPDIR/target`（N5 旧洞）| **rc=1 保留** ✔（不再误删安装目录）|
| `$APPDIR` 本身是符号链接（N6 旧误判）| **rc=0 删净** ✔ |
| 链接 → 工作区外 / 别的应用 / `@appshare` 父目录 | rc=1 保留 ✔ |

### 2.3 声称 3（N7，符号链接 config.json）：**意图达成，但会写到数据目录之外**（见 N14）
```bash
bash /tmp/qa10/f.sh
# 链接指向数据目录内 realconf.json → rc=0，链接保留、真实目标更新 ✔（N7 修好）
# 链接指向 /tmp/x.json（已存在，用户内容）→ rc=0，Token 被写进该外部文件（grep 命中 1）
# 链接指向数据目录外不存在路径 → rc=0，在外部新建了带 Token 的文件
# 链接 = 符号链接环 → rc=1 无泄漏；正常情况 stderr 无 Token、权限 600 ✔
```

### 2.4 声称 4/5（N9/N10）：属主活则不夺锁、普通文件占用主动清理 ✔
见 2.1、2.5；I5d/I5e 自测对照也证实。

### 2.5 新发现（打穿了）

**N11【非阻塞·高危 · “永不返回”同类】`owner` 被做成特殊文件 → `tr` 永久阻塞。**
```bash
unshare -rmn bash /tmp/qa10/b2.sh
# owner=符号链接→/dev/zero   timeoutrc=124 wall=8.00s  ← 永久挂死
# owner=符号链接→/dev/urandom timeoutrc=124 wall=8.00s  ← tr 无限输出数字流
# owner=命名管道(FIFO)        timeoutrc=124 wall=8.00s  ← open 阻塞等写端
# owner=符号链接→FIFO         timeoutrc=124             ← 同上
```
根因：`owner="$(tr -dc '0-9' < "${LOCK_DIR}/owner" 2>/dev/null)"` 对“无限/阻塞输入”没有上界。
可达性：需能往 `${PKGVAR}/.o2p.lock` 里造条目；实测锁目录 mode = `0777 & ~umask`
（`umask 000→777 / 002→775 / 022→755`，`mkdir` 未套 `umask 077`）→ **若应用以 umask 0/002 启动，
本机普通用户即可 DoS start/stop**。

**N12【非阻塞·信息泄漏 · 新引入】`owner` 缺失时裸错误打到 stderr。**
```bash
# 陈旧锁、无 owner（-9 遗留 / mkdir 与写 owner 之间崩溃）
bash /tmp/qa10/pkg10/cmd/main start   # stderr 97 字节：
# /tmp/qa10/pkg10/cmd/common: line 444: /tmp/qa10/G/var/.o2p.lock/owner: No such file or directory
```
根因：`< file 2>/dev/null` 重定向顺序（`<` 先失败再轮到 `2>`）——与本文件 `log_msg` 注释里
记录的“`2>/dev/null` 必须在前”是同一纪律，此处漏了。有 owner 时 stderr=0。

**N13【非阻塞】`O2P_LOCK_MAX_TICKS` 未做上界 → 溢出时超时判据失效。**
```bash
# 全数字且 > INT64_MAX：9…9(23位) / 9223372036854775808
#   → timeoutrc=124，4s 内 stderr 1880 字节全是
#   "common: line 472: [: 999…: integer expression expected"（每 0.2s 一条，泄漏脚本路径）
# 其余：空/abc/-1/1e9/" 5"/"+5"/0x5/5.5 → 回落 600（释放测试证明：rc=0≈2.05s，有界）
#       0→0.01s rc=1、1→0.01s、5→0.82s、007→1.23s（按十进制 7 计）✔
```

**N14【非阻塞·语义】`ensure_token_in_conf` 跟随指向数据目录**之外**的符号链接**，把 Token 写到该
外部路径并覆盖其内容（原内容仅存于 `.bak`/`.broken`）。判断：**应当拒绝**——应用数据目录之外
不是它该写密钥的地方；建议限定解析后的 `CONF` 必须落在 `readlink -f "$DATA_DIR"/` 之内。

**打穿未遂**：`i=0; continue` 的“删成功→被抢走”饥饿循环**未能复现**（`c2.sh`：陈旧 mtime 重造者
8 次试验下 acquire 均先抢到锁 rc=0；新鲜锁抢占者 3/3 精确在 25 tick≈4.89s 返回 rc=1）。
分析结论：`continue` 只在**确认锁目录真的消失**（`[ ! -d ]`）后发生，紧随的 `mkdir` 通常先赢；
且 `waited` 不重置 → 现实“被活锁抢占”路径**总时限照常累加**，不会饿死。

### 2.6 作者自测与泄漏复核
- `OPENP2P_ROOT=… bash qa/exec-I.sh` → **30 PASS / 0 FAIL**（独立重跑复现）。覆盖 B3'/N5/N6/N7/N9/N10，
  **未覆盖** N11/N12/N13/N14（盲区）。
- 新日志文本（“普通文件占用已清理/活进程持有/清理失败/超时”）**不含 Token、不含裸 stderr 泄漏**；
  §2.3 正常路径 stderr 无 Token、文件权限 600 ✔。唯一新泄漏是 N12 的**脚本路径**。

## 3. 若要改，按优先级（最小修改点）

1. **N11（先修）**：`owner` 读取加双保险——`( umask 077; mkdir "$LOCK_DIR" )`（或 `chmod 700`）；并把读取改成有界：
   `owner=$(cat "${LOCK_DIR}/owner" 2>/dev/null | head -c 32 | tr -dc '0-9')`（`head` 保证不死读 /dev/zero、FIFO 仍会阻塞故再配 `timeout 1 cat …`）。
2. **N12（一行）**：`owner="$(tr -dc '0-9' 2>/dev/null < "${LOCK_DIR}/owner")"`（`2>/dev/null` 提到 `<` 之前）。
3. **N13（一行）**：把 `max_ticks` 夹到合理上界，如 `case "$max_ticks" in ''|*[!0-9]*) max_ticks=600;; esac; [ "$max_ticks" -le 600 ] 2>/dev/null || max_ticks=600`。
4. **N14（加判断）**：解析出 `realconf` 后，若不在 `readlink -f "$DATA_DIR"/` 内则 `log_msg` 拒绝并 `return 1`。
5. 收尾：把 N11–N14 写进 `qa/exec-*`，避免下轮返工。
