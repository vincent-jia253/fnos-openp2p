# OpenP2P for 飞牛 fnOS

把 [openp2p](https://github.com/openp2p-cn/openp2p)（v3.25.11，MIT）封装成飞牛 fnOS 应用包，
在应用中心一键安装、图形界面配置，无需命令行。

**产物**：`openp2p_3.25.11-11_all.fpk`（约 16 MB，单包内含 4 种架构，自动适配）
—— 到本仓库的 **Releases** 下载。

> 这是**第三方封装**，与 openp2p 上游没有隶属关系。上游程序的问题请提到 openp2p 仓库；
> 打包脚本、fnOS 集成、界面（`app/ui/index.cgi`）的问题请提到本仓库。

---

## 一、安装

1. 从本仓库 **Releases** 下载 `openp2p_3.25.11-11_all.fpk` 到本机
2. 打开 **应用中心 → 手动安装**（或「设置 → 应用 → 手动安装应用」），选择该文件
3. 安装向导会问你三件事（**都可以留空，装完再填**）：
   - **Token**：来自 console.openp2p.cn
   - **节点名**：本机在 P2P 网络中的名字，留空自动用 NAS 主机名
   - **共享带宽上限**：默认 10 Mbps，填 `0` 表示不加入共享网络
4. 安装完成后，应用会出现在应用中心，图标可点开

> 支持 x86_64 / aarch64 / armv7 / i386。安装时自动识别本机架构并部署对应二进制；
> 若本机架构不在支持列表内，安装会明确报错而不是装完跑不起来。

## 二、开始使用

1. 浏览器打开 **https://console.openp2p.cn** 注册账号
2. 进入「**个人资料 / Profile**」，复制 **Token**（一串纯数字）
3. 回到 NAS，打开本应用 → 填 **Token** 和 **节点名** → 点「**保存并启动**」
4. 回到 console，给这个节点添加 **P2PApp**（端口转发规则），例如把本机 `3389` 映射出去
5. 在其它设备上装 openp2p 客户端（或用 console 里的连接方式）即可访问

**不需要**自备公网服务器，**不需要**在路由器上做端口映射——打洞失败会自动走中继。

## 三、文件都在哪

| 内容 | 路径 |
|---|---|
| 应用设置（Token、节点名…） | `/var/apps/openp2p/shares/openp2p/settings.conf` |
| openp2p 自己的配置（含端口转发规则） | `/var/apps/openp2p/shares/openp2p/config.json` |
| 运行日志 | `/var/log/apps/openp2p.log` |
| openp2p 二进制 | `/var/apps/openp2p/shares/openp2p/openp2p` |

在「文件管理 → 应用文件」里能直接看到这些文件，可以手动编辑或备份。

> **为什么二进制放在数据目录而不是应用目录？**
> openp2p 固定把 `config.json` 和 `log/` 写在**可执行文件所在目录**（实测：既不是进程工作目录，
> `-installpath` 参数也不改变这一点）。如果把二进制放在应用目录 `target/bin/`，
> 每次升级都会替换该目录，**用户的 Token 和所有端口转发规则都会丢**。
> 因此本封装把二进制部署到持久的数据目录再运行。

## 四、升级

在应用中心点「**更新**」即可。升级流程会：
- 停止旧进程 → 替换二进制 → 重新启动
- **完整保留** `settings.conf` 与 `config.json`（Token、端口转发规则都不丢）

> 不要用「卸载再装」的方式升级——虽然卸载默认保留配置，但直接用「更新」更稳妥。

## 五、卸载

卸载向导会让你选：

- **保留配置（默认）**：Token、节点名、端口转发规则都留下，重装后直接继续用
- **删除配置**：连 Token 一起清掉

> 「删除配置」会真的删到数据卷上（fnOS 的数据目录是符号链接，早期版本只删掉了链接本身，
> 已修复：现在会解析真实路径、带白名单守卫、删完自检，并在日志里如实报告结果）。

## 六、常见问题

**Q：装完日志里写「尚未配置 Token」？**
正常。没 Token 时应用照常启动、界面可用，只是**不会登录组网**——这是故意的：
Token 只能在应用界面里填，如果没 Token 就不启动，界面进不去就永远填不上了。
填好 Token 点「保存并启动」即可。

**Q：应用中心里点启动没反应？**
看日志 `/var/log/apps/openp2p.log`，最后几行会写明原因（运行时目录不可写、二进制异常等）。

**Q：Token 会不会泄露？**
Token **不经命令行参数传递**——否则 `ps` 里任何本机用户都能看到。它只落在数据目录的两个文件里：
`config.json`（openp2p 自己用）和 `settings.conf`（本封装保存的界面设置），
两者权限都是 **600（仅属主可读）**，且目录本身被收紧为 `go-rwx`。日志里不打印 Token。

**Q：想用自建服务端？**
在应用设置里改「服务端地址」和「服务端端口」即可（默认 `api.openp2p.cn:27183`）。

**Q：改了设置没生效？**
保存时如果应用正在运行，会自动重启使其生效。

**Q：端口转发规则在哪配？**
推荐用 console.openp2p.cn 网页配；也可以直接编辑 `config.json` 里的 `apps` 数组后重启应用。
本封装**不会覆盖**你手写的 `apps`：写 Token 时只替换 `Token` 字段（没有该字段就插入），
改写前还会留一份 `config.json.bak`；写入结果必须是合法 JSON 才落盘。

## 七、从源码构建

```bash
./build.sh                    # 默认全架构包（版本号见脚本顶部 VERSION）
./build.sh --version 3.25.12-1
./build.sh --arch x86         # 只打 x86（部分老版本 fnOS 不认 platform=all 时用）
./build.sh --arch arm
```

- 仓库已含四个架构的上游官方二进制（`src/openp2p/app/bin/`）。
  若要自行从上游重新获取并校验：
  ```bash
  ./tools/fetch-upstream.sh --verify   # 只校验现有文件
  ./tools/fetch-upstream.sh            # 重新下载 → 校验 sha256 → 落盘
  ```
- 优先调用官方 `fnpack`；开发机没装时回退到内置打包器（两者产物已逐项比对一致）
- 打包后自动自检：文件清单、manifest 字段、`checksum` 是否匹配、wizard/config 的 JSON 合法性
- 运行时自测：`bash test/simulate-fnos.sh`（模拟 fnOS 完整生命周期）

## 八、测试与验证

完整的验证方法、执行矩阵（**290 断言 PASS / 0 FAIL**、26 组对照组）与**尚未验证的项**，
统一记在 **[`docs/VALIDATION.md`](docs/VALIDATION.md)** —— 本 README 不再复述，避免两处文本各自腐化。

速览：

- `docs/testcases.md` 用例矩阵；`tests/qa-harness/` 执行器与运行日志（脱敏副本，可自行复跑）
- `docs/bugs.md` 缺陷台账（每条含根因、修复、如何验证）
- `docs/qa-review-round5.md` / `round6.md`：两轮独立对抗性复核报告
- `docs/qa-round7-review.md` / `qa-round7b-review.md`：可移植性专项的评审与定向复验
- 一条命令自测：`./build.sh && bash test/simulate-fnos.sh`（29 项断言，路径自动推导）

## 九、目录结构

```
src/openp2p/            应用包源文件（manifest / cmd / app / wizard / config / 图标）
src/openp2p/app/bin/    四个架构的上游 openp2p 二进制（未修改，哈希见 NOTICE）
src/openp2p/cmd/        fnOS 生命周期脚本（install / upgrade / uninstall / config / main / common）
src/openp2p/app/ui/     应用界面（index.cgi，CGI 形式）
build.sh                .fpk 打包脚本（含打包后自检）
tools/fetch-upstream.sh 从上游拉取并校验二进制
test/simulate-fnos.sh   运行时自测
docs/                   验证记录、用例、缺陷台账、复核报告
tests/qa-harness/       沙箱测试执行器与日志
```

## 十、上游与许可

- **上游**：openp2p —— https://github.com/openp2p-cn/openp2p （MIT）
- **本封装**：MIT（见 `LICENSE`）
- **随仓库分发的四个可执行文件**：上游 v3.25.11 官方发布物，**逐字节未修改**，
  出处与哈希见 [`NOTICE`](NOTICE)；可用 `./tools/fetch-upstream.sh --verify` 复算
- 「openp2p」与「飞牛 / fnOS」相关名称、标识归各自权利人所有；本仓库与上游无隶属关系
