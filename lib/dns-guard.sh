#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════════════════
#  dns-guard.sh —— GitHub 动态 DNS 守护
#  ---------------------------------------------------------------------------
#  背景：这台表上没有靠谱的 DNS，github.com 经经常解析不出来。
#  做法：模块自带一份 system/etc/hosts（静态 GitHub IP），再挂一个守护进程，
#        每 30 分钟探一次；探不通就从 IP 池里换一个能 ping 通的，
#        改 hosts 后用 mount --bind 覆盖 /system/etc/hosts。
#
#  v1.2 里这段是塞在 service.sh 的一个 nohup sh -c '...' 单引号字符串里，
#  里面还嵌着变量拼接，改一行就得数引号。现在独立成文件，顺带把
#  「怎么判断它在跑」从 pgrep 猜改成写 pid 文件 —— pgrep 匹配的是
#  ping 命令的字符串，ping 一结束那一刻就会误判成"守护没起来"。
#
#  由 service.sh 后台拉起：  nohup sh dns-guard.sh >/dev/null 2>&1 &
# ═══════════════════════════════════════════════════════════════════════════

MODDIR="${MODDIR:-${0%/*}/..}"
[ -d "$MODDIR" ] || MODDIR="/data/adb/modules/SL8541E_Config_Fix"
MODDIR="${MODDIR%/lib}"          # 允许从 lib/ 下直接调用
[ -d "$MODDIR" ] || MODDIR="/data/adb/modules/SL8541E_Config_Fix"

LOG="$MODDIR/fix.log"
PIDFILE="$MODDIR/.dnsguard.pid"
HOSTS="$MODDIR/system/etc/hosts"

# 候补 IP：按延迟顺序试，第一个通的就用
IP_POOL="20.205.243.166 20.205.243.168 20.27.177.113 20.200.245.247 140.82.112.4"
CHECK_INTERVAL=1800              # 30 分钟一次
PING_TIMEOUT=2

# 防御：这两个值会直接进 `sleep`，非数字/空/0 会让守护空转（CPU 100%）
# 或干脆报错退出。技能清单里"validate all inputs"就指这类。
case "$CHECK_INTERVAL" in
    ''|*[!0-9]*) CHECK_INTERVAL=1800 ;;
esac
[ "$CHECK_INTERVAL" -ge 60 ] 2>/dev/null || CHECK_INTERVAL=1800
case "$PING_TIMEOUT" in
    ''|*[!0-9]*) PING_TIMEOUT=2 ;;
esac
[ "$PING_TIMEOUT" -ge 1 ] 2>/dev/null || PING_TIMEOUT=2

log() { echo "[$(date '+%m-%d %H:%M:%S')] [dns] $*" >> "$LOG" 2>/dev/null; }

echo $$ > "$PIDFILE" 2>/dev/null
log "守护启动 pid=$$"

# ── 可达性探测 ─────────────────────────────────────────────────────────────
# ⚠ 不能只 ping 域名：DNS 坏的时候域名本来就不通，用它当判据等于自证循环，
#   永远"探不通"、永远去打日志。改成先 ping 免 DNS 的 IP（114.114.114.114），
#   网络本身不通就安静待着，不去改 hosts —— 免得越改越糟。
net_ok() {
    ping -c 1 -w 2 114.114.114.114 >/dev/null 2>&1 && return 0
    ping -c 1 -w 2 223.5.5.5 >/dev/null 2>&1 && return 0
    return 1
}
# hosts 里 github.com 当前指向哪个 IP（空 = 没有条目）
#   $1 传 live 时读**挂载后**的 /system/etc/hosts —— 那才是用户实际生效的那份。
#   默认读模块内那份（维护候选池用）。
#   ⚠ 两个视图必须分开：只用模块内那份做校验，等于自己跟自己比对，
#     bind mount 失败也照样"验证通过"。
current_gh_ip() {
    _f="$HOSTS"
    [ "${1:-}" = "live" ] && _f="/system/etc/hosts"
    [ -f "$_f" ] || return 1
    grep -E '^[0-9.]+[[:space:]]+github\.com' "$_f" 2>/dev/null | head -1 | tr -s ' ' | cut -d' ' -f1
}

# ── 写入并**验证**是否真的生效 ──────────────────────────────────────────────
# 之前的版本写完就打印"已切到 X"，但 mount 失败/文件只读时也照打 —— 误导排查。
apply_ip() {
    _ip="$1"
    [ -f "$HOSTS" ] || { log "hosts 不存在，放弃切换"; return 1; }

    #  ⚠ 这里**绝不能**用 `sed -i`（v2.1.3 之前就是，属于真 bug）：
    #    sed -i 的做法是"写新文件再 rename"，inode 会变。而 $HOSTS 这个文件
    #    已经被 service.sh 用 `mount --bind` 挂到了 /system/etc/hosts 上，
    #    绑定挂载跟的是**旧的 inode**。于是：
    #      我们改的是新 inode → 读回校验通过 → 日志写"已切到 X"
    #      但 /system/etc/hosts 还是旧 inode → 用户侧毫无变化
    #    守护进程自证成功，故障却一点没解决。这正是 common.sh 里那条
    #    "不用 sed -i" 纪律要防的事，只是当时只在 settings XML 那边执行了。
    #    改成"写到临时文件 → cat 原地覆写"：`> ` 不换 inode，bind mount 才看得见。
    _tmp="$MODDIR/.hosts.new"
    _err=$( { sed '/github\.com/d' "$HOSTS" > "$_tmp"; } 2>&1 )
    if [ -n "$_err" ] || [ ! -s "$_tmp" ]; then
        log "⚠ 清理旧条目失败：${_err:-结果为空}"
        rm -f "$_tmp" 2>/dev/null
        return 1
    fi
    _err=$( { printf '%s github.com\n%s www.github.com\n%s api.github.com\n%s codeload.github.com\n' \
              "$_ip" "$_ip" "$_ip" "$_ip" >> "$_tmp"; } 2>&1 )
    if [ -n "$_err" ]; then
        log "⚠ 构造新 hosts 失败：$_err"
        rm -f "$_tmp" 2>/dev/null
        return 1
    fi
    _err=$( { cat "$_tmp" > "$HOSTS"; } 2>&1 )
    rm -f "$_tmp" 2>/dev/null
    if [ -n "$_err" ]; then log "⚠ 写入 hosts 失败：$_err"; return 1; fi

    _err=$(mount --bind "$HOSTS" /system/etc/hosts 2>&1)
    _mounted=0
    [ -z "$_err" ] && _mounted=1

    setprop net.dns1 8.8.8.8 2>/dev/null
    setprop net.dns2 114.114.114.114 2>/dev/null

    # 验证：读**挂载后**的视图 —— 确认用户侧真的看到了新 IP
    _now=$(current_gh_ip live)
    if [ "$_now" = "$_ip" ]; then
        if [ "$_mounted" = "1" ]; then
            log "已切到 $_ip（hosts 已生效）"
            return 0
        else
            log "hosts 已写入 $_ip，但挂载失败：$_err"
            return 2
        fi
    fi
    log "⚠ 切到 $_ip 失败：写完读回是 [${_now:-空}]"
    return 1
}

# ── 主循环 ─────────────────────────────────────────────────────────────────
# 日志只在**状态变化**时打，不再每轮刷屏（原来每 30 分钟一条，一周上千行）。
_last_state=""
while true; do
    if ! net_ok; then
        _state="offline"
        [ "$_last_state" != "$_state" ] && log "网络本身不通，暂停 hosts 维护（等网络恢复）"
        _last_state="$_state"
        sleep "$CHECK_INTERVAL"
        continue
    fi

    # 网络通：检查 hosts 里的 github IP 还是不是池子里的候选
    _cur=$(current_gh_ip)
    if [ -z "$_cur" ]; then
        _state="noentry"
    else
        _hit=0
        for _ip in $IP_POOL; do [ "$_cur" = "$_ip" ] && _hit=1; done
        [ "$_hit" = "1" ] && _state="ok:$_cur" || _state="stale:$_cur"
    fi

    case "$_state" in
        ok:*)
            [ "$_last_state" != "$_state" ] && log "github IP 正常：${_state#ok:}"
            ;;
        noentry)
            [ "$_last_state" != "$_state" ] && log "hosts 里没有 github 条目，尝试补一个"
            for _ip in $IP_POOL; do
                ping -c 1 -w 2 "$_ip" >/dev/null 2>&1 && { apply_ip "$_ip"; break; }
            done
            ;;
        stale:*)
            [ "$_last_state" != "$_state" ] && log "当前 IP ${_state#stale:} 已不在候选池，尝试更换"
            for _ip in $IP_POOL; do
                [ "$_ip" = "${_state#stale:}" ] && continue
                ping -c 1 -w 2 "$_ip" >/dev/null 2>&1 && { apply_ip "$_ip"; break; }
            done
            ;;
    esac
    _last_state="$_state"
    sleep "$CHECK_INTERVAL"
done
