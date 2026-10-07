# 测试执行器（沙箱）

这里是从开发机**原样搬过来**的执行器与运行日志，用于让 `docs/VALIDATION.md` 里的数字可审计。

## 目录

| 文件 | 说明 |
|---|---|
| `exec-A.sh` / `.log` | 块 A：安装 / 卸载生命周期（TC-01 ~ TC-09） |
| `exec-B.sh` / `.log` | 块 B：启动 / 停止 / 状态 / 幂等（TC-10 ~ TC-18） |
| `exec-C1.sh` / `.log` | 块 C1：卸载数据保留、日志、非法输入拒绝 |
| `exec-C2.sh` / `.log` | 块 C2：越界回退、命令注入、脏 pid、包结构 |
| `exec-D.sh` / `.log` | 块 D：跨架构真实执行（qemu-user-static）|
| `exec-E.sh` / `.log` | 块 E：架构映射 + 四架构真二进制佐证 |
| `exec-F.sh` / `.log` | 块 F：无 Token 死锁回归 |
| `exec-G.sh` / `.log` | 块 G：真机根因回归（判活 / 符号链接路径形态） |
| `exec-H.sh` / `.log` | 块 H：界面层 `app/ui/index.cgi` 回归 |
| `repro.sh` / `.log` | 端到端复现集（安装→启动→幂等→卸载 等 17 项）|
| `round5-rerun/` | 独立复核时的重跑日志、专项小脚本，以及 `mutants/`（回退变异体） |

## 怎么跑

脚本里的路径、包名、沙箱根目录都是**按开发机硬编码**的（形如
`<repo>/dist/openp2p_3.25.11-8_all.fpk`），直接搬走不能原样执行。要复跑请：

1. 先构建出包（见仓库 README「从源码构建」），放进 `dist/`
2. 按需改脚本顶部的 `PKG` / `R`（沙箱根，建议放 `/tmp`）变量
3. 逐个执行，例如：

   ```bash
   bash tests/qa-harness/exec-B.sh | tee /tmp/exec-B.log
   ```

   脚本自带 `res()` 计数，结束会打印 `PASS/FAIL` 统计。

## 两点注意

- 脚本会覆写 `OPENP2P_APPROOT`，把 `cmd/*` 与 `ui/index.cgi` 的操作**重定向到沙箱**，
  不会碰到真机应用目录。但仍建议在测试机上跑，而不是生产机。
- `round5-rerun/mutants/` 里是**故意改坏的**源码副本（用于证明用例有鉴别力），
  它们不是可用代码，不要拿去打包。

## 日志里能看到的"对照组"约定

- 正常用例打印 `[PASS] / [FAIL]`；
- 对照组（旧版本或变异体）必须打印 `LEAK / NOLEAK`、`truncated / preserved` 一类**成对标记**，
  证明两种情况下日志形态真的不同——只有单侧输出说明用例没区分能力。
