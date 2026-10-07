# QA 证据索引 — openp2p fnOS fpk（当前产物 `openp2p_3.25.11-11_all.fpk`）

> **本索引由 `qa/make-index.py` 生成**（不是手写的）。手写的哈希会腐：上一版就因为
> 「写完后又被改动的文件」与「没记录配方的聚合哈希」被独立 QA 连抓两次（第四轮 BLK-1/C1）。
> 复算方式：`cd teams/dev-squad/runs/20260930-openp2p-fpk/qa && python3 make-index.py --check`。
> 打印 `OK` = 「索引里每个数字都能从当前的实物重新算出来」；打印 diff = 索引已腐（实物变了索引没跟上，或索引被手改）。

> **历史事故**：本文件曾于 2026-09-30 18:04 被写坏成 53 字节残骸（整文件只剩一行
> `...(argument truncated)`），全部绑定丢失。现已改为脚本生成，从根上消除该类事故。

- 生成时间：`2026-10-07 22:45:21`
- 生成脚本自身：`qa/make-index.py` sha256 `17dc3d0bb950e58f4630fbde283e57e221000107550657f2001345140590bc64`
- **自检**：`python3 make-index.py --check` → 一致则打印 `OK`；实物变过而索引没跟上则打印 diff 并非零退出。

## 0. 前提与环境（影响所有结论）

- 复核身份：`appuser`（uid 868，**非 root**）；真机上应用以 **root** 运行。
  因此「杀掉真机残留 root 实例」「跨用户伪装认领」本环境**做不到**，见 §7。
- ⚠️ **本机环境自带 `TRIM_APPNAME=appuser`、`TRIM_APPDEST`、`TRIM_PKGVAR`、
  `TRIM_TEMP_LOGFILE`**。脚本若直接 source `cmd/common` 而不覆盖它们，会算出
  `/var/apps/appuser` 的路径、在错误目录上得出结论。`repro.sh` 开头已固定
  `TRIM_APPNAME=openp2p` 并 unset 其余。

## 1. 产物硬绑定

| 产物 | 状态 | md5 | sha256 | 大小(字节) | mtime |
|---|---|---|---|---|---|
| `openp2p_3.25.11-8_all.fpk` | **当前交付**（第六轮：N5-1~N5-6 处置 + 数据目录结构性保护） | `6898fc7f073c0ab8699eee5299916aec` | `9df9220747f4ee0f2c95fd2b153c8d380224f3213f74fbd04a69048a7a3896fa` | 16384143 | 2026-10-01 03:07:11 |
| `openp2p_3.25.11-7_all.fpk` | 已交付并**真机验收通过**（实例唯一/停止-启动幂等/组网登录成功），被 `-8` 取代 | `3608a54efe1b966d6e80e93195e815d1` | `6fb75699f1870e7340fb3dae0c8dfd33ad48a8a6c0289f928648cc65054fa651` | 16382785 | 2026-09-30 19:05:47 |
| `openp2p_3.25.11-6_all.fpk` | 作废（P2-A/B：回调泄漏 / 保存失败把应用丢在停止态） | `8cfa038075a2cfd51b6a4cf96484562a` | `3e5ddb4aef0e58dcca21fb2c6fab3ee88f61bbe0ba4c9e5e4f0639d4dbf04c2b` | 16381609 | 2026-09-30 18:17:47 |
| `openp2p_3.25.11-5_all.fpk` | 作废（保存失败仍谎报） | `a6a8e5257c47a2844befea2a934d5770` | `5a1d65875ff983220545d60fb498798068857064d974080ecd73a70b46c7c9ba` | 16379947 | 2026-09-30 17:52:47 |
| `openp2p_3.25.11-4_all.fpk` | 作废（N2 未真修） | `a9ba988810b383481513eb6ad431301a` | `be6fccb8891890cdf125f621566dc6d180b15a62ed8cacb192c1d84fd1e9575d` | 16379492 | 2026-09-30 17:19:16 |
| `openp2p_3.25.11-3_all.fpk` | 作废（曾被交付） | `91858f742f868a06dc717b8f2b42f646` | `b07be8b60a1fe26bedfa29c96500b1e7367e350559c9dea535908a66909a7057` | 16377953 | 2026-09-30 16:55:06 |
| `openp2p_3.25.11-2_all.fpk` | 作废 | `319db26d162f35a645cef939132ba052` | `225f469c7f8d8652331b4bd1442b1e1df63159927cced168f274b639720ade64` | 16374945 | 2026-09-30 16:24:20 |
| `openp2p_3.25.11-1_all.fpk` | 作废（真机在装，缺陷最全） | —（文件不在工作区） | — | — | — |

当前产物内部一致性（**已实跑**）：

```bash
tar -xOf $DIST/openp2p_3.25.11-11_all.fpk manifest | grep -E "^(version|checksum)"
tar -xf  $DIST/openp2p_3.25.11-11_all.fpk -C /tmp/v && md5sum /tmp/v/app.tgz
diff -r src/openp2p/cmd /tmp/v/cmd        # 必须完全一致（防"源码改了包里没改"）
```

- `manifest.version` = **`3.25.11-11`**
- `manifest.checksum` = **`245ea3054776d4fd6b402a3d2e2a8687`**；实测 `md5(app.tgz)` = **`245ea3054776d4fd6b402a3d2e2a8687`** → 一致 ✅

## 2. 测试日志绑定（块 A–H、D、复现集）

| 日志 | 行数 | sha256 | mtime | 汇总 |
|---|---|---|---|---|
| `exec-A.log` | 67 | `aa2fd2d8806f0bdaf2f1a187980a2a9dd1907a1ab936f358ab74cc6bd128bf29` | 2026-10-07 22:38:32 | PASS=26 FAIL=0 |
| `exec-B.log` | 75 | `0647c38b55405389bac2a8d7dfcc190ea4ba99686f7c06301dfa76268d20881c` | 2026-10-07 22:39:11 | PASS=30 FAIL=0 |
| `exec-C1.log` | 30 | `73689491dc74edc525722b19bb3c0f45ca953a42a6447ac1858af1c0526b6f4a` | 2026-10-07 22:39:37 | PASS=18 FAIL=0 |
| `exec-C2.log` | 40 | `2c3e73109be9ca2f5e5fe3c5d932df9643d7e7ef7ac714ca999a6c36f03f3aa6` | 2026-10-07 22:40:09 | PASS=26 FAIL=0 |
| `exec-D.log` | 18 | `9cfe751b4f75cebe28c8ee5be49e685917f046fb8e1789bcc7a34aa9259c34eb` | 2026-10-07 22:40:10 | PASS=3 FAIL=1（i386 环境受限，见 §7） |
| `exec-E.log` | 40 | `ee2d9261c9445ba7805c120ffdd11605a1fc3b0f7c53dc3dca81a3576f3150d6` | 2026-10-07 22:40:11 | PASS=21 FAIL=0 |
| `exec-F.log` | 33 | `5ed340b3eb30af3c62d41389955d319a60b94e2b2b30ff8ba3480a6b67664cd4` | 2026-10-07 22:40:28 | PASS=16 FAIL=0 |
| `exec-G.log` | 53 | `5cc8e71e722fffd31ce96ddb26d30732480d88c95182f6a0beba605c120a4125` | 2026-10-07 22:41:21 | PASS=29 FAIL=0 |
| `exec-H.log` | 153 | `d78c20f3527c704806e81dec46df4d361de82464535de1ab11bfccacb1b35bae` | 2026-10-07 22:42:10 | PASS=87 FAIL=0 |
| `exec-I.log` | 68 | `78b1aaa09dde48c3f2476e4e866e62ee175641882899353f23d89b37182ff702` | 2026-10-07 22:43:06 | PASS=37 FAIL=0 |
| `repro.log` | 49 | `bebae83449c96894194fdc38033f78649998bb02a333da6fe4a57115089f0c66` | 2026-10-07 22:42:18 | OK=17 BAD=0 |

- **A/B/C1/C2/E/F/G/H/I 合计 PASS = 290**（FAIL=0）；块 D 另计 3 PASS / 1 FAIL（i386，环境受限）。
- 块 G/D/H 的被测对象是从**源码树**拷贝的 `cmd/`；该拷贝与 fpk 内 `cmd/` 逐字节一致由 §1 的 `diff -r` 证明。
- 块 I 的被测对象是**源码树** `src/openp2p/cmd/*`（可移植性阻塞项 B1/B2/B3 的修复），
  对照组取自冻结快照 `legacy-8-cmd/`（B1/B2/B3/B3'）与 `legacy-9-cmd/`（N5~N10）——`legacy-10-cmd/`（N11~N14）——即"同一场景下旧实现必须失败"。

## 3. 测试脚本自身绑定（防"日志与脚本对不上"）

| 脚本 | sha256 |
|---|---|
| `exec-A.sh` | `b5becf9e29759c0d115ec99fb49401cc793e8d8cac18a05a56eba1f5d6b27c8e` |
| `exec-B.sh` | `af0325903ec42d3cff373fa421e14d2ac940e8cff4943bbc51b9423569d02042` |
| `exec-C1.sh` | `c268b4295ebe032978b1fa44cd5d2e9fd336bbf1ffdc45ec1b10983ba1c0e1cf` |
| `exec-C2.sh` | `5bd10cfa82e36570bec787cb63d6910ebb2797aa4f68b5ea119f2718715bae1b` |
| `exec-D.sh` | `eab92d23caad994142fb62af567538409615d713f45266fef7020d710ec3c32f` |
| `exec-E.sh` | `764e055165afd9894064cc065ac70cef272c45ab1e7ab1d3e03211b5cfcf04e9` |
| `exec-F.sh` | `59d3fed0f27c618a6fc30cbd129b0510a3b4ab737c85762b65b41a6c7b76e79d` |
| `exec-G.sh` | `28fcdd80fae25ba793ec6cb1d2a77e6151a860464c855c1f690a8daee0b4a900` |
| `exec-H.sh` | `b776b6ab34e3363975616bdd96113e5c034f0be29f7a14a5f36d2b87e5269804` |
| `exec-I.sh` | `fe93361efbc26fae1d3aa867401488ff572e34840fa6e820b629e7a7d4d493a8` |
| `repro.sh` | `6ec901c8341906f43b02b55a601d0c3b2b4007e21f2466092017656b289ff61c` |
| `make-index.py` | `17dc3d0bb950e58f4630fbde283e57e221000107550657f2001345140590bc64` |
| `testcases.md` | `106b68b963385a09a5370de2f376eb4b0833b8cd2a204b8762c29115e41c0641` |
| `qa-round5-review.md` | `8336f811bbf42c7df46fc767cf9210c6222583b6b4dbbe42a64a1a1601f08583` |
| `qa-round6-review.md` | `2b40ec71695d3c7c657b0f6e09f7e5cd560ed7d285dce8d79d83c8dc9ff137b7` |
| `qa-portability-review.md` | `5f1f83927fd476e2bdfab2b693270d7de60f665452aaf66ca0bd1725b97c34e1` |

## 4. 对照组快照绑定（"用例有鉴别力"的实体）

没有对照组，「PASS」可能只是「怎么写都通过」。本目录的对照组：

| 快照 | 来源 | sha256 |
|---|---|---|
| `legacy-3.25.11-1-cmd/`（10 文件） | 真机 `-1` 的 `cmd/` 代码快照（用户实际安装的版本） | `dd95771a3c18f6b977180cedefde5c5d5559db6693146bc0a227ab3a96a2a15f`（配方见下） |
| `legacy-cmd/common.from-6` | `-6` 包内 `cmd/common`（P2-A 对照组） | `fa434ac271882a5bad67637100849c86a99a246bc423c6da10b12b5ef73a287f` |
| `legacy-8-cmd/`（10 文件） | `-8` 包内 `cmd/`（B1/B2/B3/B3' 对照组） | `3ca2dbbd535da1cfb6a31dbf34bf6ba20872731b6661c5ab842ff1ac08fcbc12`（配方见下） |
| `legacy-9-cmd/`（10 文件） | `-9` 包内 `cmd/`（第七轮评审已审，N5~N10 加固前） | `b7b079a90e41ab430edd018631006c1983b505d2b714d1aab8fb1ebfc26619e9`（配方见下） |
| `legacy-10-cmd/`（10 文件） | `-10` 包内 `cmd/`（第七轮 b 已审，N11~N14 加固前） | `734823a27bfb7f514deb3c336471fdeb75ebddb5a29b1a5469a4d92c20061d97`（配方见下） |
| `legacy-ui/index.cgi.from-2` | `-2` 包内 `ui/index.cgi` | `b4943a8cc82013e5dc472b5a9950e77e24b4f587d1ebe50348ded440d66b5244` |
| `legacy-ui/index.cgi.from-3` | `-3` 包内 `ui/index.cgi` | `ed10466c5c612214c234ac0cbd265d05a9158a9ddbcded05b41b22c355d433d5` |
| `legacy-ui/index.cgi.from-5` | `-5` 包内 `ui/index.cgi` | `86217c8f8f1fe075476a3673c61f136c43e6a7a081c762417571fac78153b511` |
| `legacy-ui/index.cgi.from-6` | `-6` 包内 `ui/index.cgi` | `f0527a8bb491f9484b838dbc8b7578886cf95b3fad354c7337e51f754b695c7b` |

**聚合配方**（§4 目录行的哈希如何复算）：按文件名字典序，把「文件名 + 文件内容」
依次喂进同一个 `sha256` 上下文，输出十六进制摘要。等价于：

```bash
python3 - <<'EOF'
import hashlib, os
d = 'teams/dev-squad/runs/20260930-openp2p-fpk/qa/legacy-3.25.11-1-cmd'
g = hashlib.sha256()
for f in sorted(os.listdir(d)):
    g.update(f.encode()); g.update(open(os.path.join(d, f), 'rb').read())
print(g.hexdigest())
EOF
```

对照关系（每条都实跑过；**旧版本必须失败/被拒**，否则该用例不算数）：

| # | 被测点 | 新版本 | 对照组 | 位置 |
|---|---|---|---|---|
| 1 | 降级分支（`cmd/common` 不存在）泄漏 `command not found`（N1） | 零泄漏 | `-3` 泄漏 127 字节 | `exec-H.log` H2 |
| 2 | `stop` 失败不得谎报「已停止」 | 如实提示 | `-2` 谎报「应用已停止」 | `exec-H.log` H6 |
| 3 | 保存设置写失败：不得谎报/泄漏/把应用丢在停止态（BLK-3、P2-B） | 如实报错 + 零泄漏 + 应用不受影响 | `-5` 谎报且泄漏；`-6` 把应用静默丢在停止态 | `exec-H.log` H9/H13/H14、`repro.log` R3 |
| 4 | `log_msg/warn_msg` 日志不可写时零泄漏（P2-1） | 0 字节 | `-4` 泄漏 299 字节 | `repro.log` R2c |
| 5 | `find_all_pids` 不认领 argv0 伪装进程（P2-4） | `[]` | `-4` 认领并会杀掉它 | `repro.log` R4 |
| 6 | 符号链接数据目录下 `is_our_pid` 为真（B11 真机根因） | TRUE | `-1` FALSE（恒假→重复起实例） | `repro.log` R5、`exec-G.log` G9 |
| 7 | 数据目录不可写时安装/升级回调零泄漏（P2-A） | 0 字节 | `-6` 泄漏 `cp: ... Permission denied` | `exec-H.log` H15 |
| 8 | 含 Token 的临时文件与进程 umask 无关地 0600（P2-D + 同类漏改） | umask=000 下仍 600 | `-6` 留下 666 | `exec-H.log` H16 |
| 9 | 日志轮转沿用原权限（600 不被 `>` 重定向放宽） | 轮转后仍 600 | `-6` 轮转后变 666 | `exec-H.log` H17 |
| 10 | `save` 写失败不得把运行中的应用丢在停止态（P2-B） | 仍在运行 + 文案交代 | `-6` 静默停在停止态 | `exec-H.log` H13/H14 |
| 11 | 数据目录结构性保护：0755 → 摘掉组/其他人权限，且**不放开** 0500（真机 umask 不生效） | 700 / 0500 保持 | `-6` 保持 755 | `exec-H.log` H21 |
| 12 | 打错的 Token 不得被原样回显进（0644 的）日志（N5-1） | 0 次出现 | 机械变异回旧写法即泄漏 | `exec-H.log` H18 |
| 13 | 冷启动写 `config.json` 一创建即 0600（N5-2，用 `chmod` 函数桩堵死"事后收紧"） | umask=000 下 600 | `-6` 在 chmod 桩下暴露创建时权限 | `exec-H.log` H19 |
| 14 | 安装/升级的失败提示必须**追加**、不得截断 fnOS 进度文件（N5-3） | 既有内容保留 | 机械变异回 `>` 即截断 | `exec-H.log` H20 |
| 15 | 卸载选「删除配置」必须真删到数据卷（数据目录是**符号链接**，B1/P1） | 真删 + 白名单守卫 + 删完自检 | `-8` 只删掉链接本身，Token 原封不动 | `exec-I.log` I1 |
| 16 | 冷启动写 Token 不得整文件覆盖、`apps[]` 必须保留（B2/P2） | 只改 Token 字段 + 备 `.bak`(0600) | `-8` 覆盖全文 → 手写规则静默清零 | `exec-I.log` I2 |
| 17 | 运行时目录建不出来时锁必须**快速失败**（B3/P3） | rc=1 + 明确文案 | `-8` 0.2s 死循环（`timeout` rc=124，界面挂死） | `exec-I.log` I3 |
| 18 | 陈旧锁 + 锁目录删不掉（只读挂载/EBUSY/immutable）也不许忙等挂死（B3'） | 2 秒内 rc=1、日志 5 行 | `-8` `timeout` 12 秒不返回（rc=124 忙等） | `exec-I.log` I4 |
| 19 | 卸载白名单必须精确：`$APPDIR/*` 过宽会删掉安装目录 `target/`（N5） | 拒绝并保留 target | `-9` 把 `target/` 一起删了 | `exec-I.log` I5a |
| 20 | `$APPDIR` 是符号链接时仍要能真删配置（N6） | 删除成功 | `-9` 误判为拒绝 → Token 留存 | `exec-I.log` I5b |
| 21 | `config.json` 是符号链接时写进真实目标、不脱链（N7） | 链接保留 + 目标已更新 | `-9` 链接被换成普通文件 | `exec-I.log` I5c |
| 22 | 锁的属主进程还活着时绝不夺锁（N9）；锁路径被普通文件占用要能自愈（N10） | 等待超时 rc=1 / 自动清理后取锁 | `-9` 夺走活进程的锁 / 永久挡住 | `exec-I.log` I5d、I5e |
| 23 | 读锁属主必须**有界**：owner 是 FIFO//dev/zero/符号链接时不许被拖死（N11） | 0~2 秒内 rc=1 | `-10` 8 秒不返回（rc=124） | `exec-I.log` I6a |
| 24 | owner 文件缺失时不得往 stderr 吐字节（N12） | 0 字节 | `-10` 泄漏 200 字节 | `exec-I.log` I6b |
| 25 | 测试注入点被塞超长数字时，超时判据不许失效（N13） | stderr 0 字节、仍在等 | `-10` 每 0.2 秒报 integer expression error → 永不返回 | `exec-I.log` I6c |
| 26 | `config.json` 指向数据目录**之外**的符号链接必须拒绝改写（N14） | rc=1 且外部文件未含 Token | `-10` 把 Token 写到了数据目录之外 | `exec-I.log` I6d、I6e |

## 5. PASS 计数口径（**唯一定义**，避免"216 vs 213"式的口径打架）

「总 PASS」= 块 **A + B + C1 + C2 + E + F + G + H + I** 的 PASS 行数之和。
**块 D（跨架构）不计入总数**，单独列报（i386 在本机 qemu 下与官方 Go 386 二进制同崩，属环境受限）。

| 块 | 覆盖内容 | PASS | FAIL |
|---|---|---|---|
| **A** | 包结构与清单（manifest / 文件清单 / 权限位 / checksum / version / 目录布局） | 26 | 0 |
| **B** | `cmd/common` 纯函数（safe_port/safe_bw/js_escape/路径推导/TRIM_* 覆盖） | 30 | 0 |
| **C1** | `cmd/main` start/stop/status 时序（含 PID 文件与实例单例） | 18 | 0 |
| **C2** | 判活与进程归属（`is_our_pid` / `proc_exe_is_bin` / `find_all_pids` / 符号链接） | 26 | 0 |
| **D** | 跨架构（i386 模拟执行）——环境受限，不计入总数 | 3 | 1 |
| **E** | `install_callback` / `upgrade_callback` / `config_callback` 回调语义 | 21 | 0 |
| **F** | `build.sh` 打包链路与可重复性 | 16 | 0 |
| **G** | `ui/index.cgi` 后端行为（保存、校验、备份、降级） | 29 | 0 |
| **H** | 缺陷回归：每条历史缺陷一个用例 + 一个"旧版本必须失败"的对照组 | 87 | 0 |
| **I** | 可移植性专项（B1/B2/B3/B3'）与两轮评审加固（N5–N7、N9–N14） | 37 | 0 |
| | **合计（不含 D）** | **290** | **0** |

**上一版索引写「216」是错的**（当时代码块 C 与 H 的行数被重复相加）。现在这个数字由本脚本
从日志实际解析 `PASS=` 行得出，并附每块的日志 sha256（§2），第三方可自行复算。

## 6. 复现集 `repro.sh`（脱离测试框架的独立复现）

`repro.sh` 不依赖 exec-*.sh 的任何辅助函数，自己起沙箱、自己造桩，用来回答
「换一个人、换一台机器，能不能复现出同样结论」。当前：**17 OK / 0 BAD**（见 `repro.log`）。

| # | 复现项 | 断言 |
|---|---|---|
| R1 | 符号链接数据目录下 `is_our_pid` | 必须为真（真机根因 B11） |
| R2 | 日志不可写时 `log_msg/warn_msg` | stdout+stderr **零字节**泄漏 |
| R2c | 同上，对照组 `-4` | 泄漏 299 字节（证明用例有鉴别力） |
| R3 | `ui/index.cgi` 保存设置写失败（目录只读） | 不得输出「✅ 已保存」，零裸错误泄漏 |
| R4 | `find_all_pids` 遇到 `exec -a` 伪装 argv0 的进程 | **不得认领**（`-4` 会认领并杀掉） |
| R5 | `-1` 快照下同一符号链接场景 | 必须为假（证明 R1 不是天然成立） |
| R6 | `stop` 面对多个实例（B12） | 全部回收，不留残党 |

**P2-A / P2-B / P2-D 的独立复现**落在块 H（H15 / H13 / H14 / H16 / H17），因为需要构造
「数据目录不可写」「保存写失败」「把 umask 设成 000 并打死 mv/rm 以留住临时文件」这几种受控现场——
`repro.sh` 的沙箱形态不适合承载它们，故未重复（**已知取舍**，非遗漏；若需要，H13/H15/H16 的桩
可直接搬到 `repro.sh`，代价是沙箱复杂度翻倍）。

## 7. 未覆盖 / 环境受限（**不得当已验收**）

| # | 项目 | 原因 |
|---|---|---|
| U1 | 真机应用中心安装/升级/修复重装 | 需真机 UI 操作与 root；沙箱无权限。**已登记为用户侧冒烟步骤** |
| U2 | 真机 OS reboot 后自启留存 | 同上（需重启 NAS） |
| U3 | i386 原生执行 | 本机无 386 内核；qemu-i386 下官方 Go 386 二进制同样崩溃 → **不能据此判定包损坏**（块 D 的 1 条 FAIL 即此） |
| U4 | armv8l 原生真机 | 无 arm 设备 |
| U5 | `hidepid=2` 等非常规 `/proc` 挂载 | 本机 `/proc` 为默认；`proc_exe_is_bin` 在 EACCES 时退化为只比 argv0（**能力上限**，代码内已注释） |
| U6 | `TRIM_APPNAME` 在真机的真实取值 | 真机安装需 root + UI；沙箱用固定值覆盖验证了「被覆盖时不误判」 |
| U7 | ENOSPC（磁盘满）下 `save` / `raw_save` | 无 quota/mount 权限构造真实 ENOSPC；已用「目录不可写」近似覆盖写失败路径 |
| U8 | 跨用户伪装进程认领（root 进程伪装成我们的 exe） | 非 root 无法构造跨 uid 现场；已用同 uid `exec -a` 伪装覆盖（R4） |
| U9 | 用户真机当前仍在运行的两个 root 遗留实例（PID 2795664 / 2800553） | **我无权限 kill**；升级后点「停止」→「启动」即可由 B12 逻辑一次清掉 |

以上 U1–U9 均**不能以沙箱结论替代**。U1/U2 是交付前唯一真正必须由用户完成的一步（见 §8 冒烟）。

## 8. 变异测试（证明用例"真的会红"）

QA 在 `/tmp` 副本上做（不污染本目录）：

| 变异 | 预期 | 实测 |
|---|---|---|
| UI 回退成 `-5` 的 `save` 实现 | 块 H 应红 | **6 条 FAIL** ✅ |
| `apply_settings_env` 失败改回 `return 0` | 块 H 应红 | **4 条 FAIL** ✅ |

## 9. 真机验收冒烟（交付后由用户执行，唯一不可沙箱替代的一步）

1. 应用中心**覆盖安装/升级** `openp2p_3.25.11-11_all.fpk`（勿卸载，保留配置）。
2. 不填 Token 直接打开界面 → 必须能进（B8：早期版本此处死锁）。
3. 填 Token 保存 → 文案为「已保存」且**不再出现裸 `Permission denied`**（BLK-3/P2-B）。
4. 状态页显示「运行中」，且 `ps` 里**只有 1 个** openp2p 实例（B11/B12）。
5. 点「停止」再「启动」（或「重启」）→ 仍只有 1 个实例，日志无 `bind: address already in use`。
6. 重启 NAS → 应用自动起来，仍只有 1 个实例。

任何一步不符：把 `/var/log/apps/openp2p.log` 与界面文案截图发回，我按同样的「用例 + 对照组」流程定位。

