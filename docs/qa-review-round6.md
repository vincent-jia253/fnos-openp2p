# QA 第六轮定向复核 —— openp2p_3.25.11-8_all.fpk

- 角色：`qa`（只审不改，**报告型**）
- 日期：2026-10-01（+0800）
- 被审对象：`dist/openp2p_3.25.11-8_all.fpk`
- 对照对象：`dist/openp2p_3.25.11-7_all.fpk`（已交付并通过真机验收）
- 上一轮报告：`qa/qa-round5-review.md`
- 缺陷台账：`bugs.md`（N5-1 ~ N5-6）
- 纪律：本报告凡标 **【实测】** 者为我本人本轮亲自跑出；标 **【读到】** 者为我阅读代码/日志/文档所得，未自行构造实验。

## 0. 结论（先行）

**裁定：有条件通过（conditional pass）。**

- **阻塞项：0 条**（未发现任何应阻断交付的缺陷；六项修复全部为真修复且具备可判别性）。
- **唯一放行条件（真机，非沙箱可覆盖）**：`-8` 尚未装机（真机现装 `-7`），需按正常流程升级到 `-8` 后补齐真机冒烟：应用中心 停止/启动 幂等、NAS 重启自启保留、`/vol4/@appshare` 树的权限探针、向导 UI、arm/i386 负载。此项与上一轮的放行条件性质相同，属"沙箱不可达"而非"产品缺陷"。
- 判断项结论（详见 §9/§10）：
  - **项3（`ensure_data_dir` 新风险）**：在已验证路径上无回归；但该函数是**尽力而为**（chmod 失败静默返回 0），代码注释中"结构上不可能"的措辞**高于实际保证**；另有 `index.cgi` 内联重复实现与 `config.json.bak` 的残余权限窗口两条低危观察。
  - **项6（"重启 NAS → 自启"证据）**：真机自 Sep 27 12:52 起**未重启**（uptime 3 天 14 小时），用户所述"重启 NAS 自启已验证 OK"**在本机无法佐证**，应记为"未验证（未观测到重启）"。
  - **项7（`chmod 700` vs `go-rwx`）**：`go-rwx` 是**真正的语义修复**，不是症状搬家（`chmod 700` 会把只读注入测试"治好"，即重新授予属主写权限，使 7 个测试用例失效）。

---

## 1. 工作项 1 —— `-7` → `-8` 字节级差分【实测】

### 1.1 两个产物

| | `-7` | `-8` |
|---|---|---|
| md5 | `3608a54efe1b966d6e80e93195e815d1` | `6898fc7f073c0ab8699eee5299916aec` |
| sha256 | `6fb75699f1870e7340fb3dae0c8dfd33ad48a8a6c0289f928648cc65054fa651` | `9df9220747f4ee0f2c95fd2b153c8d380224f3213f74fbd04a69048a7a3896fa` |
| size | 16382785 B | 16384143 B（+1358 B） |
| mtime | 2026-09-30 19:05:47 | 2026-10-01 03:07:11 |

### 1.2 顶层差分（`diff -r` 解包树）

**仅**以下条目不同：

- `cmd/common`
- `cmd/install_callback`
- `cmd/upgrade_callback`
- `app.tgz`（其内部**仅** `ui/index.cgi` 不同）
- `manifest`

### 1.3 负载二进制 —— 四个架构逐字节未变【实测】

| 负载 | sha256（`-8`，**与 `-7` 相同**） |
|---|---|
| `bin/openp2p_aarch64` | `0fd0a94f21b4cbb82d9e0a3e405d05c375d10bdec8341dba66e129c019966ae6` |
| `bin/openp2p_armv7` | `faf48c4cadcb041358ba0e8ed9c90c66dddf7773ca21ce38052056ca98cddb8c` |
| `bin/openp2p_i386` | `6fb6112d244ed623c556db1b13ebb1ebc8173ed7b1def461ddaebd108a3a8127` |
| `bin/openp2p_x86_64` | `6fbd7772e8a82299ba77bf3505de2ebc6b8be8ff9083eb3197101bb5fbba4b44` |

`config/privilege`、`config/resource`、`ui/config`、`images/`、`wizard`、图标等**全部 SAME**。**无夹带**。

### 1.4 manifest 自洽【实测】

`version` `3.25.11-7` → `3.25.11-8`；`checksum` `ad690f7bc19526db8022c23fe2969fa8` → `34f3a0d3…`，与 `md5(app.tgz)` 一致（已核）。

### 1.5 变更文件全量哈希（`-7` → `-8`）

| 文件 | `-7` sha256 | `-8` sha256 |
|---|---|---|
| `cmd/common` | `e5d2f15facf5545ffcc1c150956dbc1976e01d1a9743fc33c592a7ff12c6bcbd` | `10c2bc210f4bbdc0f3ee035ffd9fe8ee7fe9bdc49f56892ed47abaad53cb39ba` |
| `cmd/install_callback` | `5fa229a4…` | `32e9c745df40f21052f6d506191c18eb2fb62469acf0026fce36e8b16a709bfb` |
| `cmd/upgrade_callback` | `f6a39b10…` | `ef1a22a6918ce3b017eff8c341c5d607b479944f5830eb23f9ebb6497814e793` |
| `app/ui/index.cgi` | `c1164ca2cf79e3a80937b1a55c5803be963777bdbd87154b70381ca9b26cb890` | `e42060283935a56be54eb8b11f8aa8c7d0b8230b4410af751a43e140679ff5c4` |

`cmd/main` 未变（`3d7e156538103e63843b6d086bf94169d2199eb65a76958573203dd4544a3c0c`，同 `-7`）。

### 1.6 源码树一致性【实测】

`-8` 包内 `cmd/`、`ui/`、`config/`、`wizard/` 与 `src/openp2p/...` **完全一致**（`diff -r` 无输出）；`find -newer 包内 cmd/common` 为空——**没有比 `-8` 更新的源文件**。变更源文件 mtime：`cmd/common` 03:05:05、`cmd/install_callback` 02:59:09、`cmd/upgrade_callback` 02:59:23、`app/ui/index.cgi` 03:05:52；`cmd/main` 18:51:09（未动）。时间线自洽。

### 1.7 变更内容映射（与声称的六项一一对应）

- `cmd/common`：新增 `ensure_data_dir()` 及注释块；4 处 `mkdir -p "$DATA_DIR"` 替换为 `ensure_data_dir`；**N5-2** 冷启动写 `config.json` 改为 `( umask 077; printf … )`；**N5-1** Token 告警不再回显值（只报长度）。
- `install_callback` / `upgrade_callback`：进度文件写入 `> file` 改为 `2>/dev/null >> file`（**N5-3**）；失败文案扩充（"程序文件已部署…请点『修复』重试"）。
- `ui/index.cgi`：保存路径（:160-161）与 `raw_save`（:293-294）新增内联 `mkdir -p "$DATA_DIR"` + `chmod go-rwx "$DATA_DIR"`；保存失败文案按 `was_running` 派生（**N5-4**："仍在运行"/"当前为停止状态"）。

**项1 结论：差分干净，与声称完全一致，无夹带、无未申报改动。**

---

## 2. 工作项 2 —— N5-1 ~ N5-6 独立复现（自写最小复现 + "回退修复"变异体）【实测】

判别方法统一为：**新源码（`-8`）/ 旧件（`-7` 实物）/ 机械变异体（回退该修复点，`bash -n` 通过，diff 恰为该一处）** 三组对照，确保每个 PASS 都能回答"旧版会不会红"。

### N5-1 坏 Token 泄入 0644 日志

| 组 | 结果 |
|---|---|
| NEW（`-8` 源码） | **NOLEAK**（日志+进度文件 0 命中） |
| OLD（`-7` 实物） | **LEAK**（各 1 命中） |
| MUTANT（回退该 1 行，`bash -n OK`，diff 恰 1 行） | **LEAK** |

→ **真修复，且本例具备可判别性。**

补充对抗性观察（低危）：`warn_msg` 仍回显 node/带宽/地址等字段（设计上的排障取舍）。若用户把 Token **误填进 node 字段**，仍会入日志；概率极低，不作为缺陷，仅记录。

### N5-2 config.json 冷启动权限

| 场景 | NEW | OLD | MUTANT |
|---|---|---|---|
| A：`/tmp` | conf **600** | 666 | 666 |
| B：`/vol4/@appshare` 树 | dir 755→**700**、conf **600** | dir 755、conf 600 | — |
| C：仅 `chmod 600` 桩 | `/vol4` conf **700**；`/tmp` conf 600 | `/vol4` conf **755（泄漏）**；`/tmp` 666 | — |

**前提验证【实测】**：`/vol4/@appshare/<app>` 会**吞掉 umask**（`umask077→705`、`umask000→705`、`mkdir→705`；父 755→子 755，父 700→子 700；`/tmp` 对照 `umask077→600`）。这正是 `ensure_data_dir` 存在的理由，前提成立。

→ **真修复。**

### N5-3 进度文件截断

| 组 | 框架内容 | stderr 泄漏 |
|---|---|---|
| NEW | 保留（=1） | 三场景全 0 B |
| OLD | **被截断** | **122 B 泄漏** |
| MUTANT（`>>`→`>`，`bash -n OK`） | **被截断** | **泄漏** |

→ **真修复。**

### N5-4 保存失败文案按 `was_running` 派生

| 组 | A（未运行） | B（运行中） |
|---|---|---|
| NEW | PASS（"停止状态"） | PASS（"仍在运行"） |
| OLD | FAIL | FAIL |
| MUTANT（分支对调，`bash -n OK`） | FAIL（说谎） | FAIL（说谎） |

→ **真修复。**

### N5-5 / N5-6 repro.sh 版本标签

`grep -c '3.25.11-6' repro.sh` = **0**；`ls -t` 返回 `-8` 为最新。→ **已修复；`-8` 确为最新产物。**

**项2 结论：六项全部为真修复，且每个 PASS 均有"旧版/变异体会红"的对照证据。**

---

## 3. 工作项 3 —— 新增 `ensure_data_dir()` 的风险分析【实测】

实验脚本 `edd.sh`（`/tmp/qa6/work/edd.sh`）：

| 编号 | 实验 | 结果 |
|---|---|---|
| E1 | 符号链接 | `chmod go-rwx` 作用于**真实目标**（700），链接本身仍 777。真机 `DATA_DIR` 软链到 `/vol4/@appshare/openp2p`（700）→ 实际受保护。 |
| E2 | 幂等（连调 3 次） | 每次均 700。 |
| E3 | 悬空软链 | 目标**未**创建，rc=0。 |
| E4 | chmod 失败（桩） | 主流程不受影响，`ensure_token_in_conf` rc=0，conf=600。 |
| E5 | 权限矩阵 | 777/755/750/711/705/701 → **700**；700→700；**500→500**；550→500；400→400；000→0。→ **只会收紧，绝不放开**；`0500`（只读注入）被保留。 |
| E6 | 父目录不可写 | rc=0，DATA_DIR 未创建。 |
| E7 | 作用域 | 仅收紧 DATA_DIR，`PKGVAR`/`LOGDIR` 仍 755。 |

**发现（低危，非阻塞）：**

1. **注释措辞高于保证**：`ensure_data_dir` 在 chmod 失败时**静默返回 0**，所以"窗口在结构上不可能"是**尽力而为**，不是不变量。若数据目录非应用属主所有或挂只读，保护会静默失效。建议把注释改为"常规情况下消除该窗口（chmod 失败时降级为尽力而为）"。
2. **`cmd/main:78` 仍为裸 `mkdir -p "$DATA_DIR" "$PKGVAR" "$(dirname "$LOG_FILE")" 2>/dev/null`**，未走 `ensure_data_dir`；`install_callback:15` / `upgrade_callback:15` 亦然。**但不构成真实缺口**：同一起动路径随后经 `ensure_token_in_conf` → `ensure_data_dir` 收紧，且收紧发生在任何敏感文件写入之前。属防御纵深建议。
3. **`index.cgi` 是内联重复**（:160-161、:293-294 直接 `mkdir + chmod go-rwx`），**不调用** `ensure_data_dir`（`grep -n ensure_data_dir` 仅命中 `cmd/common` 定义与 4 处调用点）。行为上等价，但存在"两处实现漂移"风险；建议至少加注释指向同一纪律。
4. **`config.json.bak`（含 Token）不在"先建后 chmod"窗口的修复射程内**：`raw_save` 中 `cp -f "$CONF" "${CONF}.bak"` 位于目录收紧**之前**，其模式由 `cp` + umask 决定。真实暴露需同时满足"目录 0755 **且** chmod/go-rwx 失败 **且** umask 被吞"。真机数据目录为 700，故不成立。记为**观察项**。附带【实测】：在 `/vol4/@appshare` 树（755 目录）上 `cp -f` 一份 600 文件会得到 **755**（`/tmp` 上保持 600）；`sed -i` 同理→755。这印证了"该文件系统上文件模式确实会被放宽"这一前提，也正是 `ensure_token_in_conf` 尾部 `chmod 600` 存在的理由。

**T22 枚举补漏【实测】**：`grep` "目标文件出现在 `2>/dev/null` 之前" 命中 = **0**；所有 `chmod` 与 `ensure_data_dir` 调用点已逐一枚举。

---

## 4. 工作项 4 —— 全套自跑 + index 自检 + 造假实验【实测】

### 4.1 A–H 全套（输出至 `/tmp`，冻结日志未动）

A 26/0、B 30/0、C1 18/0、C2 26/0、E 21/0、F 16/0、G 29/0、H 87/0 = **253 PASS / 0 FAIL** ✓ 与 `evidence-index.md` §2/§5 声称一致。
D **3 PASS / 1 FAIL** ✓（i386 环境受限，预期内）。
`repro.sh` **17 OK / 0 BAD** ✓。

### 4.2 哈希漂移

C1 与 F **逐字节相同**；A/B/C2/E/G/H/repro 及 D 的执行段因 PID/时间戳漂移。D 漂移文本不同（"mallocgc…" vs "morestack on gN"），**结论不变**。去编号归一后逐行 diff：除 D 崩溃文案 4 行外**全 0 行**。冻结文件经 `sha256sum -c` 基线校验**全部 OK（未被我污染）**。

### 4.3 index 自检

`python3 make-index.py --check` = **OK（206 行，rc=0）**，在造假实验前后各一次，均为 OK。

### 4.4 "让它说谎"实验（两次，均先 DIFF+rc=1，后恢复至 OK）

1. 向 `exec-H.sh` 追加一行注释 → index 报 sha256 `f1b5ddaf…`→`25df7e83…` 漂移（DIFF）。
2. 仅 `touch exec-E.log`（只改 mtime）→ index 报 mtime 漂移，sha256 列不变（DIFF）。

→ **index 同时绑定 sha256 与 mtime，具备真实判别力**；伪造后已恢复并复核 OK。

---

## 5. 工作项 5 —— 真机证据（`my-fnos`，2026-10-01 03:26 +0800）【实测】

- `uptime` = 3 天 14:34；`last reboot` → **Sun Sep 27 12:52 仍在运行** → **未重启**。
- `ps`：**单实例** PID **405435**（root，`-node fnos -sharebandwidth 10 -serverhost api.openp2p.cn:27183 -loglevel 1 -installpath …`，**无 `-token`**），etime 31:17。上一轮两个 root 残留进程 **2795664/2800553 已消失**。
- 端口 `*:1025` **单条 LISTEN**。
- `/var/log/apps/openp2p.log` = 0 字节（mtime 03:00）→ 结论须取自轮转归档（证据卫生提示，非缺陷）。
- `manifest` version=`3.25.11-7`、checksum=`ad690f7bc19526db8022c23fe2969fa8` → **`-8` 尚未装机**。已装 `cmd/*`（common/main/install_callback/upgrade_callback） sha256 **与 `-7` 包逐字节一致**。
- 数据目录 `/var/apps/openp2p/shares/openp2p → /vol4/@appshare/openp2p`（Permission denied，**预期**）；`/proc/405435/exe` readlink EACCES（**预期**）。
- 归档日志佐证 `-7` 的清理逻辑：`openp2p.log-20261001.gz` 含 `[02:51:16] 清理残留进程 pid=2795664`、`[02:51:17] 清理残留进程 pid=2800553`、`[02:52:01] ✅ 启动成功 pid=396041`、`login ok. user=demo-user, node=fnos-demo01`、`sdwan init ok`；`02:55:30 停止中 pid=396041`；`02:55:39` 重启；`02:55:49 login ok … node=fnos-demo02`。`openp2p.log-20260930.gz` 记录了此前的病态状态（反复 `bind 1025 address already in use`、多实例）。

**项5 结论：真机当前状态健康**——单实例、单端口、已登录，且上一轮的两个 root 残留已被 `-7` 的停止逻辑回收。

---

## 6. 工作项 6 —— "重启 NAS → 自启"的时间证据【实测】

- `uptime` 3 天 14:34、`last reboot` = Sep 27 12:52 → **自 Sep 27 起未重启**。
- 用户所述"重启 NAS 后自启，已验证 OK"**在本机无任何可佐证的时间证据**；最可能是把"**重启应用**"与"**重启 NAS**"混为一谈（本轮归档日志恰好显示 02:55 有一次**应用级**停止/重启并成功重登）。
- **判定：该项应记为"未验证（未观测到重启）"，继续留在待验证清单，不因用户口述而结案。** 若要结案，需一次真实的整机重启 + 重启后 `ps`（单实例）+ `1025` 监听 + `login ok` 时间戳。

---

## 7. 工作项 7 —— `chmod 700` vs `chmod go-rwx`【实测】（`e7.sh`）

以"只读注入"（目录 `0500`）为判据：

| 实现 | dir 500 → | 写探针 |
|---|---|---|
| 现行（`go-rwx`） | **500** | **无法写**（只读注入被保留） |
| 变异（`chmod 700`） | **700** | **可写**（只读注入被破坏） |
| 裸实现（旧，无 ensure） | 500 | 无法写 |

**判定：`go-rwx` 是真正的语义修复，不是症状搬家。** `chmod 700` 之所以错，在于它会把属主写权限**重新授予**，从而"治好"只读注入测试、使 7 个用例失去判别力。`go-rwx` 只收紧、绝不放开，语义正确。

---

## 8. 新发现 / 观察清单（均为低危，非阻塞）

| # | 观察 | 影响 | 建议 |
|---|---|---|---|
| O1 | `ensure_data_dir` chmod 失败静默返回 0，注释措辞高于实际保证 | 文档准确性 | 修改注释为"尽力而为" |
| O2 | `cmd/main:78`、`install_callback:15`、`upgrade_callback:15` 仍裸 `mkdir -p` | 防御纵深（**无真实缺口**） | 可选：改调 `ensure_data_dir` |
| O3 | `index.cgi` 内联 `mkdir+chmod go-rwx`（:160-161、:293-294），未复用函数 | 两处实现漂移风险 | 加注释指向同一纪律 |
| O4 | `config.json.bak`（含 Token）在目录收紧前经 `cp -f` 创建；该文件系统上 `cp`/`sed -i` 会把 600 放宽为 755 | 需"目录 0755 + chmod 失败 + umask 被吞"同时成立；真机目录 700，不成立 | 观察；可在 `cp` 后补 `chmod 600` |
| O5 | `warn_msg` 仍回显 node 等字段；若 Token 误填 node 字段仍会入日志 | 概率极低 | 观察 |
| O6 | `repro.sh` banner 绑定产物、断言绑定 `$SRC`，二者当前相等 | 一旦源码/产物分叉会误归因 | banner 同时打印 `$SRC/cmd/common` 与 `index.cgi` 的 sha256 |
| O7 | 真机活动日志 0 字节，结论只能取自轮转归档 | 证据卫生 | 复核记录中注明归档来源 |

---

## 9. 阻塞项

**无。** 未发现应阻断交付的缺陷。以下为"非阻塞项"里判别力最强的原始证据（供对抗性反驳）：

```
# N5-1 对照组：机械变异体必须泄漏（否则修复不可判别）
$ bash -n /tmp/qa6/work/mut_n51_common && echo "语法合法"
$ diff <(cat /tmp/qa6/u8/cmd/common) /tmp/qa6/work/mut_n51_common | wc -l   # 恰为 1 行差异
$ bash /tmp/qa6/work/n51.sh /tmp/qa6/work/mut_n51_common
  → LEAK（日志 1 命中 + 进度文件 1 命中）
$ bash /tmp/qa6/work/n51.sh /tmp/qa6/work/legacy/common.from-7
  → LEAK（同）-7 实物确实泄
$ bash /tmp/qa6/work/n51.sh /tmp/qa6/u8/cmd/common
  → NOLEAK（0 命中）

# N5-7 判据：go-rwx vs chmod 700（只读注入 0500）
$ bash /tmp/qa6/work/e7.sh
  go-rwx : dir 500→500  write=不能
  chmod700: dir 500→700  write=能   ← 只读注入被破坏
```

---

## 10. 我**无法**验证的项（沙箱不可达 / 需真机）

1. `-8` 装机后的真机行为（现机仍为 `-7`）：应用中心 停止/启动 幂等、单实例保持。
2. NAS **重启**自启（详见 §6，未观测到重启）。
3. 真机 `/vol4/@appshare` 树上的 umask/权限探针实测（沙箱内已在 `/tmp` 与 `/vol4/@appshare/octop-native` 上完成等价验证）。
4. 向导（wizard）UI 交互路径。
5. arm/aarch64/armv7/i386 负载的真实执行（D 的 1 FAIL 即 i386 环境受限）。
6. 应用中心"安装/升级回调"在真实 FNOS 上的端到端表现（仅审了脚本逻辑）。

---

## 11. 我的哈希清单（本轮全部实测）

**产物**：见 §1.1。**变更文件**：见 §1.5。**负载二进制**：见 §1.3。

**我重跑的日志（`/tmp/qa6/rerun/`）**：

```
13d766ff92a9f2bb45f983ea412dc2203634af0c93b2d70fd69c276848d41499  exec-A.rerun.log
e51fbad94d2440b42590d96884f9a57cec8c7c1be4f9b45a771883104044c83d  exec-B.rerun.log
73689491dc74edc525722b19bb3c0f45ca953a42a6447ac1858af1c0526b6f4a  exec-C1.rerun.log
48f042383dd87fd9fe038b007443a4a200366f6b0635ec7b4652b3e94017cd57  exec-C2.rerun.log
f3df5987095dda5ef10f9ce6982d42040ab3f0c3f7e1be24e61f82ff7ec2c59b  exec-D.rerun.log
ffddc843c451cbc2de35103ef996982e0787a642a1bbb1c5c15f6c67e15a92b3  exec-E.rerun.log
e54ca762d2f73369920eccb73b5d2ef406dd22b4bbe35ef5c4d7ff0c36dcb21e  exec-F.rerun.log
c0badad20ce8cfec707c5eb0b6f0e04810e9c7e8d79aa327488e37dd432a72c8  exec-G.rerun.log
bea055b6b2ad24daa002c334bb9bc503b268319627cb624815a69ee6e089bc6d  exec-H.rerun.log
f0eb3740aa07f6ca8d6314ee26c58070fe9e4b12815034160978f03acdfd9ac7  repro.rerun.log
```

**我的 harness / 变异体（`/tmp/qa6/work/`）**：

```
0ffdb48b641cb7cb97f790291f91726ed5822596d15a3cf1cfe76dd87b16ff64  env.sh
b1e19dec044e06164ba8276295e84b833d80a5f66620028bcde5a4e99285dfe4  n51.sh
560f570c6c5f61f88eebff3e7d80e3a12b7f6cb70c29074939dd86e60a94a1cf  n52.sh
2821c0f3f1aa97228e1584c9bec5434192bee49aa146752ae4877f9071ac77e0  n52b.sh
2e4594ab473b754350d0ea4bdc1e264d374410998894aefaf535ca365664e208  n52c.sh
330bb52d3def5c923c85843cf51d7f7d4a29f175cc06bcb431d9d5b4cfcc753c  n53.sh
dc15e741748877075f78f9f7cfafbf4135631c57e3728860a4088d4456dc66ef  n54.sh
d96c77598c4582500a986edeb5285a2735c0dccbdc998a0d76075d6fb2b64b2f  e7.sh
01341d2b2b067f9e92f415f8a4808c07c8325fd171c5246e8bb9c0b6bac74d9a  edd.sh
c4f03d03a6a934c2295a194b1772705ebfa8f009571692647a6b72e231ffe999  mut_n51_common
11793b12d2bc6eae55642fbfe28e226eb9ecd7ef3603ecc168623e97602c1aee  mut_n52_common
7aa4bf331282721d782dd17e2b2a0007125ac989bf4b2423dacce259fccced40  mut_n54_swap.cgi
e5d2f15facf5545ffcc1c150956dbc1976e01d1a9743fc33c592a7ff12c6bcbd  legacy/common.from-7
c1164ca2cf79e3a80937b1a55c5803be963777bdbd87154b70381ca9b26cb890  legacy/index.cgi.from-7
```

**冻结基线**（`-8` 前捕获）：`/tmp/qa6/baseline/qa-files.sha256`、`exec-H.sh.bak`、`exec-E.log.bak`；本轮结束时 `sha256sum -c` 全部 OK，`make-index.py --check` OK。

---

## 12. 需真机补充的工作（结案条件）

1. 升级到 `-8`，复核 `manifest` checksum 与包内 `cmd/*`、`ui/index.cgi` 哈希。
2. 应用中心 停止/启动 幂等：多次停止/启动 → `ps` 恒为单实例、`1025` 单监听、无残留。
3. **NAS 整机重启** → 重启后自启：`ps` 单实例 + `1025` 监听 + `login ok` 时间戳（**当前证据不支持"已 OK"**）。
4. `/vol4/@appshare/openp2p` 目录与 `config.json` 模式实测（期望 700 / 600）。
5. 向导 UI 路径；arm/aarch64/i386 负载真机执行。
