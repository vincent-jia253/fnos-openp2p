# 测试执行器（沙箱）

这里是从开发机搬过来的执行器与运行日志，用于让 `docs/VALIDATION.md` 里的数字**可审计、可复跑**。

## 目录

| 文件 | 说明 |
|---|---|
| `exec-A.sh` / `.log` | 块 A：包结构与清单（manifest / 文件清单 / 权限位 / checksum） |
| `exec-B.sh` / `.log` | 块 B：`cmd/common` 纯函数（端口/带宽清洗、转义、路径推导） |
| `exec-C1.sh` / `.log` | 块 C1：`start`/`stop`/`status` 时序（PID 文件、实例单例） |
| `exec-C2.sh` / `.log` | 块 C2：判活与进程归属（`is_our_pid`、符号链接、脏 PID） |
| `exec-D.sh` / `.log` | 块 D：跨架构真实执行（qemu-user-static；环境受限，不计入总数） |
| `exec-E.sh` / `.log` | 块 E：架构映射 + 四架构真二进制佐证 |
| `exec-F.sh` / `.log` | 块 F：「没填 Token 就永远填不上」死锁回归 |
| `exec-G.sh` / `.log` | 块 G：真机根因回归（判活 / 符号链接路径形态 / 守护判定） |
| `exec-H.sh` / `.log` | 块 H：界面层 `app/ui/index.cgi` 回归 |
| `exec-I.sh` / `.log` | 块 I：**可移植性专项**（卸载真删 / Token 不覆盖 `apps` / 锁不挂死）与两轮评审加固 B3'、N5–N14 |
| `repro.sh` / `.log` | 端到端复现集（安装→启动→幂等→卸载 等 17 项） |
| `evidence-index.md` | **证据索引**：把每个结论绑定到具体文件的 sha256 / md5 / 行数 / mtime |
| `make-index.py` | 生成上面的索引（开发机侧另有 `--check` 自检"索引是否还在说真话"） |
| `testcases.md` | 用例矩阵（编号 → 覆盖点 → 断言） |
| `qa-round*.md` / `qa-portability-review.md` | 独立复核报告（对抗性评审 + 定向复验） |
| `legacy-8-cmd/`、`legacy-9-cmd/`、`legacy-10-cmd/` | **冻结快照**：旧版 `cmd/*`，块 I 的"旧实现必须失败"对照组 |
| `round5-rerun/` | 更早一轮复核的重跑日志、专项小脚本，以及 `mutants/`（回退变异体） |

## 怎么跑

执行器**路径自动推导**（`$OPENP2P_ROOT` 优先，其次向上找含 `src/openp2p` 的目录），包取 `dist/`
里最新的一版；因此克隆下来就能跑，不必改脚本。

```bash
./build.sh                                  # 先产出 fpk 到 dist/
bash test/simulate-fnos.sh                  # 最快的一条路：端到端生命周期，29 项断言
bash tests/qa-harness/exec-I.sh             # 单块（可移植性专项，37 项）
bash tests/qa-harness/repro.sh              # 脱离框架的独立复现
python3 tests/qa-harness/make-index.py      # 以本目录实物为准，重新生成一份证据索引
```

（`make-index.py --check` 用于开发机侧核对"索引是否还在说真话"：它要求原件与包同时在位，
不适用于本脱敏副本目录。）

脚本自带 `res()` 计数，结束打印 `PASS/FAIL` 统计；需要别的包时设
`OPENP2P_ROOT=<项目路径>` 或把包放进 `dist/`。

## 三点注意

- 脚本会覆写 `OPENP2P_APPROOT`，把 `cmd/*` 与 `ui/index.cgi` 的操作**重定向到沙箱**（`/tmp`），
  不会碰到真机应用目录；但仍建议在测试机上跑，而不是生产机。
- 需要"只读文件系统""锁目录删不掉"这类极端场景时，用 `unshare -rmn` 造私有 mount namespace，
  只影响测试进程自己，不动真机挂载点。
- `round5-rerun/mutants/` 与 `legacy-*-cmd/` 里是**故意改坏/故意留旧**的源码副本，
  不是可用代码，不要拿去打包。

## 日志里能看到的"对照组"约定

- 正常用例打印 `[PASS] / [FAIL]`；
- 对照组（旧版本或变异体）必须打印 `LEAK / NOLEAK`、`truncated / preserved` 一类**成对标记**，
  证明两种情况下日志形态真的不同——只有单侧输出说明用例没区分能力。
- 块 I 的对照组直接跑 `legacy-8-cmd/`、`legacy-9-cmd/`、`legacy-10-cmd/` 里的旧 `cmd/*`，
  每条断言的"旧实现"表现都写在 `evidence-index.md` §4 的对应行里。

## 关于脱敏（哈希为什么对不上）

这里的一切是**运行产物的脱敏副本**：主机名、账号名、内网 IP、个人绝对路径已替换为
`my-fnos` / `demo-user` / `192.0.2.11` / `/path/to`。替换会改变字节，因此本目录内文件的 sha256
与 `evidence-index.md` 里登记的**原件**哈希不同——索引登记的是开发机侧的原件，用于追溯。

`make-index.py --check` 是给**开发机侧**用的（需要原件 + 同目录下的 `dist/` 产物，此处没有），
在本目录内跑会因找不到包清单而报错，属预期；要自己核对，请以本目录实物为准重新生成一份索引。
