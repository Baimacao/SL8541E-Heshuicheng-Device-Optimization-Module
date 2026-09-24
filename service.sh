#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════════════════
#  service.sh —— 开机完成后跑
#  ---------------------------------------------------------------------------
#  post-fs-data 负责"抢时间"（充电节点），这里负责"善后"：
#    · 属性清单再写一遍（core + service）—— 有些属性开机过程中会被系统改回去
#    · sysctl（TCP 缓冲 / swappiness / I/O 调度）
#    · ZRAM 关停确认（拿 /proc/swaps 实证，不信"我下发过了"）
#    · 动态 DNS 守护
#    · 设置项（开发者选项 / 动画缩放）—— settings 连不上就改 XML
#    · 生成 WebUI 状态页
#
#  防重入：脚本中途被拉起两次会把设置项写两遍、守护进程起两个。
# ═══════════════════════════════════════════════════════════════════════════

MODDIR="${MODDIR:-${0%/*}}"
[ -d "$MODDIR" ] || MODDIR="/data/adb/modules/SL8541E_Config_Fix"

# shellcheck source=lib/common.sh
. "$MODDIR/lib/common.sh"

LOCK="$STATE.lock"
mkdir -p "$MODDIR" 2>/dev/null
if [ -f "$LOCK" ]; then
    fish_log "service.sh 已在运行（锁存在），本次退出"
    exit 0
fi
: > "$LOCK" 2>/dev/null
trap 'rm -f "$LOCK" 2>/dev/null' EXIT

fish_log "── service.sh 开始 ──"
fish_log "开机完成，大肥鱼二次巡检"

# ── 1. 属性清单：core 二次保险 + service 段一次补齐 ──
prop_apply core service

# ── 2. TCP 参数（接管 tcpboost 模块干的活）──
#   这台内核没有 BBR（4.4.83 未编译），拥塞算法保持 cubic，只调缓冲与开关。
sysctl_set() {
    [ -e "$1" ] || return 0
    echo "$2" > "$1" 2>/dev/null
}
sysctl_set /proc/sys/net/core/rmem_max                8388608
sysctl_set /proc/sys/net/core/wmem_max                8388608
sysctl_set /proc/sys/net/ipv4/tcp_rmem                "4096 87380 8388608"
sysctl_set /proc/sys/net/ipv4/tcp_wmem                "4096 87380 8388608"
sysctl_set /proc/sys/net/ipv4/tcp_sack                1
sysctl_set /proc/sys/net/ipv4/tcp_window_scaling      1
sysctl_set /proc/sys/net/ipv4/tcp_timestamps          1
sysctl_set /proc/sys/net/ipv4/tcp_fastopen            1
sysctl_set /proc/sys/net/ipv4/tcp_tw_reuse            1
sysctl_set /proc/sys/net/ipv4/tcp_low_latency         1
sysctl_set /proc/sys/vm/swappiness                    150
sysctl_set /sys/block/mmcblk0/queue/scheduler         noop
fish_log "sysctl：TCP 缓冲 / swappiness=150 / I-O=noop 已下发"

# ── 3. ZRAM 确认（实证，不靠下发记录）──
setprop ctl.stop zram 2>/dev/null
swapoff /dev/block/zram0 2>/dev/null
if grep -q zram /proc/swaps 2>/dev/null; then
    fish_log "⚠ ZRAM 仍在运行：$(grep zram /proc/swaps 2>/dev/null | tr -s ' ')"
else
    fish_log "✅ ZRAM 确认已关闭"
fi

# ── 4. 充电二次保险（节点此时通常已锁，写了不生效也无害）──
#   注意不能写 `charge_boost service | read _x`：read 在子 shell 里，拿不到值。
CHG_HIT=$(charge_boost service)
fish_log "充电二次保险：命中 $CHG_HIT 个节点（开机后大多已锁，写不进属正常）"

# ── 5. 动态 DNS 守护 ──
GUARD="$MODDIR/lib/dns-guard.sh"
PIDFILE="$MODDIR/.dnsguard.pid"
_guard_running() {
    [ -f "$PIDFILE" ] || return 1
    _p=$(cat "$PIDFILE" 2>/dev/null | tr -d ' \n')
    [ -n "$_p" ] || return 1
    [ -d "/proc/$_p" ] || return 1
    return 0
}
if [ -f "$GUARD" ]; then
    if _guard_running; then
        fish_log "DNS 守护已在运行（pid $(cat "$PIDFILE" 2>/dev/null | tr -d ' \n')），不重复拉起"
    else
        nohup sh "$GUARD" >/dev/null 2>&1 &
        fish_log "DNS 守护已拉起"
    fi
else
    fish_log "⚠ 找不到 lib/dns-guard.sh，跳过"
fi

# ── 6. 设置项：开发者选项 ──
#   settings 在部分上下文连不上 system_server（报 Failed transaction），
#   所以先 settings 重试，全失败再直接改 XML。
fish_log "开始写开发者选项"
if settings_put development_settings_enabled 1; then
    fish_log "✅ 开发者选项写入成功"
else
    fish_log "⚠ settings 写不进去，改 XML 兜底"
    settings_xml_force development_settings_enabled 1
fi
settings_put adb_enabled 1 2 >/dev/null 2>&1

# ── 7. 动画：两步法 ──
#   为什么要先写 1.0 再写目标值：某些 ROM 上直接写缩放值会被忽略，
#   先归位再设才会真正落盘（实测出来的土办法）。
settings put global window_animation_scale 1.0 2>/dev/null
settings put global transition_animation_scale 1.0 2>/dev/null
settings put global animator_duration_scale 1.0 2>/dev/null
sleep 1
settings put global window_animation_scale 0.75 2>/dev/null
settings put global transition_animation_scale 0.75 2>/dev/null
settings put global animator_duration_scale 0.5 2>/dev/null

fish_log "动画值：窗口=$(settings_get window_animation_scale) 过渡=$(settings_get transition_animation_scale) 时长=$(settings_get animator_duration_scale)"

# ── 8. 生成 WebUI 状态页 ──
[ -f "$MODDIR/webroot/gen_status.sh" ] && sh "$MODDIR/webroot/gen_status.sh" 2>/dev/null
fish_log "WebUI 状态页已生成"

fish_log "── service.sh 结束 ──"
fish_log "🐟 巡检完毕。摸鱼去了，红烧肉记得叫我。"
exit 0
