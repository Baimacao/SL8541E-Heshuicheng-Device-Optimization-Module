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

log() { echo "[$(date '+%m-%d %H:%M:%S')] [dns] $*" >> "$LOG" 2>/dev/null; }

echo $$ > "$PIDFILE" 2>/dev/null
log "守护启动 pid=$$"

alive() { ping -c 1 -w $PING_TIMEOUT "$1" >/dev/null 2>&1; }

# 把 hosts 里的 github 段换成指定 IP
apply_ip() {
    _ip="$1"
    [ -f "$HOSTS" ] || { log "hosts 不存在，放弃切换"; return 1; }
    sed -i '/github\.com/d' "$HOSTS" 2>/dev/null
    {
        echo "$_ip github.com"
        echo "$_ip www.github.com"
        echo "$_ip api.github.com"
        echo "$_ip codeload.github.com"
    } >> "$HOSTS"
    mount --bind "$HOSTS" /system/etc/hosts 2>/dev/null
    setprop net.dns1 8.8.8.8 2>/dev/null
    setprop net.dns2 114.114.114.114 2>/dev/null
    log "已切到 $_ip"
}

while true; do
    if ! alive github.com; then
        log "github.com 探不通，开始换 IP"
        for _ip in $IP_POOL; do
            if alive "$_ip"; then
                apply_ip "$_ip"
                break
            fi
        done
    fi
    sleep $CHECK_INTERVAL
done
