#!/bin/bash
# openp2p fnOS 应用界面（CGI）
# 通过 fnOS 网关访问：/cgi/ThirdParty/openp2p/index.cgi/
# 功能：状态总览 / 可视化配置 / 启动停止重启 / 高级 config.json 编辑 / 日志查看

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
HAVE_COMMON="yes"
if [ -f "/var/apps/openp2p/cmd/common" ]; then
    # shellcheck source=/dev/null
    . "/var/apps/openp2p/cmd/common"
else
    HAVE_COMMON="no"
    APPDIR="/var/apps/openp2p"
    APPDEST="${TRIM_APPDEST:-${APPDIR}/target}"
    PKGVAR="${TRIM_PKGVAR:-${APPDIR}/var}"
    DATA_DIR="${APPDIR}/shares/openp2p"
    CONF="${DATA_DIR}/config.json"
    SETTINGS="${DATA_DIR}/settings.conf"
    # 降级分支没有 cmd/common，DEFAULT_* 也得自己补：漏了不会崩（本分支无 set -u），
    # 但状态卡会渲染成「服务端 :」（空主机 + 空端口）—— 纯显示缺陷，qa 第四轮指出。
    DEFAULT_SERVERHOST="api.openp2p.cn"
    DEFAULT_SERVERPORT="27183"
    PID_FILE="${PKGVAR}/app.pid"
    START_FILE="${PKGVAR}/start_time"
    BIN="${DATA_DIR}/openp2p"
    LOG_FILE="/var/log/apps/openp2p.log"
    log_msg() { :; }
    cfg_get() { echo ""; }
    # 降级分支：应用目录缺失（未安装/被删）时，公共函数全都不可用。
    # 这里必须把下面会用到的一并补齐，否则界面会冒出 "command not found"
    # 到 web 错误日志里（真被 qa 抓到过：只补 running_pid 是不够的，因为
    # 后面那段说明性重定义会把它覆盖掉，所以改用 HAVE_COMMON 标志判断）。
    safe_num()  { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }
    safe_port() { safe_num "$1" && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }
    safe_bw()   { safe_num "$1" && [ "$1" -le 100000 ]; }
    safe_node() { case "$1" in ''|*[!A-Za-z0-9_-]*) return 1 ;; *) [ ${#1} -le 31 ] ;; esac; }
    safe_host() { case "$1" in ''|*[!A-Za-z0-9.-]*) return 1 ;; *) return 0 ;; esac; }
fi

MAIN_SCRIPT="/var/apps/openp2p/cmd/main"

# ---------- 工具 ----------
h() { printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'; }

urldecode() {
    local s="${1//+/ }"
    printf '%b' "${s//%/\\x}"
}

get_field() {
    local key="$1" body="$2" out
    out=$(printf '%s' "$body" | tr '&' '\n' | sed -n "s/^${key}=//p" | head -n 1)
    urldecode "$out"
}

# 复用 cmd/common 的 is_running / find_pid，不再自己写一套判活逻辑。
# 旧实现有两个真机级缺陷：
#   1) 只用 kill -0 判活 → 跨用户（界面非 root、openp2p 以 root 跑）时 EPERM
#      被判成"已死"，界面显示"已停止"而进程其实活着；
#   2) 兜底用 pidof openp2p 且不校验 exe → 可能认领另一份安装的 openp2p。
# is_running 会顺带把丢失的 PID 文件修复回来。
running_pid() {
    local p
    [ "$HAVE_COMMON" = "yes" ] || return 1      # 没装应用 / 公共函数不可用
    is_running || return 1
    p=$(head -n 1 "$PID_FILE" 2>/dev/null | tr -d '[:space:]')
    [ -n "$p" ] || p=$(find_pid)
    [ -n "$p" ] || return 1
    echo "$p"
}

uptime_text() {
    [ -f "$START_FILE" ] || { echo ""; return; }
    local st now diff d t
    st=$(cat "$START_FILE" 2>/dev/null)
    case "$st" in ''|*[!0-9]*) echo ""; return ;; esac
    now=$(date +%s)
    diff=$(( now - st ))
    [ "$diff" -lt 0 ] && diff=0
    d=$(( diff / 86400 ))
    t=$(date -u -d "@${diff}" +%H:%M:%S 2>/dev/null)
    if [ "$d" -gt 0 ]; then echo "${d}天 ${t}"; else echo "$t"; fi
}

mask_token() {
    local t="$1"
    [ -z "$t" ] && { echo "（未配置）"; return; }
    local len=${#t}
    if [ "$len" -le 4 ]; then echo "****"; else echo "${t:0:2}****${t:$((len-2))}"; fi
}

# ---------- 读取 POST ----------
POST_DATA=""
CONTENT_LENGTH="${CONTENT_LENGTH:-0}"
case "$CONTENT_LENGTH" in ''|*[!0-9]*) CONTENT_LENGTH=0 ;; esac
if [ "$CONTENT_LENGTH" -gt 0 ]; then
    POST_DATA=$(head -c "$CONTENT_LENGTH" 2>/dev/null)
fi

ACTION=""
MSG=""
MSG_KIND="ok"
if [ -n "$POST_DATA" ]; then
    ACTION=$(get_field action "$POST_DATA")

    case "$ACTION" in
        save)
            t=$(get_field token "$POST_DATA" | tr -d '[:space:]')
            n=$(get_field node "$POST_DATA" | tr -d '[:space:]')
            sb=$(get_field sharebandwidth "$POST_DATA" | tr -d '[:space:]')
            sh=$(get_field serverhost "$POST_DATA" | tr -d '[:space:]')
            sp=$(get_field serverport "$POST_DATA" | tr -d '[:space:]')
            ll=$(get_field loglevel "$POST_DATA" | tr -d '[:space:]')

            err=""
            [ -n "$t" ]  && ! safe_num  "$t"  && err="Token 只能是数字"
            [ -z "$err" ] && [ -n "$n" ]  && ! safe_node "$n"  && err="节点名只能包含字母/数字/-/_，且 1-31 位"
            # 校验范围与后端 cmd/common 的 safe_bw / safe_port 保持一致，
            # 否则界面会"接受"一个后端即将静默回退的值 —— 用户看到的值 ≠ 生效的值。
            [ -z "$err" ] && [ -n "$sb" ] && ! safe_bw   "$sb" && err="共享带宽必须是 0-100000 的整数"
            [ -z "$err" ] && [ -n "$sh" ] && ! safe_host "$sh" && err="服务端地址格式不正确"
            [ -z "$err" ] && [ -n "$sp" ] && ! safe_port "$sp" && err="服务端端口必须是 1-65535"
            [ -z "$err" ] && [ -n "$ll" ] && case "$ll" in 0|1|2|3) ;; *) err="日志级别只能是 0/1/2/3" ;; esac

            if [ -n "$err" ]; then
                MSG="❌ ${err}"; MSG_KIND="err"
            else
                mkdir -p "$DATA_DIR" 2>/dev/null
                was_running="no"; running_pid >/dev/null 2>&1 && was_running="yes"

                cur_t=$(cfg_get token); cur_n=$(cfg_get node); cur_sb=$(cfg_get sharebandwidth)
                cur_sh=$(cfg_get serverhost); cur_sp=$(cfg_get serverport); cur_ll=$(cfg_get loglevel)
                [ -n "$t" ]  || t="$cur_t"
                [ -n "$n" ]  || n="$cur_n"
                [ -n "$sb" ] || sb="$cur_sb"
                [ -n "$sh" ] || sh="$cur_sh"
                [ -n "$sp" ] || sp="$cur_sp"
                [ -n "$ll" ] || ll="$cur_ll"
                [ -n "$n" ]  || n=$(hostname 2>/dev/null | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9-' | cut -c1-31)
                [ -n "$n" ]  || n="fnos-nas"
                [ -n "$sb" ] || sb=10
                [ -n "$sh" ] || sh="$DEFAULT_SERVERHOST"
                [ -n "$sp" ] || sp="$DEFAULT_SERVERPORT"
                [ -n "$ll" ] || ll=1

                # 写文件必须：先写临时文件 → 校验非空 → 原子改名，并对失败**如实回报**。
                # 旧写法 `cat > "$SETTINGS" <<EOF` 有两个问题（qa 第四轮实跑抓到）：
                #   1) 目录不可写时，bash 把裸 "Permission denied" 打到 CGI stderr（污染 web 错误日志）；
                #   2) 没有任何写后校验，界面却照喊「✅ 设置已保存」—— 用户以为存上了，实际 Token
                #      根本没落盘，接着表现为"填了 Token 还是不组网"，把人带偏。
                # 顺序同样重要（qa 第四轮指出 P2-B）：**先写盘、确认写好，再动正在运行的应用**。
                # 旧顺序是「先 stop → 再写」，写失败就把应用留在停止态、文案还不提，
                # 用户看到的是"点一下保存，应用莫名不跑了"。现在写失败就完全不碰应用。
                wrote="no"
                tmp="${SETTINGS}.tmp.$$"
                # 结构性保护（`-8`）：真机实测 **/vol4/@appshare 这棵树上进程 umask 不生效**，
                # 新文件直接继承父目录权限 —— 所以除 umask 077 外，还要把目录本身压到 0700，
                # 让"含 Token 的临时文件被他人读到"在结构上不可能发生。
                # 用 go-rwx 而非 700：只收紧、不放开（不推翻运维设的 0500）。
                mkdir -p "$DATA_DIR" 2>/dev/null
                chmod go-rwx "$DATA_DIR" 2>/dev/null
                # umask 077：settings.conf 含 Token，临时文件必须**一创建就是 0600**，
                # 不能等 mv 之后再 chmod（那会留下一个宽权限窗口）。
                if ( umask 077
                     printf '# openp2p 应用设置 —— 由 fnOS 应用界面维护，也可手动编辑后重启应用\n'
                     printf 'token=%s\nnode=%s\nsharebandwidth=%s\nserverhost=%s\nserverport=%s\nloglevel=%s\n' \
                            "$t" "$n" "$sb" "$sh" "$sp" "$ll"
                   ) 2>/dev/null > "$tmp" \
                   && [ -s "$tmp" ] \
                   && { mv -f "$tmp" "$SETTINGS"; } 2>/dev/null \
                   && [ -f "$SETTINGS" ]; then
                    wrote="yes"
                fi
                rm -f "$tmp" 2>/dev/null

                if [ "$wrote" != "yes" ]; then
                    # 文案按**实测状态**推导，不写死（qa 第五轮指出：写死"应用未被改动"
                    # 在当前控制流下成立，但一旦顺序再被改动就会变成谎话）。
                    if [ "$was_running" = "yes" ]; then
                        MSG="❌ 设置写入失败：${SETTINGS} 不可写（请检查存储空间与权限），本次设置未生效；应用未被改动（仍在运行）"
                    else
                        MSG="❌ 设置写入失败：${SETTINGS} 不可写（请检查存储空间与权限），本次设置未生效；应用未被改动（当前为停止状态）"
                    fi
                    MSG_KIND="err"
                    log_msg "❌ 界面保存设置失败：无法写入 ${SETTINGS}"
                else
                chmod 600 "$SETTINGS" 2>/dev/null
                log_msg "界面保存设置：node=$n server=$sh:$sp 带宽=$sb 日志级别=$ll"

                # 写盘已确认成功，这时才去动应用（需要重启来让新设置生效）
                stopped="yes"
                if [ "$was_running" = "yes" ]; then
                    bash "$MAIN_SCRIPT" stop >/dev/null 2>&1 || stopped="no"
                    running_pid >/dev/null 2>&1 && stopped="no"
                fi

                if [ "$was_running" = "yes" ]; then
                    if [ "$stopped" = "no" ]; then
                        MSG="⚠️ 设置已保存，但未能停止旧进程（可能权限不足），请到应用中心重启后生效"
                        MSG_KIND="warn"
                    else
                        bash "$MAIN_SCRIPT" start >/dev/null 2>&1
                        if running_pid >/dev/null 2>&1; then
                            MSG="✅ 设置已保存，应用已自动重启"
                        else
                            MSG="⚠️ 设置已保存，但应用未能启动，请查看下方日志"; MSG_KIND="warn"
                        fi
                    fi
                else
                    MSG="✅ 设置已保存（应用当前未运行）"
                fi
                fi
            fi
            ;;

        start)
            if bash "$MAIN_SCRIPT" start >/dev/null 2>&1; then
                if running_pid >/dev/null 2>&1; then
                    if [ -n "$(cfg_get token)" ]; then MSG="✅ 应用已启动"; else MSG="✅ 应用已启动（未填 Token，暂不组网）"; fi
                else
                    MSG="⚠️ 启动指令已执行，但未检测到进程，请查看下方日志"; MSG_KIND="warn"
                fi
            else
                MSG="❌ 启动失败，请查看下方日志"; MSG_KIND="err"
            fi
            ;;

        stop)
            if bash "$MAIN_SCRIPT" stop >/dev/null 2>&1 && ! running_pid >/dev/null 2>&1; then
                MSG="🛑 应用已停止"
            elif running_pid >/dev/null 2>&1; then
                MSG="⚠️ 未能停止：进程仍存活（可能权限不足），请到应用中心停止"; MSG_KIND="warn"
            else
                MSG="🛑 应用已停止（stop 返回非零，详见日志）"; MSG_KIND="warn"
            fi
            ;;

        restart)
            bash "$MAIN_SCRIPT" stop >/dev/null 2>&1
            if running_pid >/dev/null 2>&1; then
                MSG="⚠️ 未能停止旧进程（可能权限不足），请到应用中心重启"; MSG_KIND="warn"
            elif bash "$MAIN_SCRIPT" start >/dev/null 2>&1 && running_pid >/dev/null 2>&1; then
                MSG="✅ 应用已重启"
            else
                MSG="⚠️ 已停止，但未能启动，请查看下方日志"; MSG_KIND="warn"
            fi
            ;;

        raw_save)
            raw=$(get_field rawjson "$POST_DATA")
            if [ -z "$raw" ]; then
                MSG="❌ 内容为空，未保存"; MSG_KIND="err"
            else
                ok="yes"
                if command -v python3 >/dev/null 2>&1; then
                    printf '%s' "$raw" | python3 -c 'import json,sys; json.load(sys.stdin)' >/dev/null 2>&1 || ok="no"
                else
                    # 无 python3 时退化为括号配平检查
                    ob=$(printf '%s' "$raw" | tr -cd '{' | wc -c)
                    cb=$(printf '%s' "$raw" | tr -cd '}' | wc -c)
                    [ "$ob" = "$cb" ] || ok="no"
                fi
                if [ "$ok" != "yes" ]; then
                    MSG="❌ JSON 格式不合法，未保存（原文件未改动）"; MSG_KIND="err"
                else
                    mkdir -p "$DATA_DIR" 2>/dev/null
                    was_running="no"; running_pid >/dev/null 2>&1 && was_running="yes"
                    stopped="yes"
                    if [ "$was_running" = "yes" ]; then
                        bash "$MAIN_SCRIPT" stop >/dev/null 2>&1 || stopped="no"
                        running_pid >/dev/null 2>&1 && stopped="no"
                    fi
                    # 备份与写入都必须「做过才算数」：旧实现在 config.json 根本不存在时
                    # 也照喊「已备份旧文件」，且写失败仍报成功（qa 第四轮实跑抓到）。
                    # 这里逐个记录事实，再据实拼文案。
                    had_conf="no"; [ -f "$CONF" ] && had_conf="yes"
                    backed="no"
                    if [ "$had_conf" = "yes" ]; then
                        cp -f "$CONF" "${CONF}.bak" 2>/dev/null && [ -f "${CONF}.bak" ] && backed="yes"
                    fi
                    if [ "$backed" = "yes" ]; then
                        baknote="（旧文件已备份为 config.json.bak）"
                    elif [ "$had_conf" = "yes" ]; then
                        baknote="（⚠️ 备份失败，旧文件可能已丢失）"
                    else
                        baknote="（原文件不存在，无需备份）"
                    fi

                    wrote="no"
                    tmp="${CONF}.tmp.$$"
                    # umask 077：config.json 也含 Token，临时文件一创建就要 0600
                    # （同 save 分支：真机 umask 不生效，故再压一次目录权限兜底）
                    mkdir -p "$DATA_DIR" 2>/dev/null
                    chmod go-rwx "$DATA_DIR" 2>/dev/null
                    if ( umask 077; printf '%s\n' "$raw" > "$tmp" ) 2>/dev/null \
                       && [ -s "$tmp" ] \
                       && { mv -f "$tmp" "$CONF"; } 2>/dev/null \
                       && [ -f "$CONF" ]; then
                        wrote="yes"
                    fi
                    rm -f "$tmp" 2>/dev/null

                    if [ "$wrote" != "yes" ]; then
                        base="❌ config.json 写入失败：${CONF} 不可写（请检查存储空间与权限），原文件未改动"
                        MSG_KIND="err"
                        log_msg "❌ 界面保存 config.json 失败：无法写入 ${CONF}"
                        # config.json 是 openp2p 自己也会改写的文件，必须先停再写（否则会被覆盖）。
                        # 所以写失败时**必须把应用恢复运行**，否则用户会看到"点一下保存，应用就不跑了"。
                        if [ "$was_running" = "yes" ]; then
                            if [ "$stopped" = "no" ]; then
                                MSG="${base}；且旧进程未能停止（可能权限不足），请到应用中心重启"
                                MSG_KIND="warn"
                            else
                                bash "$MAIN_SCRIPT" start >/dev/null 2>&1
                                if running_pid >/dev/null 2>&1; then
                                    MSG="${base}；应用已恢复运行"
                                else
                                    MSG="${base}；且应用未能重新启动，请查看下方日志"
                                    MSG_KIND="warn"
                                fi
                            fi
                        else
                            MSG="$base"
                        fi
                    else
                    chmod 600 "$CONF" 2>/dev/null
                    log_msg "界面保存 config.json ${baknote}"
                    if [ "$was_running" = "no" ]; then
                        MSG="✅ config.json 已保存${baknote}"
                    elif [ "$stopped" = "no" ]; then
                        MSG="⚠️ config.json 已保存${baknote}，但未能停止旧进程（可能权限不足），请到应用中心重启后生效"
                        MSG_KIND="warn"
                    else
                        bash "$MAIN_SCRIPT" start >/dev/null 2>&1
                        if running_pid >/dev/null 2>&1; then
                            MSG="✅ config.json 已保存${baknote}，应用已重启"
                        else
                            MSG="⚠️ config.json 已保存${baknote}，但应用未能启动，请查看下方日志"; MSG_KIND="warn"
                        fi
                    fi
                    fi
                fi
            fi
            ;;
    esac
fi

# ---------- 采集展示数据 ----------
PID=""
if PID=$(running_pid); then RUNNING="yes"; else RUNNING="no"; PID=""; fi
UP=""
[ "$RUNNING" = "yes" ] && UP=$(uptime_text)
VER=$(bin_version 2>/dev/null)
[ -n "$VER" ] || VER="未知"

S_TOKEN=$(cfg_get token)
S_NODE=$(cfg_get node)
S_SB=$(cfg_get sharebandwidth)
S_SH=$(cfg_get serverhost)
S_SP=$(cfg_get serverport)
S_LL=$(cfg_get loglevel)
[ -n "$S_NODE" ] || S_NODE=$(hostname 2>/dev/null)
[ -n "$S_SB" ]   || S_SB=10
[ -n "$S_SH" ]   || S_SH="$DEFAULT_SERVERHOST"
[ -n "$S_SP" ]   || S_SP="$DEFAULT_SERVERPORT"
[ -n "$S_LL" ]   || S_LL=1

# 自定义 P2PApp（config.json 的 apps[]）
APPS_HTML=""
if [ -f "$CONF" ]; then
    APPS_HTML=$(sed -n '/"apps"/,$p' "$CONF" 2>/dev/null | grep -E '"(AppName|Protocol|SrcPort|PeerNode|DstPort|DstHost)"' \
        | sed 's/^[[:space:]]*//' | tr -d '",' | sed 's/: */: /' | head -60)
fi
if [ -z "$APPS_HTML" ]; then
    APPS_HTML="（暂无自定义端口转发。推荐直接在 console.openp2p.cn 里创建 P2PApp，会自动下发到本节点）"
fi

RAW_JSON=""
[ -f "$CONF" ] && RAW_JSON=$(cat "$CONF" 2>/dev/null)
[ -n "$RAW_JSON" ] || RAW_JSON=$(printf '{\n  "network": {\n    "Token": 0,\n    "Node": "%s"\n  },\n  "apps": null\n}' "$S_NODE")

LOG_TAIL=""
if [ -f "$LOG_FILE" ]; then
    LOG_TAIL=$(tail -n 80 "$LOG_FILE" 2>/dev/null)
fi
[ -n "$LOG_TAIL" ] || LOG_TAIL="（暂无日志。应用启动后日志会出现在这里）"

# ---------- 输出 ----------
echo "Content-Type: text/html; charset=UTF-8"
echo "Cache-Control: no-store"
echo ""

cat <<HTML
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>OpenP2P 内网穿透</title>
<style>
  *{box-sizing:border-box}
  body{margin:0;padding:20px;font-family:-apple-system,"PingFang SC","Microsoft YaHei",sans-serif;background:#f5f7fb;color:#1f2937}
  .wrap{max-width:1000px;margin:0 auto}
  h1{font-size:20px;margin:0 0 4px}
  .sub{color:#6b7280;font-size:13px;margin-bottom:16px}
  .card{background:#fff;border-radius:12px;padding:18px;margin-bottom:16px;box-shadow:0 2px 10px rgba(0,0,0,.06)}
  .card h2{font-size:15px;margin:0 0 12px;color:#374151}
  .badge{display:inline-block;padding:3px 10px;border-radius:999px;font-size:12px;font-weight:600}
  .on{background:#dcfce7;color:#166534}
  .off{background:#fee2e2;color:#991b1b}
  .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px}
  .kv{background:#f9fafb;border-radius:8px;padding:10px 12px}
  .kv .k{font-size:12px;color:#6b7280;margin-bottom:3px}
  .kv .v{font-size:14px;font-weight:600;word-break:break-all}
  label{display:block;font-size:13px;color:#374151;margin:10px 0 4px;font-weight:600}
  input[type=text],textarea{width:100%;padding:9px 11px;border:1px solid #d1d5db;border-radius:8px;font-size:14px;font-family:inherit;background:#fff}
  input[type=text]:focus,textarea:focus{outline:none;border-color:#3b82f6;box-shadow:0 0 0 3px rgba(59,130,246,.15)}
  .hint{font-size:12px;color:#9ca3af;margin-top:3px}
  .row{display:grid;grid-template-columns:1fr 1fr;gap:14px}
  @media(max-width:640px){.row{grid-template-columns:1fr}}
  .btns{margin-top:16px;display:flex;gap:10px;flex-wrap:wrap}
  button{padding:9px 18px;border:0;border-radius:8px;font-size:14px;font-weight:600;cursor:pointer}
  .b1{background:#3b82f6;color:#fff}
  .b2{background:#ef4444;color:#fff}
  .b3{background:#10b981;color:#fff}
  .b4{background:#e5e7eb;color:#374151}
  button:hover{opacity:.9}
  .msg{padding:11px 14px;border-radius:8px;margin-bottom:14px;font-size:14px}
  .msg.ok{background:#dcfce7;color:#166534}
  .msg.err{background:#fee2e2;color:#991b1b}
  .msg.warn{background:#fef3c7;color:#92400e}
  pre{background:#111827;color:#e5e7eb;padding:14px;border-radius:8px;overflow:auto;max-height:340px;font-size:12px;line-height:1.55;white-space:pre-wrap;word-break:break-all}
  .mono{font-family:ui-monospace,Menlo,Consolas,monospace}
  .apps{font-size:12px;color:#374151;white-space:pre-wrap;font-family:ui-monospace,Menlo,Consolas,monospace;background:#f9fafb;padding:12px;border-radius:8px;max-height:200px;overflow:auto}
  details summary{cursor:pointer;font-size:14px;font-weight:600;color:#374151;margin-bottom:10px}
</style>
</head>
<body>
<div class="wrap">
  <h1>OpenP2P 内网穿透</h1>
  <div class="sub">核心版本 <span class="mono">$(h "$VER")</span> · 飞牛 fnOS 封装版</div>
HTML

if [ -n "$MSG" ]; then
    echo "<div class=\"msg $(h "$MSG_KIND")\">$(h "$MSG")</div>"
fi

cat <<HTML
  <div class="card">
    <h2>运行状态</h2>
    <div style="margin-bottom:12px">
      $( [ "$RUNNING" = "yes" ] && echo '<span class="badge on">● 运行中</span>' || echo '<span class="badge off">● 已停止</span>' )
    </div>
    $( [ -z "$S_TOKEN" ] && echo '<div class="hint" style="margin-bottom:12px">⚠️ 尚未填写 Token：应用可以正常启动，但在填写 Token 并保存前不会登录组网。在下方「配置」中填入 <a href="https://console.openp2p.cn" target="_blank">console.openp2p.cn</a> 的个人 Token（纯数字）后保存即可。</div>' )
    <div class="grid">
      <div class="kv"><div class="k">进程 PID</div><div class="v mono">$(h "${PID:-—}")</div></div>
      <div class="kv"><div class="k">运行时长</div><div class="v mono">$(h "${UP:-—}")</div></div>
      <div class="kv"><div class="k">节点名</div><div class="v mono">$(h "$S_NODE")</div></div>
      <div class="kv"><div class="k">Token</div><div class="v mono">$(h "$(mask_token "$S_TOKEN")")</div></div>
      <div class="kv"><div class="k">服务端</div><div class="v mono">$(h "$S_SH:$S_SP")</div></div>
      <div class="kv"><div class="k">共享带宽上限</div><div class="v mono">$(h "${S_SB} Mbps")</div></div>
    </div>
    <div class="btns">
      <form method="post" style="display:inline"><input type="hidden" name="action" value="start"><button class="b3" type="submit">启动</button></form>
      <form method="post" style="display:inline"><input type="hidden" name="action" value="stop"><button class="b2" type="submit">停止</button></form>
      <form method="post" style="display:inline"><input type="hidden" name="action" value="restart"><button class="b4" type="submit">重启</button></form>
      <form method="post" style="display:inline"><button class="b4" type="submit">刷新</button></form>
    </div>
  </div>

  <div class="card">
    <h2>配置</h2>
    <form method="post">
      <input type="hidden" name="action" value="save">
      <div class="row">
        <div>
          <label>Token</label>
          <input type="text" name="token" value="" placeholder="$(h "$(mask_token "$S_TOKEN")")" autocomplete="off">
          <div class="hint">来自 <a href="https://console.openp2p.cn" target="_blank">console.openp2p.cn</a> → 个人资料，纯数字。留空表示不修改</div>
        </div>
        <div>
          <label>本机节点名</label>
          <input type="text" name="node" value="" placeholder="$(h "$S_NODE")" autocomplete="off">
          <div class="hint">1-31 位字母/数字/-/_，留空表示不修改</div>
        </div>
      </div>
      <div class="row">
        <div>
          <label>共享带宽上限 (Mbps)</label>
          <input type="text" name="sharebandwidth" value="" placeholder="$(h "$S_SB")" autocomplete="off">
          <div class="hint">0 = 不加入共享网络（也无法使用他人节点中继）</div>
        </div>
        <div>
          <label>日志级别</label>
          <input type="text" name="loglevel" value="" placeholder="$(h "$S_LL")" autocomplete="off">
          <div class="hint">0 调试 / 1 信息 / 2 警告 / 3 错误</div>
        </div>
      </div>
      <div class="row">
        <div>
          <label>服务端地址</label>
          <input type="text" name="serverhost" value="" placeholder="$(h "$S_SH")" autocomplete="off">
          <div class="hint">默认 api.openp2p.cn</div>
        </div>
        <div>
          <label>服务端端口</label>
          <input type="text" name="serverport" value="" placeholder="$(h "$S_SP")" autocomplete="off">
          <div class="hint">默认 27183</div>
        </div>
      </div>
      <div class="btns">
        <button class="b1" type="submit">保存并应用</button>
      </div>
    </form>
  </div>

  <div class="card">
    <h2>自定义端口转发（P2PApp）</h2>
    <div class="apps">$(h "$APPS_HTML")</div>
    <div class="hint" style="margin-top:10px">推荐在 <a href="https://console.openp2p.cn" target="_blank">console.openp2p.cn</a> 创建 P2PApp，会自动下发到本节点；也可在下方高级设置里手动编辑 config.json 的 apps 数组。</div>
  </div>

  <div class="card">
    <details>
      <summary>高级：直接编辑 config.json</summary>
      <form method="post">
        <input type="hidden" name="action" value="raw_save">
        <div class="hint" style="margin:8px 0">保存前会校验 JSON 合法性，并自动备份旧文件为 config.json.bak；应用运行中会自动重启。</div>
        <textarea name="rawjson" rows="16" class="mono">$(h "$RAW_JSON")</textarea>
        <div class="btns"><button class="b1" type="submit">保存 config.json</button></div>
      </form>
    </details>
  </div>

  <div class="card">
    <h2>运行日志（最近 80 行）</h2>
    <pre>$(h "$LOG_TAIL")</pre>
    <div class="hint">完整日志：<span class="mono">$(h "$LOG_FILE")</span></div>
  </div>
</div>
</body>
</html>
HTML
