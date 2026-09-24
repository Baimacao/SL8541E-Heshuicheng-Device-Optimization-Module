#!/system/bin/sh

MODDIR="${MODDIR:-${0%/*}}"
[ ! -d "$MODDIR" ] && MODDIR="/data/adb/modules/SL8541E_Config_Fix"
LOG="$MODDIR/fix.log"

i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ $i -lt 60 ]; do
    sleep 2
    i=$((i+1))
done
sleep 5

echo "[$(date)] 系统启动完毕，大肥鱼二次巡检开始……" >> "$LOG"

# ═══════════════════════════════════════
# 属性覆盖（二次保险）
# ═══════════════════════════════════════
resetprop -n persist.sys.5g false
resetprop -n persist.sys.logo 4G
resetprop -n persist.sys.cpu 4
resetprop -n persist.sys.rom.fake 0
resetprop -n persist.sys.isshowrealram 1

resetprop -n persist.sys.apr.enabled 0
resetprop -n persist.sys.apr.autoupload 0
resetprop -n persist.sys.apr.reportlevel 0
resetprop -n persist.sys.bsservice.enable 0
resetprop -n persist.sys.heartbeat.enable 0

resetprop -n persist.support.fingerprint false
resetprop -n heils.facelock 0
resetprop -n persist.sys.cam.refocus.enable true

resetprop ro.config.f14_double_click_recent_tasks true
resetprop ro.lockwallpaper.enable true

resetprop dalvik.vm.dex2oat-threads 4
resetprop dalvik.vm.image-dex2oat-threads 4
resetprop dalvik.vm.bg-dex2oat-threads 4
resetprop dalvik.vm.boot-dex2oat-threads 4
resetprop dalvik.vm.dex2oat-cpu-set 0,1,2,3
resetprop dalvik.vm.boot-dex2oat-cpu-set 0,1,2,3
resetprop dalvik.vm.background-dex2oat-cpu-set 0,1,2,3
resetprop dalvik.vm.default-dex2oat-cpu-set 0,1,2,3

resetprop net.tcp.default_init_rwnd 256

resetprop debug.sf.disable_backpressure 0
resetprop debug.sf.latch_unsignaled 0

# ⭐ UI 实时优先级
resetprop sys.use_fifo_ui 1

# ═══════════════════════════════════════
# 接管 tcpboost
# ═══════════════════════════════════════
echo 8388608 > /proc/sys/net/core/rmem_max 2>/dev/null
echo 8388608 > /proc/sys/net/core/wmem_max 2>/dev/null
echo "4096 87380 8388608" > /proc/sys/net/ipv4/tcp_rmem 2>/dev/null
echo "4096 87380 8388608" > /proc/sys/net/ipv4/tcp_wmem 2>/dev/null
echo 1 > /proc/sys/net/ipv4/tcp_sack 2>/dev/null
echo 1 > /proc/sys/net/ipv4/tcp_window_scaling 2>/dev/null
echo 1 > /proc/sys/net/ipv4/tcp_timestamps 2>/dev/null
echo 1 > /proc/sys/net/ipv4/tcp_fastopen 2>/dev/null
echo 1 > /proc/sys/net/ipv4/tcp_tw_reuse 2>/dev/null
echo 1 > /proc/sys/net/ipv4/tcp_low_latency 2>/dev/null

# ═══════════════════════════════════════
# 强制关闭 ZRAM（二次保险）
# ═══════════════════════════════════════
setprop ctl.stop zram 2>/dev/null
swapoff /dev/block/zram0 2>/dev/null
ZRAM_STATE=$(grep zram /proc/swaps 2>/dev/null)
if [ -z "$ZRAM_STATE" ]; then
    echo "[$(date)] ✅ ZRAM 已关闭" >> "$LOG"
else
    echo "[$(date)] ⚠ ZRAM 仍在运行: $ZRAM_STATE" >> "$LOG"
fi

# ═══════════════════════════════════════
# 充电加速 3A（二次保险）
# ═══════════════════════════════════════
echo "[$(date)] 调整充电电流..." >> "$LOG"

CHG_AC="/sys/devices/platform/battery/power_supply/ac/current_max"
CHG_USB="/sys/devices/platform/battery/power_supply/usb/current_max"
CHG_LIMIT="/sys/devices/platform/battery/power_supply/battery/input_current_limit"
CHG_MAX="/sys/devices/platform/battery/power_supply/battery/current_max"

for node in "$CHG_AC" "$CHG_USB" "$CHG_LIMIT" "$CHG_MAX"; do
    if [ -e "$node" ]; then
        echo 3000000 > "$node" 2>/dev/null
        RAW=$(cat "$node" 2>/dev/null | tr -d ' \n')
        echo "[$(date)]   $(basename $(dirname $node))/$(basename $node) = ${RAW}µA ($((RAW / 1000))mA)" >> "$LOG"
    fi
done

# ═══════════════════════════════════════
# 内核参数
# ═══════════════════════════════════════
echo 150 > /proc/sys/vm/swappiness 2>/dev/null
echo noop > /sys/block/mmcblk0/queue/scheduler 2>/dev/null

# ═══════════════════════════════════════
# 动态 DNS 守护
# ═══════════════════════════════════════
IP_POOL="20.205.243.166 20.205.243.168 20.27.177.113 20.200.245.247 140.82.112.4"
MOD_HOSTS="$MODDIR/system/etc/hosts"

nohup sh -c '
    MOD_HOSTS="'"$MOD_HOSTS"'"
    LOG="'"$LOG"'"
    IP_POOL="'"$IP_POOL"'"

    while true; do
        if ! ping -c 1 -w 2 github.com >/dev/null 2>&1; then
            for ip in $IP_POOL; do
                if ping -c 1 -w 2 "$ip" >/dev/null 2>&1; then
                    if [ -f "$MOD_HOSTS" ]; then
                        sed -i "/github.com/d" "$MOD_HOSTS" 2>/dev/null
                        echo "$ip github.com" >> "$MOD_HOSTS"
                        echo "$ip www.github.com" >> "$MOD_HOSTS"
                        echo "$ip api.github.com" >> "$MOD_HOSTS"
                        mount --bind "$MOD_HOSTS" /system/etc/hosts 2>/dev/null
                        setprop net.dns1 8.8.8.8
                        setprop net.dns2 114.114.114.114
                        echo "[$(date)] DNS 失效，已切换至 $ip" >> "$LOG"
                    fi
                    break
                fi
            done
        fi
        sleep 1800
    done
' >/dev/null 2>&1 &

echo "[$(date)] 动态 DNS 守护进程已启动" >> "$LOG"

# ═══════════════════════════════════════
# Settings 辅助
# ═══════════════════════════════════════
SETTINGS_XML="/data/system/users/0/settings_global.xml"

xml_read() {
    [ -f "$SETTINGS_XML" ] || { echo ""; return; }
    grep -o "name=\"$1\"[^/]*" "$SETTINGS_XML" 2>/dev/null | \
        grep -o 'value="[^"]*"' | head -1 | sed 's/value="//;s/"$//'
}

cmd_read() {
    out=$("$@" 2>/dev/null)
    case "$out" in
        *"Failure"*|*"cmd:"*|*"Error"*|*"null"|"") echo "" ;;
        *) echo "$out" ;;
    esac
}

verify_setting() {
    key="$1"; want="$2"
    got=$(cmd_read settings get global "$key")
    [ "$got" = "$want" ] && return 0
    got=$(xml_read "$key")
    [ "$got" = "$want" ]
}

write_setting() {
    key="$1"; val="$2"
    for round in 1 2 3 4 5; do
        settings put global "$key" "$val" 2>/dev/null
        verify_setting "$key" "$val" && return 0
        cmd settings put global "$key" "$val" 2>/dev/null
        verify_setting "$key" "$val" && return 0
        sleep 3
    done
    return 1
}

echo "[$(date)] 开始写开发者选项……" >> "$LOG"
if write_setting development_settings_enabled 1; then
    echo "[$(date)] ✅ 开发者选项写入成功" >> "$LOG"
else
    echo "[$(date)] ⚠ 开发者选项写入失败，XML 兜底" >> "$LOG"
    if [ -f "$SETTINGS_XML" ]; then
        cp "$SETTINGS_XML" "$SETTINGS_XML.bak" 2>/dev/null
        if grep -q 'name="development_settings_enabled"' "$SETTINGS_XML"; then
            sed -i 's|name="development_settings_enabled" value="[^"]*"|name="development_settings_enabled" value="1"|' "$SETTINGS_XML"
        else
            sed -i 's|</settings>|<setting id="0" name="development_settings_enabled" value="1" package="android" />\n</settings>|' "$SETTINGS_XML"
        fi
    fi
fi

write_setting adb_enabled 1 >/dev/null 2>&1

# ═══════════════════════════════════════
# 修复动画（两步法）
# ═══════════════════════════════════════
settings put global window_animation_scale 1.0
settings put global transition_animation_scale 1.0
settings put global animator_duration_scale 1.0
sleep 1

settings put global window_animation_scale 0.75
settings put global transition_animation_scale 0.75
settings put global animator_duration_scale 0.5

W=$(cmd_read settings get global window_animation_scale)
T=$(cmd_read settings get global transition_animation_scale)
A=$(cmd_read settings get global animator_duration_scale)
echo "[$(date)] 动画值: 窗口=$W 过渡=$T 时长=$A" >> "$LOG"

# ═══════════════════════════════════════
# 生成 WebUI 状态页
# ═══════════════════════════════════════
[ -f "$MODDIR/webroot/gen_status.sh" ] && sh "$MODDIR/webroot/gen_status.sh"
echo "[$(date)] WebUI 状态页已生成" >> "$LOG"

echo "[$(date)] 全部搞定，大肥鱼表示可以摸鱼了 ~" >> "$LOG"