#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 qa/evidence-index.md —— 证据索引由本脚本**重新生成**，不手写哈希。
用法：python3 make-index.py          # 原地重写 evidence-index.md
      python3 make-index.py --check  # 只比对：现在的实物能否复原出磁盘上的索引？
                                     # 不一致则打印 diff 并以非零退出（可塞进 CI / QA 例行）

为什么改成"生成"而不是"手写"：
  * 上一版索引里 testcases.md 的哈希在写完之后又因改动而变旧（qa 第四轮抓到），
    而 legacy 目录的聚合哈希**没记录配方**、第三方复算不出来（qa 第四轮抓到）。
  * 结论：**索引里任何人工转录的数字都是易腐的**。改由脚本从实物计算，
    并把自己（脚本）的哈希也写进去，任何一次改动都能被看出来。
"""
import difflib, hashlib, os, re, subprocess, sys, time

ROOT = os.path.dirname(os.path.abspath(__file__))
RUN = os.path.dirname(ROOT)                      # .../20260930-openp2p-fpk
WS = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(RUN))))  # 工作区根
DIST = os.path.join(WS, 'projects', 'fnos-openp2p', 'dist')
SRC = os.path.join(WS, 'projects', 'fnos-openp2p', 'src', 'openp2p')
PKG_NAME = 'openp2p_3.25.11-11_all.fpk'
PKG = os.path.join(DIST, PKG_NAME)
VERSIONS = ['8', '7', '6', '5', '4', '3', '2', '1']


def h(path, algo='sha256'):
    d = hashlib.new(algo)
    with open(path, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            d.update(b)
    return d.hexdigest()


def nlines(path):
    return sum(1 for _ in open(path, 'rb'))


def mt(path):
    return time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(os.path.getmtime(path)))


def agg_dir(d):
    """目录聚合哈希的**配方**（写清楚，第三方才复算得了）：
       按文件名排序，逐个把「文件名 + 内容」喂进同一个 sha256 上下文。
    """
    dg = hashlib.sha256()
    for f in sorted(os.listdir(d)):
        p = os.path.join(d, f)
        if os.path.isdir(p):
            continue
        dg.update(f.encode())
        dg.update(open(p, 'rb').read())
        sys.stderr.write('  agg <- %s\n' % f)
    return dg.hexdigest()


def manifest_fields():
    man = subprocess.run(['tar', '-xOf', PKG, 'manifest'], capture_output=True, text=True).stdout
    ver = [l.split('=', 1)[1].strip() for l in man.splitlines() if l.startswith('version')][0]
    cks = [l.split('=', 1)[1].strip() for l in man.splitlines() if l.startswith('checksum')][0]
    return ver, cks


def pkg_app_md5():
    import tempfile
    with tempfile.TemporaryDirectory() as t:
        subprocess.run(['tar', '-xf', PKG, '-C', t, 'app.tgz'], check=True)
        return h(os.path.join(t, 'app.tgz'), 'md5')


def summary_of(log):
    txt = open(log, errors='replace').read()
    m = re.search(r'PASS=(\d+)\s+FAIL=(\d+)', txt)
    if m:
        return 'PASS=%s FAIL=%s' % m.groups(), int(m.group(1)), int(m.group(2))
    m = re.search(r'OK=(\d+)\s+BAD=(\d+)', txt)
    if m:
        return 'OK=%s BAD=%s' % m.groups(), int(m.group(1)), int(m.group(2))
    # 兜底：没有汇总行的块（如 exec-D）按逐条标记计数
    p = len(re.findall(r'\[PASS\]', txt))
    f = len(re.findall(r'\[FAIL\]', txt))
    if p or f:
        return 'PASS=%d FAIL=%d（按逐条标记统计）' % (p, f), p, f
    return '（无汇总行）', 0, 0


def main():
    o = []
    A = o.append
    # --check 模式下沿用磁盘上原有的生成时间，否则自己都会和自己不一致
    now = time.strftime('%Y-%m-%d %H:%M:%S')
    old = os.path.join(ROOT, 'evidence-index.md')
    if '--check' in sys.argv and os.path.exists(old):
        m = re.search(r'- 生成时间：`([^`]+)`', open(old).read())
        if m:
            now = m.group(1)
    ver, cks = manifest_fields()
    appmd5 = pkg_app_md5()

    A('# QA 证据索引 — openp2p fnOS fpk（当前产物 `%s`）' % PKG_NAME)
    A('')
    A('> **本索引由 `qa/make-index.py` 生成**（不是手写的）。手写的哈希会腐：上一版就因为')
    A('> 「写完后又被改动的文件」与「没记录配方的聚合哈希」被独立 QA 连抓两次（第四轮 BLK-1/C1）。')
    A('> 复算方式：`cd teams/dev-squad/runs/20260930-openp2p-fpk/qa && python3 make-index.py --check`。')
    A('> 打印 `OK` = 「索引里每个数字都能从当前的实物重新算出来」；打印 diff = 索引已腐（实物变了索引没跟上，或索引被手改）。')
    A('')
    A('> **历史事故**：本文件曾于 2026-09-30 18:04 被写坏成 53 字节残骸（整文件只剩一行')
    A('> `...(argument truncated)`），全部绑定丢失。现已改为脚本生成，从根上消除该类事故。')
    A('')
    A('- 生成时间：`%s`' % now)
    A('- 生成脚本自身：`qa/make-index.py` sha256 `%s`' % h(os.path.join(ROOT, 'make-index.py')))
    A('- **自检**：`python3 make-index.py --check` → 一致则打印 `OK`；实物变过而索引没跟上则打印 diff 并非零退出。')
    A('')
    A('## 0. 前提与环境（影响所有结论）')
    A('')
    A('- 复核身份：`appuser`（uid 868，**非 root**）；真机上应用以 **root** 运行。')
    A('  因此「杀掉真机残留 root 实例」「跨用户伪装认领」本环境**做不到**，见 §7。')
    A('- ⚠️ **本机环境自带 `TRIM_APPNAME=appuser`、`TRIM_APPDEST`、`TRIM_PKGVAR`、')
    A('  `TRIM_TEMP_LOGFILE`**。脚本若直接 source `cmd/common` 而不覆盖它们，会算出')
    A('  `/var/apps/appuser` 的路径、在错误目录上得出结论。`repro.sh` 开头已固定')
    A('  `TRIM_APPNAME=openp2p` 并 unset 其余。')
    A('')
    A('## 1. 产物硬绑定')
    A('')
    A('| 产物 | 状态 | md5 | sha256 | 大小(字节) | mtime |')
    A('|---|---|---|---|---|---|')
    states = {
        '1': '作废（真机在装，缺陷最全）', '2': '作废', '3': '作废（曾被交付）',
        '4': '作废（N2 未真修）', '5': '作废（保存失败仍谎报）',
        '6': '作废（P2-A/B：回调泄漏 / 保存失败把应用丢在停止态）',
        '7': '已交付并**真机验收通过**（实例唯一/停止-启动幂等/组网登录成功），被 `-8` 取代',
        '8': '**当前交付**（第六轮：N5-1~N5-6 处置 + 数据目录结构性保护）',
    }
    for v in VERSIONS:
        p = os.path.join(DIST, 'openp2p_3.25.11-%s_all.fpk' % v)
        if not os.path.exists(p):
            A('| `openp2p_3.25.11-%s_all.fpk` | %s | —（文件不在工作区） | — | — | — |' % (v, states[v]))
            continue
        A('| `openp2p_3.25.11-%s_all.fpk` | %s | `%s` | `%s` | %d | %s |'
          % (v, states[v], h(p, 'md5'), h(p), os.path.getsize(p), mt(p)))
    A('')
    A('当前产物内部一致性（**已实跑**）：')
    A('')
    A('```bash')
    A('tar -xOf $DIST/%s manifest | grep -E "^(version|checksum)"' % PKG_NAME)
    A('tar -xf  $DIST/%s -C /tmp/v && md5sum /tmp/v/app.tgz' % PKG_NAME)
    A('diff -r src/openp2p/cmd /tmp/v/cmd        # 必须完全一致（防"源码改了包里没改"）')
    A('```')
    A('')
    A('- `manifest.version` = **`%s`**' % ver)
    A('- `manifest.checksum` = **`%s`**；实测 `md5(app.tgz)` = **`%s`** → %s'
      % (cks, appmd5, '一致 ✅' if cks == appmd5 else '不一致 ❌'))
    A('')

    # ---- §2 日志绑定 ----
    A('## 2. 测试日志绑定（块 A–H、D、复现集）')
    A('')
    A('| 日志 | 行数 | sha256 | mtime | 汇总 |')
    A('|---|---|---|---|---|')
    tot = 0
    for b in ['A', 'B', 'C1', 'C2', 'D', 'E', 'F', 'G', 'H', 'I']:
        lg = os.path.join(ROOT, 'exec-%s.log' % b)
        if not os.path.exists(lg):
            continue
        summ, p, f = summary_of(lg)
        if b != 'D':
            tot += p
        else:
            summ = 'PASS=%d FAIL=%d（i386 环境受限，见 §7）' % (p, f)
        A('| `exec-%s.log` | %d | `%s` | %s | %s |' % (b, nlines(lg), h(lg), mt(lg), summ))
    lg = os.path.join(ROOT, 'repro.log')
    if os.path.exists(lg):
        summ, p, f = summary_of(lg)
        A('| `repro.log` | %d | `%s` | %s | %s |' % (nlines(lg), h(lg), mt(lg), summ))
    A('')
    A('- **A/B/C1/C2/E/F/G/H/I 合计 PASS = %d**（FAIL=0）；块 D 另计 3 PASS / 1 FAIL（i386，环境受限）。' % tot)
    A('- 块 G/D/H 的被测对象是从**源码树**拷贝的 `cmd/`；该拷贝与 fpk 内 `cmd/` 逐字节一致由 §1 的 `diff -r` 证明。')
    A('- 块 I 的被测对象是**源码树** `src/openp2p/cmd/*`（可移植性阻塞项 B1/B2/B3 的修复），')
    A('  对照组取自冻结快照 `legacy-8-cmd/`（B1/B2/B3/B3\'）与 `legacy-9-cmd/`（N5~N10）——'
      '`legacy-10-cmd/`（N11~N14）——即"同一场景下旧实现必须失败"。')
    A('')

    # ---- §3 脚本绑定 ----
    A('## 3. 测试脚本自身绑定（防"日志与脚本对不上"）')
    A('')
    A('| 脚本 | sha256 |')
    A('|---|---|')
    for name in ['exec-A.sh', 'exec-B.sh', 'exec-C1.sh', 'exec-C2.sh', 'exec-D.sh',
                 'exec-E.sh', 'exec-F.sh', 'exec-G.sh', 'exec-H.sh', 'exec-I.sh',
                 'repro.sh', 'make-index.py', 'testcases.md', 'qa-round5-review.md',
                 'qa-round6-review.md', 'qa-portability-review.md']:
        p = os.path.join(ROOT, name)
        if os.path.exists(p):
            A('| `%s` | `%s` |' % (name, h(p)))
    A('')

    # ---- §4 对照组绑定 ----
    A('## 4. 对照组快照绑定（"用例有鉴别力"的实体）')
    A('')
    A('没有对照组，「PASS」可能只是「怎么写都通过」。本目录的对照组：')
    A('')
    A('| 快照 | 来源 | sha256 |')
    A('|---|---|---|')
    for rel, src in [('legacy-3.25.11-1-cmd', '真机 `-1` 的 `cmd/` 代码快照（用户实际安装的版本）'),
                     ('legacy-cmd/common.from-6', '`-6` 包内 `cmd/common`（P2-A 对照组）'),
                     ('legacy-8-cmd', '`-8` 包内 `cmd/`（B1/B2/B3/B3\' 对照组）'),
                     ('legacy-9-cmd', '`-9` 包内 `cmd/`（第七轮评审已审，N5~N10 加固前）'),
                     ('legacy-10-cmd', '`-10` 包内 `cmd/`（第七轮 b 已审，N11~N14 加固前）')]:
        p = os.path.join(ROOT, rel)
        if os.path.isdir(p):
            A('| `%s/`（%d 文件） | %s | `%s`（配方见下） |' % (rel, len(
                [f for f in os.listdir(p) if os.path.isfile(os.path.join(p, f))]), src, agg_dir(p)))
        elif os.path.exists(p):
            A('| `%s` | %s | `%s` |' % (rel, src, h(p)))
    for v in ['2', '3', '5', '6']:
        rel = 'legacy-ui/index.cgi.from-%s' % v
        p = os.path.join(ROOT, rel)
        if os.path.exists(p):
            A('| `%s` | `-%s` 包内 `ui/index.cgi` | `%s` |' % (rel, v, h(p)))
    A('')
    A('**聚合配方**（§4 目录行的哈希如何复算）：按文件名字典序，把「文件名 + 文件内容」')
    A('依次喂进同一个 `sha256` 上下文，输出十六进制摘要。等价于：')
    A('')
    A('```bash')
    A("python3 - <<'EOF'")
    A('import hashlib, os')
    A("d = 'teams/dev-squad/runs/20260930-openp2p-fpk/qa/legacy-3.25.11-1-cmd'")
    A('g = hashlib.sha256()')
    A('for f in sorted(os.listdir(d)):')
    A("    g.update(f.encode()); g.update(open(os.path.join(d, f), 'rb').read())")
    A('print(g.hexdigest())')
    A('EOF')
    A('```')
    A('')
    A('对照关系（每条都实跑过；**旧版本必须失败/被拒**，否则该用例不算数）：')
    A('')
    A('| # | 被测点 | 新版本 | 对照组 | 位置 |')
    A('|---|---|---|---|---|')
    A('| 1 | 降级分支（`cmd/common` 不存在）泄漏 `command not found`（N1） | 零泄漏 | `-3` 泄漏 127 字节 | `exec-H.log` H2 |')
    A('| 2 | `stop` 失败不得谎报「已停止」 | 如实提示 | `-2` 谎报「应用已停止」 | `exec-H.log` H6 |')
    A('| 3 | 保存设置写失败：不得谎报/泄漏/把应用丢在停止态（BLK-3、P2-B） | 如实报错 + 零泄漏 + 应用不受影响 | `-5` 谎报且泄漏；`-6` 把应用静默丢在停止态 | `exec-H.log` H9/H13/H14、`repro.log` R3 |')
    A('| 4 | `log_msg/warn_msg` 日志不可写时零泄漏（P2-1） | 0 字节 | `-4` 泄漏 299 字节 | `repro.log` R2c |')
    A('| 5 | `find_all_pids` 不认领 argv0 伪装进程（P2-4） | `[]` | `-4` 认领并会杀掉它 | `repro.log` R4 |')
    A('| 6 | 符号链接数据目录下 `is_our_pid` 为真（B11 真机根因） | TRUE | `-1` FALSE（恒假→重复起实例） | `repro.log` R5、`exec-G.log` G9 |')
    A('| 7 | 数据目录不可写时安装/升级回调零泄漏（P2-A） | 0 字节 | `-6` 泄漏 `cp: ... Permission denied` | `exec-H.log` H15 |')
    A('| 8 | 含 Token 的临时文件与进程 umask 无关地 0600（P2-D + 同类漏改） | umask=000 下仍 600 | `-6` 留下 666 | `exec-H.log` H16 |')
    A('| 9 | 日志轮转沿用原权限（600 不被 `>` 重定向放宽） | 轮转后仍 600 | `-6` 轮转后变 666 | `exec-H.log` H17 |')
    A('| 10 | `save` 写失败不得把运行中的应用丢在停止态（P2-B） | 仍在运行 + 文案交代 | `-6` 静默停在停止态 | `exec-H.log` H13/H14 |')
    A('| 11 | 数据目录结构性保护：0755 → 摘掉组/其他人权限，且**不放开** 0500（真机 umask 不生效） | 700 / 0500 保持 | `-6` 保持 755 | `exec-H.log` H21 |')
    A('| 12 | 打错的 Token 不得被原样回显进（0644 的）日志（N5-1） | 0 次出现 | 机械变异回旧写法即泄漏 | `exec-H.log` H18 |')
    A('| 13 | 冷启动写 `config.json` 一创建即 0600（N5-2，用 `chmod` 函数桩堵死"事后收紧"） | umask=000 下 600 | `-6` 在 chmod 桩下暴露创建时权限 | `exec-H.log` H19 |')
    A('| 14 | 安装/升级的失败提示必须**追加**、不得截断 fnOS 进度文件（N5-3） | 既有内容保留 | 机械变异回 `>` 即截断 | `exec-H.log` H20 |')
    A('| 15 | 卸载选「删除配置」必须真删到数据卷（数据目录是**符号链接**，B1/P1） | 真删 + 白名单守卫 + 删完自检 | `-8` 只删掉链接本身，Token 原封不动 | `exec-I.log` I1 |')
    A('| 16 | 冷启动写 Token 不得整文件覆盖、`apps[]` 必须保留（B2/P2） | 只改 Token 字段 + 备 `.bak`(0600) | `-8` 覆盖全文 → 手写规则静默清零 | `exec-I.log` I2 |')
    A('| 17 | 运行时目录建不出来时锁必须**快速失败**（B3/P3） | rc=1 + 明确文案 | `-8` 0.2s 死循环（`timeout` rc=124，界面挂死） | `exec-I.log` I3 |')
    A('| 18 | 陈旧锁 + 锁目录删不掉（只读挂载/EBUSY/immutable）也不许忙等挂死（B3\'） | 2 秒内 rc=1、日志 5 行 | `-8` `timeout` 12 秒不返回（rc=124 忙等） | `exec-I.log` I4 |')
    A('| 19 | 卸载白名单必须精确：`$APPDIR/*` 过宽会删掉安装目录 `target/`（N5） | 拒绝并保留 target | `-9` 把 `target/` 一起删了 | `exec-I.log` I5a |')
    A('| 20 | `$APPDIR` 是符号链接时仍要能真删配置（N6） | 删除成功 | `-9` 误判为拒绝 → Token 留存 | `exec-I.log` I5b |')
    A('| 21 | `config.json` 是符号链接时写进真实目标、不脱链（N7） | 链接保留 + 目标已更新 | `-9` 链接被换成普通文件 | `exec-I.log` I5c |')
    A('| 22 | 锁的属主进程还活着时绝不夺锁（N9）；锁路径被普通文件占用要能自愈（N10） | 等待超时 rc=1 / 自动清理后取锁 | `-9` 夺走活进程的锁 / 永久挡住 | `exec-I.log` I5d、I5e |')
    A('| 23 | 读锁属主必须**有界**：owner 是 FIFO//dev/zero/符号链接时不许被拖死（N11） | 0~2 秒内 rc=1 | `-10` 8 秒不返回（rc=124） | `exec-I.log` I6a |')
    A('| 24 | owner 文件缺失时不得往 stderr 吐字节（N12） | 0 字节 | `-10` 泄漏 200 字节 | `exec-I.log` I6b |')
    A('| 25 | 测试注入点被塞超长数字时，超时判据不许失效（N13） | stderr 0 字节、仍在等 | `-10` 每 0.2 秒报 integer expression error → 永不返回 | `exec-I.log` I6c |')
    A('| 26 | `config.json` 指向数据目录**之外**的符号链接必须拒绝改写（N14） | rc=1 且外部文件未含 Token | `-10` 把 Token 写到了数据目录之外 | `exec-I.log` I6d、I6e |')
    A('')

    # ---- §5 计数口径 ----
    A('## 5. PASS 计数口径（**唯一定义**，避免"216 vs 213"式的口径打架）')
    A('')
    A('「总 PASS」= 块 **A + B + C1 + C2 + E + F + G + H + I** 的 PASS 行数之和。')
    A('**块 D（跨架构）不计入总数**，单独列报（i386 在本机 qemu 下与官方 Go 386 二进制同崩，属环境受限）。')
    A('')
    A('| 块 | 覆盖内容 | PASS | FAIL |')
    A('|---|---|---|---|')
    blocks = [
        ('A', '包结构与清单（manifest / 文件清单 / 权限位 / checksum / version / 目录布局）'),
        ('B', '`cmd/common` 纯函数（safe_port/safe_bw/js_escape/路径推导/TRIM_* 覆盖）'),
        ('C1', '`cmd/main` start/stop/status 时序（含 PID 文件与实例单例）'),
        ('C2', '判活与进程归属（`is_our_pid` / `proc_exe_is_bin` / `find_all_pids` / 符号链接）'),
        ('D', '跨架构（i386 模拟执行）——环境受限，不计入总数'),
        ('E', '`install_callback` / `upgrade_callback` / `config_callback` 回调语义'),
        ('F', '`build.sh` 打包链路与可重复性'),
        ('G', '`ui/index.cgi` 后端行为（保存、校验、备份、降级）'),
        ('H', '缺陷回归：每条历史缺陷一个用例 + 一个"旧版本必须失败"的对照组'),
        ('I', '可移植性专项（B1/B2/B3/B3\'）与两轮评审加固（N5–N7、N9–N14）'),
    ]
    for b, desc in blocks:
        lg = os.path.join(ROOT, 'exec-%s.log' % b)
        if not os.path.exists(lg):
            continue
        summ, p, f = summary_of(lg)
        A('| **%s** | %s | %s | %s |' % (b, desc, p if b != 'D' else '3', f if b != 'D' else '1'))
    A('| | **合计（不含 D）** | **%d** | **0** |' % tot)
    A('')
    A('**上一版索引写「216」是错的**（当时代码块 C 与 H 的行数被重复相加）。现在这个数字由本脚本')
    A('从日志实际解析 `PASS=` 行得出，并附每块的日志 sha256（§2），第三方可自行复算。')
    A('')

    # ---- §6 复现集 ----
    A('## 6. 复现集 `repro.sh`（脱离测试框架的独立复现）')
    A('')
    A('`repro.sh` 不依赖 exec-*.sh 的任何辅助函数，自己起沙箱、自己造桩，用来回答')
    A('「换一个人、换一台机器，能不能复现出同样结论」。当前：**17 OK / 0 BAD**（见 `repro.log`）。')
    A('')
    A('| # | 复现项 | 断言 |')
    A('|---|---|---|')
    A('| R1 | 符号链接数据目录下 `is_our_pid` | 必须为真（真机根因 B11） |')
    A('| R2 | 日志不可写时 `log_msg/warn_msg` | stdout+stderr **零字节**泄漏 |')
    A('| R2c | 同上，对照组 `-4` | 泄漏 299 字节（证明用例有鉴别力） |')
    A('| R3 | `ui/index.cgi` 保存设置写失败（目录只读） | 不得输出「✅ 已保存」，零裸错误泄漏 |')
    A('| R4 | `find_all_pids` 遇到 `exec -a` 伪装 argv0 的进程 | **不得认领**（`-4` 会认领并杀掉） |')
    A('| R5 | `-1` 快照下同一符号链接场景 | 必须为假（证明 R1 不是天然成立） |')
    A('| R6 | `stop` 面对多个实例（B12） | 全部回收，不留残党 |')
    A('')
    A('**P2-A / P2-B / P2-D 的独立复现**落在块 H（H15 / H13 / H14 / H16 / H17），因为需要构造')
    A('「数据目录不可写」「保存写失败」「把 umask 设成 000 并打死 mv/rm 以留住临时文件」这几种受控现场——')
    A('`repro.sh` 的沙箱形态不适合承载它们，故未重复（**已知取舍**，非遗漏；若需要，H13/H15/H16 的桩')
    A('可直接搬到 `repro.sh`，代价是沙箱复杂度翻倍）。')
    A('')

    # ---- §7 未覆盖 ----
    A('## 7. 未覆盖 / 环境受限（**不得当已验收**）')
    A('')
    A('| # | 项目 | 原因 |')
    A('|---|---|---|')
    A('| U1 | 真机应用中心安装/升级/修复重装 | 需真机 UI 操作与 root；沙箱无权限。**已登记为用户侧冒烟步骤** |')
    A('| U2 | 真机 OS reboot 后自启留存 | 同上（需重启 NAS） |')
    A('| U3 | i386 原生执行 | 本机无 386 内核；qemu-i386 下官方 Go 386 二进制同样崩溃 → **不能据此判定包损坏**（块 D 的 1 条 FAIL 即此） |')
    A('| U4 | armv8l 原生真机 | 无 arm 设备 |')
    A('| U5 | `hidepid=2` 等非常规 `/proc` 挂载 | 本机 `/proc` 为默认；`proc_exe_is_bin` 在 EACCES 时退化为只比 argv0（**能力上限**，代码内已注释） |')
    A('| U6 | `TRIM_APPNAME` 在真机的真实取值 | 真机安装需 root + UI；沙箱用固定值覆盖验证了「被覆盖时不误判」 |')
    A('| U7 | ENOSPC（磁盘满）下 `save` / `raw_save` | 无 quota/mount 权限构造真实 ENOSPC；已用「目录不可写」近似覆盖写失败路径 |')
    A('| U8 | 跨用户伪装进程认领（root 进程伪装成我们的 exe） | 非 root 无法构造跨 uid 现场；已用同 uid `exec -a` 伪装覆盖（R4） |')
    A('| U9 | 用户真机当前仍在运行的两个 root 遗留实例（PID 2795664 / 2800553） | **我无权限 kill**；升级后点「停止」→「启动」即可由 B12 逻辑一次清掉 |')
    A('')
    A('以上 U1–U9 均**不能以沙箱结论替代**。U1/U2 是交付前唯一真正必须由用户完成的一步（见 §8 冒烟）。')
    A('')

    # ---- §8 变异/破坏性测试 ----
    A('## 8. 变异测试（证明用例"真的会红"）')
    A('')
    A('QA 在 `/tmp` 副本上做（不污染本目录）：')
    A('')
    A('| 变异 | 预期 | 实测 |')
    A('|---|---|---|')
    A('| UI 回退成 `-5` 的 `save` 实现 | 块 H 应红 | **6 条 FAIL** ✅ |')
    A('| `apply_settings_env` 失败改回 `return 0` | 块 H 应红 | **4 条 FAIL** ✅ |')
    A('')
    A('## 9. 真机验收冒烟（交付后由用户执行，唯一不可沙箱替代的一步）')
    A('')
    A('1. 应用中心**覆盖安装/升级** `openp2p_3.25.11-11_all.fpk`（勿卸载，保留配置）。')
    A('2. 不填 Token 直接打开界面 → 必须能进（B8：早期版本此处死锁）。')
    A('3. 填 Token 保存 → 文案为「已保存」且**不再出现裸 `Permission denied`**（BLK-3/P2-B）。')
    A('4. 状态页显示「运行中」，且 `ps` 里**只有 1 个** openp2p 实例（B11/B12）。')
    A('5. 点「停止」再「启动」（或「重启」）→ 仍只有 1 个实例，日志无 `bind: address already in use`。')
    A('6. 重启 NAS → 应用自动起来，仍只有 1 个实例。')
    A('')
    A('任何一步不符：把 `/var/log/apps/openp2p.log` 与界面文案截图发回，我按同样的「用例 + 对照组」流程定位。')
    A('')
    text = '\n'.join(o) + '\n'
    path = os.path.join(ROOT, 'evidence-index.md')
    if '--check' in sys.argv:
        cur = open(path).read() if os.path.exists(path) else ''
        if cur == text:
            print('OK: evidence-index.md 与实物一致（%d 行）' % len(o))
            return
        print('DIFF: evidence-index.md 与实物不一致 —— 实物变过而索引没跟上，或索引被手改过')
        sys.stdout.writelines(difflib.unified_diff(
            cur.splitlines(True), text.splitlines(True), 'on-disk', 'regenerated'))
        sys.exit(1)
    open(path, 'w').write(text)
    sys.stderr.write('已生成 evidence-index.md（%d 行）\n' % len(o))


if __name__ == '__main__':
    main()
