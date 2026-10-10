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
# 锁要带"本次开机"标识：否则上次 service.sh 被强杀（trap 没跑到）而锁文件留在
# /data 上时，之后**每次开机**都会直接 exit 0 —— 动画、sysctl、DNS、状态页全部静默不执行，
# 日志只有一行"已在运行"。这是最隐蔽的单点故障。
_BOOT_ID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null | tr -d ' \r\n')
[ -n "$_BOOT_ID" ] || _BOOT_ID=$(cat /proc/uptime 2>/dev/null | cut -d' ' -f1)
if [ -f "$LOCK" ]; then
    _LOCK_BOOT=$(cat "$LOCK" 2>/dev/null | tr -d ' \r\n')
    if [ -n "$_LOCK_BOOT" ] && [ "$_LOCK_BOOT" = "$_BOOT_ID" ]; then
        fish_log "service.sh 已在运行（同一开机内的锁），本次退出"
        exit 0
    fi
    fish_log "发现上次开机残留的锁，清除后继续（避免静默失联）"
fi
: > "$LOCK" 2>/dev/null
printf '%s\n' "$_BOOT_ID" >> "$LOCK" 2>/dev/null
trap 'rm -f "$LOCK" 2>/dev/null' EXIT

fish_log "── service.sh 开始 ──"

# ⚠ 必须先等开机完成，再动手。这不是"保险起见"，是硬前置：
#   · service.sh 是 late_start，此刻 system_server 还没把设置项初始化完，
#     现在写动画缩放会被它随后的初始化覆盖掉 —— 白写
#   · 动画的三轮循环（每轮"先全部 1.0 再全部目标值"）整段依赖这个时序，
#     提前跑等于三轮都白做
#   · 属性类操作倒是越早越好，但那些在 post-fs-data 里已经做过了
#   v1.2 原本就有这个循环，v1.3 重构时被我漏掉了 —— 别再删。
wait_boot
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
#   开机完成后节点大多已锁，但偶尔有驱动是在这时候才解锁的，所以再做一次
#   有界重试（3 次 × 5 秒）。全部已是目标值时会直接跳过，不做无用写入。
#   注意不能写 `charge_retry ... | read _x`：read 在子 shell 里，拿不到值。
charge_retry service 3 5

# 充电也要常驻复写：实测写成功过（3000 mA），但下次开机又回到 500 ——
# 同一个"系统周期性回写"机制。后台跑 20 轮 × 30 秒 ≈ 10 分钟，只补偏离的节点。
# ⚠ 后台进程必须留 pidfile：否则卸载后它会一直活着（孤儿进程）。
#   用户的要求是"动画不要守护进程"，充电这个是另一回事，但同样要能收干净。
charge_keepalive service 20 30 &
echo $! > "$MODDIR/.charge-keepalive.pid" 2>/dev/null

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

# ── 7. 生成 WebUI 状态页 ──
#   放到动画之前，别让动画那段 sleep 挡住状态页生成
#   （否则用户点开 WebUI 会看到上一次开机的旧快照）。
[ -f "$MODDIR/webroot/gen_status.sh" ] && sh "$MODDIR/webroot/gen_status.sh" 2>/dev/null
fish_log "WebUI 状态页已生成"

# ═══════════════════════════════════════════════════════════════════════════
#  修复动画（两步法）—— **完全按 1.x 原样**（用户指定）
#  ---------------------------------------------------------------------------
#  这就是 v1.1 ~ v1.6 一直用的那段实现，一字不改：
#      1.0 ×3 → sleep 1 → 0.75/0.75/0.5
#  只有一遍，不循环、不守护、不重试、不写 XML、**不加任何额外等待或沉降**。
#
#  为什么不再加等待（用户 2026-10-10 明确要求删掉）：
#    我先后加过"再等一次开机 / 沉降 15 秒 / 间隔拉长到 6 秒 / 三次覆盖 / 后台守护"，
#    全都没解决问题 —— 因为问题不在时机上：
#      · 报告和日志读回的值**都是 0.75**（说明设置库确实写进去了）
#      · 但系统设置界面仍显示 1.0x
#    也就是说写入"成功"了，系统却没按它执行。继续调时机是白费功夫。
#
#  无条件覆盖：这一段**没有任何 if** —— 不管当前是什么值都照写一遍。
#  绝不写"已经是目标值就跳过"：跳过就等于没执行。
# ═══════════════════════════════════════════════════════════════════════════

settings put global window_animation_scale 1.0
settings put global transition_animation_scale 1.0
settings put global animator_duration_scale 1.0
sleep 1

settings put global window_animation_scale 0.75
settings put global transition_animation_scale 0.75
settings put global animator_duration_scale 0.5

W=$(settings_get window_animation_scale)
T=$(settings_get transition_animation_scale)
A=$(settings_get animator_duration_scale)
fish_log "动画值: 窗口=$W 过渡=$T 时长=$A"

fish_log "── service.sh 结束 ──"
fish_log "🐟 巡检完毕。摸鱼去了，红烧肉记得叫我。"
exit 0
