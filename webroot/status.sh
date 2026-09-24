#!/system/bin/sh

# ═══════════════════════════════════════
# 状态输出脚本
# 输出格式：key|value
#   1 = 已生效 / 0 = 未生效 / 其他 = 原始值
# ═══════════════════════════════════════

MODDIR="$(cd "$(dirname "$0")/.." && pwd)"
[ ! -d "$MODDIR" ] && MODDIR="/data/adb/modules/SL8541E_Config_Fix"

out() { echo "$1|$2"; }

# ═══════════════════════════════════════
# 版本
# ═══════════════════════════════════════
if [ -f "$MODDIR/module.prop" ]; then
    VER=$(grep '^version=' "$MODDIR/module.prop" | head -1 | cut -d= -f2)
    out "VER" "$VER"
fi

# ═══════════════════════════════════════
# 属性检测
# ═══════════════════════════════════════
chkv() {
    if [ "$(getprop "$1")" = "$2" ]; then echo "1"; else echo "0"; fi
}

out "5G"       "$(chkv persist.sys.5g false)"
out "LOGO"     "$(chkv persist.sys.logo 4G)"
out "CPU"      "$(chkv persist.sys.cpu 4)"
out "FAKE_ROM" "$(chkv persist.sys.rom.fake 0)"
out "REAL_RAM" "$(chkv persist.sys.isshowrealram 1)"
out "FP_OFF"   "$(chkv persist.support.fingerprint false)"
out "FACE_OFF" "$(chkv heils.facelock 0)"
out "REFOCUS"  "$(chkv persist.sys.cam.refocus.enable true)"
out "DBL_TAP"  "$(chkv ro.config.f14_double_click_recent_tasks true)"
out "LOCKWALL" "$(chkv ro.lockwallpaper.enable true)"
out "STAT_OFF" "$(chkv ro.hsc.statistics false)"
out "IOT_OFF"  "$(chkv ro.hsc.iot false)"
out "APR_OFF"  "$(chkv persist.sys.apr.autoupload 0)"
out "HB_OFF"   "$(chkv persist.sys.heartbeat.enable 0)"
out "BS_OFF"   "$(chkv persist.sys.bsservice.enable 0)"
out "RWND"     "$(chkv net.tcp.default_init_rwnd 256)"
out "RESAMPLE" "$(chkv af.resampler.quality 4)"
out "SF_BP"    "$(chkv debug.sf.disable_backpressure 0)"
out "SF_LATCH" "$(chkv debug.sf.latch_unsignaled 0)"

# ─── 开发者选项（读 XML）───
DEV=""
for xml in /data/system/users/0/settings_global.xml /data/system/settings_global.xml; do
    [ -f "$xml" ] || continue
    DEV=$(grep -o 'name="development_settings_enabled"[^/]*' "$xml" 2>/dev/null | \
          grep -o 'value="[^"]*"' | head -1 | sed 's/value="//;s/"$//')
    [ -n "$DEV" ] && break
done
[ "$DEV" = "1" ] && out "DEV_OPT" "1" || out "DEV_OPT" "0"

# ─── dex2oat ───
out "DEX_THREADS" "$(getprop dalvik.vm.dex2oat-threads)"
out "DEX_CPUSET"  "$(getprop dalvik.vm.dex2oat-cpu-set)"

# ─── TCP ───
out "TCP_RMEM" "$(cat /proc/sys/net/core/rmem_max 2>/dev/null)"
out "TCP_WMEM" "$(cat /proc/sys/net/core/wmem_max 2>/dev/null)"
out "TCP_CC"   "$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)"

# ─── 内核 ───
out "SWAPPINESS" "$(cat /proc/sys/vm/swappiness 2>/dev/null)"

IO_RAW=$(cat /sys/block/mmcblk0/queue/scheduler 2>/dev/null)
IO_SEL=$(echo "$IO_RAW" | grep -o '\[[a-z]*\]' | tr -d '[]')
if [ "$IO_SEL" = "noop" ]; then
    out "IO_SCHED" "noop ✓"
else
    out "IO_SCHED" "$IO_SEL ✗"
fi

# ─── 内存 ───
MEM_TOTAL=$(grep MemTotal /proc/meminfo 2>/dev/null | tr -s ' ' | cut -d' ' -f2)
MEM_AVAIL=$(grep MemAvailable /proc/meminfo 2>/dev/null | tr -s ' ' | cut -d' ' -f2)
[ -n "$MEM_TOTAL" ] && out "MEM_TOTAL" "$((MEM_TOTAL / 1024))"
[ -n "$MEM_AVAIL" ] && out "MEM_AVAIL" "$((MEM_AVAIL / 1024))"

# ─── ZRAM ───
if grep -q zram /proc/swaps 2>/dev/null; then
    out "ZRAM_OFF" "0"
else
    out "ZRAM_OFF" "1"
fi

# ─── 充电 ───
CHG_LIMIT="/sys/devices/platform/battery/power_supply/battery/input_current_limit"
CHG_AC="/sys/devices/platform/battery/power_supply/ac/current_max"
[ -e "$CHG_LIMIT" ] && out "CHG_LIMIT" "$(cat "$CHG_LIMIT" 2>/dev/null | tr -d ' \n')"
[ -e "$CHG_AC" ] && out "CHG_AC" "$(cat "$CHG_AC" 2>/dev/null | tr -d ' \n')"

# ─── Wear OS ───
[ -f /system/framework/com.google.android.wearable.jar ] && out "WEAR_JAR" "1" || out "WEAR_JAR" "0"
[ -f /system/framework/wear-service.jar ] && out "WEAR_SVC" "1" || out "WEAR_SVC" "0"
[ -f /system/etc/permissions/com.google.android.wearable.xml ] && out "WEAR_XML" "1" || out "WEAR_XML" "0"

# ─── GitHub ───
GH_IP=""
if [ -f /system/etc/hosts ]; then
    GH_LINE=$(grep -E "^[0-9.]+[[:space:]]+github\.com" /system/etc/hosts 2>/dev/null | head -1)
    if [ -n "$GH_LINE" ]; then
        out "GH_HOSTS" "1"
        GH_IP=$(echo "$GH_LINE" | tr -s ' ' | cut -d' ' -f1)
        out "GH_IP" "$GH_IP"
    else
        out "GH_HOSTS" "0"
    fi
else
    out "GH_HOSTS" "0"
fi

if pgrep -f "ping -c 1 -w 2 github" >/dev/null 2>&1; then
    out "GH_DNS" "1"
else
    out "GH_DNS" "0"
fi

# ─── 动画值 ───
get_anim() {
    for xml in /data/system/users/0/settings_global.xml /data/system/settings_global.xml; do
        [ -f "$xml" ] || continue
        val=$(grep -o "name=\"$1\"[^/]*" "$xml" 2>/dev/null | \
              grep -o 'value="[^"]*"' | head -1 | sed 's/value="//;s/"$//')
        [ -n "$val" ] && { echo "$val"; return; }
    done
    settings get global "$1" 2>/dev/null
}

out "ANIM_WIN"   "$(get_anim window_animation_scale)"
out "ANIM_TRANS" "$(get_anim transition_animation_scale)"
out "ANIM_DUR"   "$(get_anim animator_duration_scale)"

# ─── 电池 ───
BATT_DIRS="/sys/class/power_supply/battery /sys/class/power_supply/sprdbattery /sys/class/power_supply/BAT0"
find_node() {
    for d in $BATT_DIRS; do
        [ -e "$d/$1" ] && { echo "$d/$1"; return; }
    done
}
read_node() {
    p=$(find_node "$1")
    [ -z "$p" ] && return
    cat "$p" 2>/dev/null | tr -d ' \r\n'
}

CAP=$(read_node capacity)
VOL=$(read_node voltage_now)
CUR=$(read_node current_now)
TMP=$(read_node temp)
HLT=$(read_node health)
STS=$(read_node status)

[ -n "$CAP" ] && out "BATT_CAP" "$CAP"

if [ -n "$VOL" ]; then
    if [ "$VOL" -gt 100000 ] 2>/dev/null; then
        V=$((VOL / 1000000)).$(printf "%02d" $(((VOL % 1000000) / 10000)))
    elif [ "$VOL" -gt 1000 ] 2>/dev/null; then
        V=$((VOL / 1000)).$(printf "%02d" $(((VOL % 1000) / 10)))
    else
        V="$VOL"
    fi
    out "BATT_VOLT" "$V"
fi

if [ -n "$CUR" ]; then
    if [ "$CUR" -lt 0 ] 2>/dev/null; then
        CUR_A=$((0 - CUR))
        out "BATT_CUR" "放电 $((CUR_A / 1000)) mA"
    else
        out "BATT_CUR" "充电 $((CUR / 1000)) mA"
    fi
fi

[ -n "$TMP" ] && out "BATT_TEMP" "$((TMP / 10)).$((TMP % 10))"

case "$HLT" in
    Good) out "BATT_HEALTH" "良好" ;;
    Overheat) out "BATT_HEALTH" "过热" ;;
    Dead) out "BATT_HEALTH" "损坏" ;;
    "") out "BATT_HEALTH" "未知" ;;
    *) out "BATT_HEALTH" "$HLT" ;;
esac

case "$STS" in
    Charging) out "BATT_STATUS" "充电中" ;;
    Discharging) out "BATT_STATUS" "放电中" ;;
    Full) out "BATT_STATUS" "已充满" ;;
    Not\ charging) out "BATT_STATUS" "未充电" ;;
    "") out "BATT_STATUS" "未知" ;;
    *) out "BATT_STATUS" "$STS" ;;
esac

exit 0