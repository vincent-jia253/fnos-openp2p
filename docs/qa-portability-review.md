# 可移植性审查（陌生机器能不能装、能不能用） —— openp2p_3.25.11-8_all.fpk

- 角色：`qa`（只审不改，**报告型**）
- 日期：2026-10-07（+0800）
- 审查问题（本次唯一目标）：**这个 .fpk 交到别人手上，能不能正常装、正常用？**（不是回归测试，不重复前六轮的断言矩阵）
- 被审对象：`dist/openp2p_3.25.11-8_all.fpk`
  - md5 `6898fc7f073c0ab8699eee5299916aec`　sha256 `9df9220747f4ee0f2c95fd2b153c8d380224f3213f74fbd04a69048a7a3896fa`　size 16384143 B
  - 交付件与源码树**逐字节一致**：`diff -rq` 对 `cmd/`、`config/`、`wizard/`、`app.tgz 内的 ui/` 全部无输出（`manifest` 除外，build.sh 会重写 version/checksum）。**因此本报告对源码的审查结论直接适用于交付件。**
- 证据纪律：凡标 **【实测】** 者为本轮亲自跑出并附原始输出；标 **【读到】** 者来自阅读代码/文档/真机现状，未自行构造实验。
- 纪律声明：工作区（`projects/`、`dist/`、`teams/`）**只读**；所有实验、临时文件、破坏性操作都在 `/tmp/port/` 的私有 mount+pid namespace 内完成。事故披露见 §7。

---

## 0. 裁定（先行）

**裁定：有条件可以。**

- **阻塞项 3 条**（1 条在 fnOS 上**必然触发**，2 条**条件触发**）：

| # | 一句话 | 触发条件 | 类型 |
|---|---|---|---|
| **B1** | 卸载时选「删除配置」，**Token 根本没被删掉**，还留在 `/volN/@appshare/openp2p/` 里；日志却写着"已按用户选择删除配置与日志" | fnOS 上**必然**（该目录在 fnOS 上永远是符号链接） | 凭据残留 + 谎报 |
| **B2** | 当 `config.json` 里没有 `"Token"` 键时，`start` 会把**整个文件重写成最小配置** → 端口转发规则 `apps[]` 静默清零 | 用户手改过 `config.json`（README 明确鼓励）或该文件被重建过 | 静默数据丢失 |
| **B3** | 运行状态目录 `$TRIM_PKGVAR` 建不出来时（系统盘满/只读/inode 耗尽），`main start`、`main stop` 与**应用界面的请求**都会**无限挂起**：无输出、无日志、不退出，请求线程被占死 | 系统盘被写满等异常 | 界面卡死且零诊断 |

- **放行条件（必须先做）**：
  1. **B1 必修**——这是"用户以为凭据已清除、实际没有"的隐私问题，且 100% 复现；修完应在真机走一次「卸载 → 选删除 → 检查 `/volN/@appshare/openp2p` 是否为空」。
  2. B2、B3 建议同批修（改动都很小，见各条修复建议）。
  3. 另有一项与缺陷无关的**交付流程条件**：`-8` **从未在真机上装过**（真机现装 `-7`，`/var/apps/openp2p/manifest` 里写的就是 `3.25.11-7`，见 §6.3），前三轮的真机验收证据不能直接套到 `-8` 头上，公开前建议补一次真机升级冒烟。

- **可以放心的部分（都实测过）**：安装/启动/停止/状态主流程、无 Token 也能装能起、9 种不支持架构的快速失败、locale 无关、主机名各种脏值兜底、日志目录不可写时不泄漏裸错误、外部命令在真机全部存在、Token 不进 `ps`、不支持架构不装半截。**"能不能装、能不能用"的主干是通顺的。**

---

## 1. 方法与沙箱（可复现）

### 1.1 三步法

1. 静态审查 `cmd/*`、`app/ui/index.cgi`：硬编码路径、环境变量依赖、外部命令、权限/属主、locale、架构、主机名、端口与资源冲突。
2. **搭一台"陌生机器"真跑**：`unshare -rmpf --mount-proc` 私有 mount/pid namespace，把 `/var/apps`、`/var/log`、`/vol4` **bind 到 /tmp 下的私有目录**，主机名打桩成 `my-nas-01`，`DATA_DIR` 按**真机形态**建成符号链接；**脚本、wizard、config、UI、二进制全部取自 `-8` fpk 的交付内容**（`/tmp/port/pkg` = `-8` fpk 解包树，`manifest` 里 `version = 3.25.11-8`）。
3. 对照 `README.md` 逐条核对实现。

### 1.2 沙箱与原机的差别（结论适用范围）

| 维度 | 沙箱 | 真机 | 是否有影响 |
|---|---|---|---|
| `DATA_DIR` 形态 | 符号链接 → 私有目录 | 符号链接 → `/volN/@appshare/openp2p` | **无**，刻意做成一致（这正是 B1 能复现的原因） |
| `$TRIM_PKGVAR` | 私有目录 | `/usr/local/apps/@appdata/openp2p`（不可读，未实测） | 无（代码只用 `TRIM_PKGVAR` 兜底 `/var/apps/openp2p/var`） |
| 进程身份 | root（ns 内 uid 0） | root（`config/privilege` 声明 `run-as: root`，`manifest install_type = root`） | 无 |
| 网络 | 真网络（用假 Token，未登录成功） | 真网络 | 组网登录未验证（见 §6.4） |
| fnOS 应用中心/向导 UI | 不可达（直接执行 `cmd/*`） | 可达 | 未验证（见 §6.4） |

沙箱脚本：`/tmp/port/nsnb.sh`（harness，先 bind 再断言 `stat -c %d:%i` 一致才敢做删除）、`/tmp/port/env.sh`（清空全部 `TRIM_*`/`openp2p_*`，PATH 收窄）、各用例 `nb-*.sh`。

---

## 2. 阻塞项

### B1【阻塞 · 必发】卸载选「删除配置」不会删掉 Token（fnOS 上必然发生）

**现象（实测）**：选「删除配置」卸载后，`config.json`、`settings.conf`（两处都含 Token 明文）、`log/`、二进制全部**原封不动**留在真实数据目录里；日志却报"已按用户选择删除配置与日志"。

**为什么在陌生机器上必然成立（这是关键，不是作者机器的怪癖）**：

- 包内 `config/resource` 声明了 data-share：
  ```json
  {"data-share":{"shares":[{"name":"openp2p","permission":{"rw":["openp2p"]}},
                           {"name":"openp2p/data","permission":{"rw":["openp2p"]}}]}}
  ```
- fnOS 据此把 `$APPDIR/shares/<appname>` 建成**指向数据卷的符号链接**。真机现状（只读观测，抽查 20 个应用，**全部**是符号链接）：
  ```
  /var/apps/openp2p//shares/data     -> /volN/@appshare/openp2p/data
  /var/apps/openp2p//shares/openp2p  -> /volN/@appshare/openp2p
  /var/apps/EasyTier-Web//shares/EasyTier-Web -> /volN/@appshare/EasyTier-Web
  /var/apps/dpanel//shares/dpanel    -> /volN/@appshare/dpanel
  /var/apps/WxBackup//shares/WxBackup -> /vol1/@appshare/WxBackup
  …（其余同类）
  ```
- 代码里 `DATA_DIR="${APPDIR}/shares/${APPNAME}"`（`cmd/common:10`），而 `cmd/uninstall_callback:24` 是：
  ```sh
  delete)
      rm -rf "$DATA_DIR"      # ← 对一个符号链接做 rm -rf，只删链接本身
      rm -f  "$LOG_FILE"      # 日志是真实文件，这条是生效的
      log_msg "卸载：已按用户选择删除配置与日志（${DATA_DIR}）"
  ```
  `rm -rf <符号链接>` 只删链接、不进目标 —— 于是"删配置"退化成"删了个链接"。

**复现（自包含，3 分钟）**【实测】：`/tmp/port/repro-report.sh`，核心步骤：

```bash
PKG=/tmp/port/pkg                      # -8 fpk 解包树
R=/tmp/o2p-repro
mkdir -p "$R/root/target" "$R/root/var" "$R/realdata"
cp -a "$PKG/cmd" "$R/root/"; tar --no-same-owner -xzf "$PKG/app.tgz" -C "$R/root/target"
mkdir -p "$R/root/shares"; ln -s "$R/realdata" "$R/root/shares/openp2p"   # ← 真机形态
export OPENP2P_APPROOT="$R/root" TRIM_APPNAME=openp2p TRIM_APPDEST="$R/root/target" \
       TRIM_PKGVAR="$R/root/var" LOG_FILE="$R/apps.log"
CMD="$R/root/cmd"
openp2p_token=12345678 bash "$CMD/install_callback"
bash "$CMD/main" start; sleep 1; bash "$CMD/main" stop
openp2p_data_action=delete bash "$CMD/uninstall_callback"
ls -l "$R/realdata"        # 期望为空；实际：配置还在
grep -h '"Token"' "$R/realdata/config.json"; grep -h '^token=' "$R/realdata/settings.conf"
```

原始输出：

```
install_callback rc=0
--- 卸载前，真实数据目录 ---
-rw------- 1 root root      333 config.json
drwxr-xr-x 2 root root     4096 log
-rwx--x--x 1 root root 10371072 openp2p
-rw------- 1 root root      635 settings.conf
uninstall_callback rc=0
--- 卸载后，真实数据目录（应为空）---
-rw------- 1 root root      333 config.json
drwxr-xr-x 2 root root     4096 log
-rwx--x--x 1 root root 10371072 openp2p
-rw------- 1 root root      635 settings.conf
--- 卸载后，Token 还在不在 ---
    "Token": 12345678,
token=12345678
--- 日志原文 ---
[2026-10-07 21:36:03] [openp2p] 卸载：已按用户选择删除配置与日志（/tmp/o2p-repro/root/shares/openp2p）
```

同一现象在"带真机形态符号链接"的 namespace 生命周期用例（`/tmp/port/nb-evidence.log` E3）里独立复现，输出一致。

**连带后果（也实测到了）**：链接被删掉后，**下一次 `start` 会在链接位置建出一个真实目录**（`ensure_data_dir` 的 `mkdir -p`），应用从此把数据写在系统盘，而用户原来的配置变成 `/volN/@appshare/openp2p` 下的孤儿：

```
--- shares/openp2p 现在是什么 ---
drwxr-xr-x 2 root root 4096 /tmp/o2p-repro/root/shares/openp2p        ← 变成真实目录（不再是链接）
--- 真实数据目录还是孤儿 ---
config.json  log  openp2p  settings.conf
```

**影响**：① 用户以为 Token 已清除（机器要转手、送修、借人都常见），实际凭据明文留在数据卷上；② 日志给了错误的安全感；③ 数据卷上留下一份用户找不到、也删不掉的"幽灵配置"。

**为什么前六轮没抓到**：`testcases.md` 的 **TC-20** 就是这个用例，且 `exec-C1.log` 里是 `[PASS]`——因为 `exec-C1.sh` 的沙箱 `mkdir -p "$DATA"` 用的是**真实目录**，`rm -rf` 当然成功。作者自己的缺陷台账里已经把这条教训写得很清楚（`bugs.md` **T7**："旧 sandbox 的 DATA_DIR 是真实目录，而真机是符号链接。这类缺陷在旧环境里永远测不出来"），B11 就是因此漏出去的——**但同一课没有回头扫到 uninstall**。建议把"符号链接布局"纳入所有用例的默认前置，而不是只在块 G 特设。

**最小修复建议**：

```sh
delete)
    real="$(readlink -f "$DATA_DIR" 2>/dev/null || true)"
    [ -n "$real" ] || real="$DATA_DIR"
    case "$real" in
        "${APPDIR}"*|/vol[0-9]*/@appshare/*) ;;      # 只允许删这两个已知位置，避免链接被人改指向
        *) log_msg "❌ 数据目录指向意外位置，拒绝删除：$real"; exit 1 ;;
    esac
    rm -rf "$real" 2>/dev/null                        # ① 先删真实目录（含 Token）
    rm -rf "$DATA_DIR" 2>/dev/null                    # ② 再删链接本身（真机形态）
    rm -f  "$LOG_FILE" 2>/dev/null
    if [ -e "$real" ] || [ -e "$DATA_DIR" ]; then     # ③ 删完自检，别再说谎
        log_msg "❌ 删除未完全生效，请手动检查 ${real}（权限或占用）"
    else
        log_msg "卸载：已按用户选择删除配置与日志（${real}）"
    fi
```

---

### B2【阻塞 · 条件触发】`config.json` 没有 `"Token"` 键时，启动会整文件覆盖 → `apps[]`（端口转发规则）静默丢失

**现象（实测）**：`config.json` 里有端口转发规则、但没有 `"Token"` 键时执行 `main start`，**整个文件被重写成最小默认配置**，`apps` 变成 `null`。

**代码**（`cmd/common:270-279`）：

```sh
if [ -f "$CONF" ] && grep -q '"Token"' "$CONF" 2>/dev/null; then
    sed -i "s/\"Token\"[[:space:]]*:[[:space:]]*\"\{0,1\}[0-9]*\"\{0,1\}/\"Token\": ${tok}/" "$CONF"   # 只换 Token，保留其余 → 安全
else
    ( umask 077; printf '{"network":{"Token":%s}}\n' "$tok" > "$CONF" )                                  # 整文件覆盖 → 危险
fi
```

"有 Token 键 → 只 sed 换值"（保住 `apps`）与"无 Token 键 → 整文件覆盖"（抹掉 `apps`）是同一条分支的两个走向。

**复现**【实测】（同一脚本 B2 段，符号链接形态）：

```bash
printf '{"network":{"Node":"nas"},"apps":[{"AppName":"rdp","Protocol":"tcp","SrcPort":3389,"DstPort":3389,"PeerNode":"other"}]}\n' > "$R/realdata/config.json"
bash "$CMD/main" start; sleep 1; cat "$R/realdata/config.json"
```

原始输出：

```
--- 启动前 ---
{"network":{"Node":"nas"},"apps":[{"AppName":"rdp","Protocol":"tcp","SrcPort":3389,"DstPort":3389,"PeerNode":"other"}]}
main start rc=0
--- 启动后（apps 去哪了）---
{
  "network": { "Token": 12345678, "Node": "my-nas-01", ..., "ServerPort": 27183, "PublicIPPort": 1859 },
  "apps": null,                       ←←← 端口转发规则没了
  "LogLevel": 1, ... , "Forcev6": false
}
```

**触发条件有多现实**：README §六明确邀请用户手改 `config.json`（"也可以直接编辑 `config.json` 里的 `apps` 数组后重启应用"），并承诺"本封装的启动参数**不会覆盖**你在 `config.json` 里手写的 `apps`"。用户从一个干净/别处拷来的 `config.json` 起步（没有 `Token` 键，Token 由本应用从 `settings.conf` 补写）就会踩到。它只在 `"Token"` 键缺席时发生——但一旦发生，**用户不会收到任何提示**，规则直接消失。

**最小修复建议**（任选其一，都很小）：
1. 覆盖前先合并：把旧文件读出来，只补 `network.Token`，其余字段原样保留（无 python3 时可用"删掉旧 `network` 段再拼"的笨办法，或直接用下面第 2 条）；
2. 覆盖前先备份 + 日志告警：`cp "$CONF" "$CONF.bak"`（`umask 077`）并 `log_msg "⚠️ 未发现 Token 键，已重建 config.json（原文件备份为 config.json.bak）"`；
3. 顺带修掉同函数的第二个坑（见 O4）：写完后用 python3（有则用）校验 JSON 合法性，不合法就回滚。

---

### B3【阻塞 · 条件触发】运行状态目录不可写时，`start`/`stop`/界面请求**无限挂起**（无输出、无日志、不退出）

**现象（实测）**：把 `$TRIM_PKGVAR` 指到一个**建不出目录**的位置（`/proc/o2p-cannot-create`，模拟系统盘满/只读/inode 耗尽/`@appdata` 异常），然后 `main start`：

```
main start rc=124  耗时=15s  stdout字节=0  stderr字节=0      ← 15s 是被 timeout 杀的，即"永不返回"
main stop  rc=124  耗时=30s
界面 save 走 main start 时：cgi rc=124  耗时=30s  stderr=0
日志只有一行，且内容是错的：
[2026-10-07 21:36:16] [openp2p] ⚠️ 清理陈旧启动锁（已存在 1791380176 秒）
```

（另一次在"16MB tmpfs 写满"下测得同样结果：`rc=124`、0 字节输出；`/tmp/port/nb-hang2.log`。）

**代码**（`cmd/common:290-308`）：

```sh
acquire_lock() {
    local i=0
    while ! mkdir "$LOCK_DIR" 2>/dev/null; do        # $LOCK_DIR = $PKGVAR/.o2p.lock
        i=$((i+1))
        if [ "$i" -ge 50 ]; then
            local age
            age=$(( $(date +%s) - $(stat -c %Y "$LOCK_DIR" 2>/dev/null || echo 0) ))   # stat 失败 → age = 现在-0 = 17 亿秒
            if [ "$age" -gt 60 ]; then
                log_msg "⚠️ 清理陈旧启动锁（已存在 ${age} 秒）"
                rm -rf "$LOCK_DIR" 2>/dev/null                                          # 删不掉（根本建不出来）
            fi
            i=0                                                                          # ←←← 计数器被重置
        fi
        sleep 0.2
    done
```

`mkdir` 因**非"陈旧锁"**原因失败（磁盘满/只读/不可写）时：`stat` 失败 → 把 `age` 当成 17 亿秒 → 判定"陈旧锁" → 清不掉 → `i` 归零 → **0.2 秒一轮无限循环，无任何上限**。`main start`、`main stop` 都先取这把锁，所以两个命令一起挂；应用界面按钮走的是同一个 `main`，于是 **HTTP 请求也永不返回**（占住 worker）。

**影响**：用户看到的是"点启动没反应"，日志里没有任何可用线索（只有一行莫名其妙的"清理陈旧启动锁"）。这类"磁盘满 → 整个应用界面卡死"的故障对陌生用户极不友好。

**最小修复建议**：

```sh
acquire_lock() {
    local i=0 age
    while ! mkdir "$LOCK_DIR" 2>/dev/null; do
        i=$((i+1))
        if [ "$i" -ge 50 ]; then
            i=0
            if [ -d "$LOCK_DIR" ] && age=$(stat -c %Y "$LOCK_DIR" 2>/dev/null); then
                if [ $(( $(date +%s) - age )) -gt 60 ]; then
                    log_msg "⚠️ 清理陈旧启动锁（已存在 $(( $(date +%s) - age )) 秒）"
                    rm -rf "$LOCK_DIR" 2>/dev/null
                fi
            else
                # 不是"锁存在但陈旧"，而是"锁根本建不出来" → 立刻报错退出，别死等
                log_msg "❌ 无法建立启动锁：${LOCK_DIR}（状态目录不可写或磁盘已满）"
                return 1
            fi
        fi
        sleep 0.2
    done
}
```
（判据的关键：**`stat` 失败 ≠ 锁陈旧**。另外给整个循环加一个总时限兜底，例如 30 秒后 `return 1`。）

---

## 3. 观察项（不阻塞，但都是陌生用户/陌生开发者会碰到的）

| # | 观察 | 证据 | 建议 |
|---|---|---|---|
| **O1** | `main` **没有 `restart` 子命令**（只有 `start|stop|status`），执行 `main restart` 得到 `Usage: ... {start\|stop\|status}`、`rc=1` | 【实测】 | 应用界面自己用 stop+start 绕过；但运维脚本/用户手册若写 `restart` 会踩空。README §六说"保存时自动重启"，实现是 stop+start，文档与实现能对上；只是 `main` 少一个子命令，建议补 `restart`（两行） |
| **O2** | README 说"Token 只写在 `config.json` 里（权限 600）"，**实际 `settings.conf` 里也有一份 Token 明文**（`token=…`，同样 600，同为 root） | 【实测】`grep` 命中文件列表：`config.json`、`settings.conf`；`ps` 命中 0 处 | 文档要改：Token 在**两个**文件里。这条会影响用户对"删哪个文件算删干净"的判断（与 B1 叠加） |
| **O3** | 仓库自带自测脚本**无法按 README 直接运行**：`test/simulate-fnos.sh:6` 是 `PROJ="/path/to/fnos-openp2p"` 占位路径，`:7` 指向 `dist/openp2p_3.25.11-1_all.fpk`——该文件在 `dist/` 里根本不存在（现为 `-2`…`-8`） | 【读到】+【实测】`dist/` 无 `-1` | README §七"运行时自测：`bash test/simulate-fnos.sh`"这句对陌生开发者不成立。改成自动探测（`PROJ="$(cd "$(dirname "$0")/.." && pwd)"`，FPK 用 `ls dist/*.fpk \| tail -1`） |
| **O4** | `ensure_token_in_conf` 的 sed 在 `Token` 值为**非数字字符串**时会把 JSON 改坏：把 `"Token":"abc"` 改成 `"Token": 98765432109876abc"` → 非法 JSON（`JSONDecodeError`） | 【实测】`E6`：`{"network":{"Token": 98765432109876abc"},"apps":[...]}` | 与 B2 同一函数、同一处修复：写完做一次 JSON 合法性校验；顺手把 sed 改成先删后插的严格匹配 |
| **O5** | 启动器**不检查端口占用**；把 1025 占住后 `start` 仍 `rc=0`、`status` 仍报运行中（openp2p 自身降级运行，日志无报错） | 【实测】`nb-port.log`：`start rc=0`、`status rc=0`、应用日志正常启动 | 不算缺陷（openp2p 设计上可走中继），但用户可能不知道"直连失效"。可在界面/文档加一句说明 |
| **O6** | 安装阶段**不生成 `config.json`**，第一次 `start` 才生成。README §三路径表把 `config.json` 列为"应用设置"，用户装完就去"文件管理 → 应用文件"找会找不到 | 【实测】`install_callback` 只写 `settings.conf` | 文档加一句"首次启动后生成" |
| **O7** | fpk 内 tar 记录的属主是**作者本机的 uid/gid（868/901）**，且 `cmd/*` 是 `711`、`ui/index.cgi` 是 `700` | 【实测】`tar tvzf --numeric-owner` | **实测不构成问题**：真机安装后是 `root:root` + ACL（`user:openp2p:rwx`），说明 fnOS 安装器会归一化属主与权限。记录在案，供镜像/手动解包用户参考 |
| **O8** | 交付件 `-8` 与真机已验收的 `-7` 有 3 个文件不同（`cmd/common`、`cmd/install_callback`、`cmd/upgrade_callback`，逐字节比对），而真机装的仍是 `-7` | 【实测】md5 比对 | 见 §0 放行条件 3；公开前补一次真机升级冒烟 |
| **O9** | ENOSPC 下 `fix_binary_arch` 复制失败会留下 `openp2p.new.<pid>` 残file | 【实测】早期 ENOSPC 用例 | 低危；可在失败分支加 `rm -f "$cand"`（`mv` 失败分支已有，`cp` 失败分支没有） |
| **O10** | 节点名缺省派生自主机名，同账号下两台默认主机名的 NAS 会撞名 | 【读到】`safe_node` + 主机名兜底 | 文档提一句"多台机器请手动区分节点名" |
| **O11** | 外部命令依赖在真机**全部存在**：bash/sh hostname uname pgrep pkill readlink stat date awk sed tr cut tail head wc nohup sleep mkdir chmod cp mv rm ps python3 timeout 等（`python3` 还是**可选**依赖，缺失时 `index.cgi` 退化为括号配平、`common` 同样有兜底） | 【实测】`command -v` 全表 | 无需动作 |

---

## 4. 「只在作者机器上成立」的假设清单

| # | 被检查的假设 | 判定 | 依据 |
|---|---|---|---|
| 1 | `DATA_DIR` 是真实目录 | **不成立**（真机是符号链接） | 【实测】真机 20/20 抽样的 `shares/*` 都是符号链接；`config/resource` 声明 data-share → **B1** |
| 2 | `DATA_DIR` 可写且已存在 | 成立（正常安装），异常时 fail-fast | 【实测】只读数据目录 → `install_callback rc=1`，报错清楚 |
| 3 | `$TRIM_PKGVAR` 可写 | 正常成立；异常时**挂死** | 【实测】→ **B3** |
| 4 | 进程以 root 运行 | **成立且 fnOS 保证** | 【读到】`config/privilege: run-as=root`；`manifest: install_type=root` |
| 5 | 依赖的外部命令存在 | **成立** | 【实测】真机 `command -v` 全表命中（O11） |
| 6 | `#!/bin/bash` 路径存在 | 成立 | 【实测】真机 `/usr/bin/bash`，`/bin` 亦可用 |
| 7 | `python3` 存在 | 成立但**非必需** | 【实测】CGI/`common` 均有 `command -v` 兜底 |
| 8 | 行为不受 locale 影响 | **成立** | 【实测】`LC_ALL=C / C.utf8 / en_US.utf8 / zh_CN.UTF-8` 四种下 install/start/status 的 rc 与解析完全一致 |
| 9 | 主机名可作为节点名 | **成立（兜底很稳）** | 【实测】空→`fnos-nas`；`MyNAS`→`mynas`；`我的NAS`→`nas`；65 字符→截 31；`my.nas_01`→`mynas01`；`my nas/01`→`mynas01` |
| 10 | 架构识别正确 | **成立** | 【实测】riscv64/loongarch64/mips64/mips64el/ppc64le/s390x/sparc64/x86/armv5tel 共 9 种全部 `rc=1` + 「❌ 不支持的系统架构：X」，且写进安装进度文件；`amd64`→x86_64、`i686`→i386 正常 |
| 11 | 端口 1025 可用 | **不成立（会被人/被自己占）**，但启动器不因此失败 | 【实测】→ O5（应用自身降级，不阻断） |
| 12 | Token 是纯数字 | 界面层成立（wizard 规则 `^[0-9]*$`、`safe_num` 拒绝非数字并按"不启动"处理）；`config.json` 手工写错时不成立 | 【实测】→ O4 |
| 13 | 路径固定为 `/var/apps/openp2p`、`/var/log/apps` | 成立 | 【读到】`common` 全部用 `TRIM_*` + 默认值；`TRIM_APPNAME` 未设时兜底 `openp2p`；`index.cgi` 硬编码的 3 个路径与 fnOS 约定一致 |
| 14 | `upgrade` 保留用户数据 | 成立 | 【实测】升级流程后 `settings.conf` / `config.json` md5 不变；重装后设置继续生效 |
| 15 | 卸载时 fnOS 会把向导的 `openp2p_data_action` 传到回调 | **不确定**（沙箱按 fnOS 约定模拟） | 【读到】wizard 字段名=环境变量名是 fnOS 约定；沙箱里显式传参复现了 B1。**若真机不传，则 `action` 缺省为 `keep`**——那"删除配置"会静默变成"保留配置"，问题性质相同（对用户都是"我选了删，它没删"） |
| 16 | 磁盘总有空间 | **不成立** | 【实测】ENOSPC 时 install/start 均 `rc=1` 且 0 字节 stderr 泄漏（这条做得好）；但 → **B3** |
| 17 | `/var/log/apps` 存在 | **不成立时也能自愈** | 【实测】目录被删后 install 自动重建（`mkdir -p`），`rc=0`；`TRIM_TEMP_LOGFILE` 不可写时也是 0 泄漏 |
| 18 | `date -d @<epoch>` 可用 | 不成立时优雅降级 | 【实测】uptime 显示 `—`，不报错 |
| 19 | `ps`/`pidof` 可用 | 代码**刻意不用**（用 `/proc`） | 【读到】`ps`/`pidof` 只出现在注释里 |

---

## 5. 文档 vs 实现 不一致清单（README.md，sha256 `b4b6be8e…`）

| README 位置 | 文中说法 | 实际实现 | 判定 |
|---|---|---|---|
| §六 第 1 个 Q | 「装完显示『未配置 Token，已跳过启动』？正常。」 | `-8` 已按 B8 修复为**照常启动**，日志文案是「⚠️ 尚未配置 Token：应用将启动但不会登录组网，请在应用界面填写 Token 后保存。」 | **不一致（文档过期）**，会误导用户以为"不启动是预期" |
| §六 Q（Token 泄露） | 「Token **只**写在 `config.json` 里（权限 600）」 | `settings.conf` 里也有一份明文 `token=`（600） | **不一致** → O2 |
| §六 Q（端口转发规则） | 「本封装的启动参数**不会覆盖**你在 `config.json` 里手写的 `apps`」 | 仅在 `config.json` 已含 `"Token"` 键时成立；否则整文件被重写、`apps` 丢 | **不一致** → B2 |
| §五 卸载 | 「删除配置：连 Token 一起清掉」 | 真机形态下什么都没删 | **不一致** → B1 |
| §七 | 「运行时自测：`bash test/simulate-fnos.sh`（模拟 fnOS 完整生命周期）」 | 脚本内是占位 `PROJ` + 已不存在的 `-1` 包名 | **不一致** → O3 |
| §一 安装 | 三项都可留空，装完再填 | 一致（B8 修复后） | 一致 |
| §一 架构 | 支持 x86_64/aarch64/armv7/i386；不支持会明确报错 | 一致 | 一致 |
| §三 路径表 | 4 行路径 | 与代码一致（`config.json` 首次启动才出现，见 O6） | 一致（需补一句） |
| §四 升级 | 保留 `settings.conf` 与 `config.json` | 一致 | 一致 |
| §六 自建服务端 / 保存自动重启 | 可改服务端地址端口；保存时若在运行会自动重启 | 一致（CGI 用 stop+start 实现） | 一致 |
| §六 Q（点启动没反应） | 「看日志，最后几行会写明原因」 | 多数失败路径确实写了；但 **B3 那条路径一行有效信息都没有** | 基本一致，B3 修复后更准 |
| §八 | 「253 断言 PASS / 0 FAIL、14 组对照组」详见 `docs/VALIDATION.md` | 文件存在；断言数字未复核（非本次范围） | 未核（不冲突） |
| §九 目录结构 | 与 `git ls-files` 一致；`dist/`、`research/` 已被 `.gitignore` 排除 | 一致 | 一致 |

---

## 6. 测试环境清单与未验证项

### 6.1 已实测（本轮亲自跑出）

- **安装/启动/停止/状态**主流程；无 Token 安装+启动（`config.json` = `{"network":{"Token":0}}`，进程常驻、`status` 报运行中）；空 Token 时 `token=`/`node=<主机名>`/默认值回落。
- **文件权限**：`DATA_DIR` 700、`settings.conf` 600、`config.json` 600、二进制 711。
- **Token 不泄漏**：`/proc/*/cmdline` 命中 0；日志与安装进度文件均无 Token；明文只出现在 `settings.conf`、`config.json`（均 600）。
- **架构**：9 种不支持架构快速失败 + `amd64`/`i686` 正常识别。
- **主机名**：空/大小写/中文/65 字符/带点/带空格斜杠 六种脏值。
- **locale**：`C` / `C.utf8` / `en_US.utf8` / `zh_CN.UTF-8`。
- **日志目录不可写 / `/var/log/apps` 不存在 / `TRIM_TEMP_LOGFILE` 不可写**：`rc=0`，**0 字节 stderr 泄漏**。
- **ENOSPC（写满的 tmpfs）**：install/start 均 `rc=1`，0 字节泄漏，原因写进进度文件。
- **缺二进制**：数据目录有二进制 → 沿用；处处都没有 → `rc=1` + 明确报错。
- **`date -d @` 不可用**、**无 python3** → 均优雅降级。
- **升级保留配置**：`settings.conf`/`config.json` md5 不变。
- **符号链接数据目录下的三个阻塞项**（B1/B2/B3）。
- **真机只读观测**：`shares/*` 全为符号链接（20 抽样）、安装后属主权限（root:root + ACL）、依赖命令存在性、安装目录形态。

### 6.2 环境

沙箱主机 = 作者这台 fnOS（uid 868 非 root；应用以 root 运行），所有用例在 `/tmp/port/` 的私有 namespace 内执行；`/var/apps`、`/var/log`、`/vol4` 在 namespace 内均被 bind 到 `/tmp/port/fake*`，`stat -c %d:%i` 校验通过后才做任何删除。

### 6.3 交付件与真机状态

- 真机 `/var/apps/openp2p/manifest` → `version = 3.25.11-7`，且 `cmd/common` 的 md5 与 `-7` fpk 内**逐字节相同**（`df79adaa678e9cd9798b3a1ecdeec14e`）⇒ **真机装的是 `-7`，`-8` 未装机**【实测】。
- `-7` 与 `-8` 的差异文件：`cmd/common`、`cmd/install_callback`、`cmd/upgrade_callback`、`app.tgz::ui/index.cgi`、`manifest`【实测】。
- `-8` 与当前源码树**逐字节一致**（除 manifest 版本号）【实测】。

### 6.4 未验证项（明确列出）

1. **真机安装/升级 `-8`**：应用中心"更新"、`upgrade_init/callback` 被 fnOS 调用的时机与实参、升级后进程重启是否保留配置（沙箱只覆盖了脚本层）。
2. **真机卸载时 `openp2p_data_action` 的实参传递**（§4 假设 15）——直接影响 B1 的表现形式。
3. **整机重启后的自启**（无重启观测）。
4. **组网真正跑通**：沙箱用假 Token，只验证到"进程起来、DNS 可解析、PublicIP 获取"；`login ok` / `sdwan init ok` / 端口转发实际连通未验证。
5. **armv8l / i386 / armv7 原生运行**（只在 x86_64 上实跑；其余为架构识别层验证）。
6. **向导 UI 与应用界面的浏览器端渲染**（fnOS 网关不可达）；**多用户/共享权限**（`@appshare` 的 `openp2p` 用户 ACL）与**文件管理器里能否看到这些文件**。
7. **自建服务端**（`serverhost/serverport` 生效）、`loglevel` 语义、`apps[]` 与 console 端 P2PApp 的同步行为。
8. `/usr/local/apps/@appdata/openp2p`（真机 `TRIM_PKGVAR`）的实际权限形态：本次以"不可写"假设构造了 B3，未取得该目录的真机读数。

---

## 7. 过程纪律与事故披露

1. **工作区只读**：`projects/`、`dist/`、`teams/` 未做任何写操作；所有产物在 `/tmp/port/`。清理沙箱前统一 `chmod -R u+rwX` 再 `rm -rf`。
2. **事故披露（如实记录）**：搭 harness 的**第一版** `nsnb.sh` 在 bind mount 之前就执行了清理语句，导致对**真机 `/var/apps`** 发起了一次删除尝试，产生约 1311 行 `Permission denied`。**复核结论：真机 `/var/apps` 内容完好**——当时以非 root 身份运行，无删除权限，事后 `ls /var/apps` 仍为 55 个应用、无缺失。**随后 harness 已改为"先 bind、再用 `stat -c %d:%i` 断言 `/var/apps` 与私有目录是同一个 inode、断言通过后才允许删除"**，之后所有用例均在该保护下执行。此事故与包本身无关，但属于必须向团队披露的操作失误。
3. **root 进程与 `/volN/@appshare` 真机目录不可读**：这是本机环境限制（真机上 openp2p 以 root 运行、`/volN/@appshare` 只对特定 uid 可读），**不作为缺陷计入**，仅在需要真机读数时标注"未验证"。
4. 沙箱内所有破坏性操作只作用于 `/tmp/port/fakevar/**`、`/tmp/port/fakevol4/**`、`/tmp/o2p-repro/**`。

---

## 附录 A：证据索引

| 文件 | 内容 |
|---|---|
| `/tmp/port/nsnb.sh` | 陌生人机器 harness（私有 mount+pid ns、bind + inode 断言、hostname 桩、真机形态符号链接） |
| `/tmp/port/repro-report.sh` / `repro-report.log` | **B1/B2/B3 的最小复现集**（报告 §2 中的命令即出自此处，已自测通过） |
| `/tmp/port/nb-evidence.sh` / `.log` | E1 文件清单与权限、E2 Token 明文分布与 argv 扫描、E3 卸载删除、E4 apps 清零、E5 main restart、E6 Token 非数字把 JSON 改坏、E7 index.cgi 前提 |
| `/tmp/port/nb-hang2.log` | B3 的 ENOSPC/tmpfs 变体（`rc=124`） |
| `/tmp/port/nb-port.log` | O5 端口占用 |
| `/tmp/port/nb-misc.log` | `/var/log/apps` 缺失自愈、`TRIM_TEMP_LOGFILE` 不可写 |
| `/tmp/port/nb-lifecycle.log` / `nb-hostile.log` / `nb-apps.log` | 生命周期、异常输入、无 Token 与 apps 保留的早期用例 |
| 真机（只读） | `/var/apps/*/shares/*` 符号链接抽样、`/var/apps/openp2p/manifest`、`/usr/local/apps/@appcenter/openp2p` 属主与 ACL、`command -v` 全表 |

**一句话交付结论**：主干（装、起、停、状态、无 Token、架构失败、locale、主机名兜底）陌生人机器上都能跑；**但"删除配置"在 fnOS 上百分之百删不掉 Token（B1，必修）**，另有 `apps[]` 静默清零（B2）与状态目录不可写时界面无限挂死（B3）两条条件性阻塞，另需在公开前补一次 `-8` 真机升级冒烟。
