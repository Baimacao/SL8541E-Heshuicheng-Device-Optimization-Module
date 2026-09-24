#!/system/bin/sh

MODDIR="${MODDIR:-/data/adb/modules/SL8541E_Config_Fix}"
WEBROOT="$MODDIR/webroot"
[ ! -d "$WEBROOT" ] && exit 0

TMP="$WEBROOT/status_generated.html.tmp"
OUT="$WEBROOT/status_generated.html"

chkv() {
    [ "$(getprop "$1")" = "$2" ] && echo "1" || echo "0"
}
ok_fail() {
    [ "$1" = "1" ] && echo '<span class="value ok">[OK]</span>' || echo '<span class="value fail">[NG]</span>'
}

V_5G=$(chkv persist.sys.5g false)
V_LOGO=$(chkv persist.sys.logo 4G)
V_CPU=$(chkv persist.sys.cpu 4)
V_FAKE=$(chkv persist.sys.rom.fake 0)
V_RAM=$(chkv persist.sys.isshowrealram 1)
V_FP=$(chkv persist.support.fingerprint false)
V_FACE=$(chkv heils.facelock 0)
V_REFOCUS=$(chkv persist.sys.cam.refocus.enable true)
V_DBL=$(chkv ro.config.f14_double_click_recent_tasks true)
V_LOCK=$(chkv ro.lockwallpaper.enable true)

V_STAT=$(chkv ro.hsc.statistics false)
V_IOT=$(chkv ro.hsc.iot false)
V_APR=$(chkv persist.sys.apr.autoupload 0)
V_HB=$(chkv persist.sys.heartbeat.enable 0)
V_BS=$(chkv persist.sys.bsservice.enable 0)

DEX_THREADS=$(getprop dalvik.vm.dex2oat-threads)
DEX_CPUSET=$(getprop dalvik.vm.dex2oat-cpu-set)

TCP_RMEM=$(cat /proc/sys/net/core/rmem_max 2>/dev/null)
TCP_WMEM=$(cat /proc/sys/net/core/wmem_max 2>/dev/null)
TCP_CC=$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)
V_RWND=$(chkv net.tcp.default_init_rwnd 256)

V_RESAMPLE=$(chkv af.resampler.quality 4)
SWAPPINESS=$(cat /proc/sys/vm/swappiness 2>/dev/null)

IO_RAW=$(cat /sys/block/mmcblk0/queue/scheduler 2>/dev/null)
IO_SEL=$(echo "$IO_RAW" | grep -o '\[[a-z]*\]' | tr -d '[]')
[ "$IO_SEL" = "noop" ] && IO_SHOW="noop [OK]" || IO_SHOW="$IO_SEL [NG]"

MEM_TOTAL=$(grep MemTotal /proc/meminfo 2>/dev/null | tr -s ' ' | cut -d' ' -f2)
MEM_AVAIL=$(grep MemAvailable /proc/meminfo 2>/dev/null | tr -s ' ' | cut -d' ' -f2)
[ -n "$MEM_TOTAL" ] && MEM_TOTAL=$((MEM_TOTAL / 1024))
[ -n "$MEM_AVAIL" ] && MEM_AVAIL=$((MEM_AVAIL / 1024))

grep -q zram /proc/swaps 2>/dev/null && V_ZRAM="0" || V_ZRAM="1"

# ⭐ Android Go
GO_MODE=$(getprop ro.config.low_ram)
[ "$GO_MODE" = "true" ] && GO_SHOW="enabled" || GO_SHOW="disabled"
GO_THRESHOLD=$(getprop ro.config.low_ram.threshold_gb)
[ -z "$GO_THRESHOLD" ] && GO_THRESHOLD="n/a"

# ⭐ 充电（µA ÷ 1000 = mA）
CHG_LIMIT="/sys/devices/platform/battery/power_supply/battery/input_current_limit"
CHG_AC="/sys/devices/platform/battery/power_supply/ac/current_max"
CHG_LIMIT_VAL=""
CHG_AC_VAL=""
if [ -e "$CHG_LIMIT" ]; then
    RAW=$(cat "$CHG_LIMIT" 2>/dev/null | tr -d ' \n')
    [ -n "$RAW" ] && CHG_LIMIT_VAL=$((RAW / 1000))
fi
if [ -e "$CHG_AC" ]; then
    RAW=$(cat "$CHG_AC" 2>/dev/null | tr -d ' \n')
    [ -n "$RAW" ] && CHG_AC_VAL=$((RAW / 1000))
fi

V_SF_BP=$(chkv debug.sf.disable_backpressure 0)
V_SF_LATCH=$(chkv debug.sf.latch_unsignaled 0)

[ -f /system/framework/com.google.android.wearable.jar ] && V_WJ="1" || V_WJ="0"
[ -f /system/framework/wear-service.jar ] && V_WS="1" || V_WS="0"
[ -f /system/etc/permissions/com.google.android.wearable.xml ] && V_WX="1" || V_WX="0"

GH_IP=""
[ -f /system/etc/hosts ] && GH_IP=$(grep -E "^[0-9.]+[[:space:]]+github\.com" /system/etc/hosts 2>/dev/null | head -1 | tr -s ' ' | cut -d' ' -f1)
[ -n "$GH_IP" ] && V_GH="1" || V_GH="0"

pgrep -f "ping -c 1 -w 2 github" >/dev/null 2>&1 && V_DNS="1" || V_DNS="0"

get_anim() {
    for xml in /data/system/users/0/settings_global.xml /data/system/settings_global.xml; do
        [ -f "$xml" ] || continue
        val=$(grep -o "name=\"$1\"[^/]*" "$xml" 2>/dev/null | grep -o 'value="[^"]*"' | head -1 | sed 's/value="//;s/"$//')
        [ -n "$val" ] && { echo "$val"; return; }
    done
}
ANIM_WIN=$(get_anim window_animation_scale)
ANIM_TRANS=$(get_anim transition_animation_scale)
ANIM_DUR=$(get_anim animator_duration_scale)

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
CUR=$(read_node current_now)
TMP=$(read_node temp)
HLT=$(read_node health)
STS=$(read_node status)

if [ -n "$CUR" ]; then
    if [ "$CUR" -lt 0 ] 2>/dev/null; then
        CUR_SHOW="放电 $(( (0 - CUR) / 1000 )) mA"
    else
        CUR_SHOW="充电 $(( CUR / 1000 )) mA"
    fi
else
    CUR_SHOW="?"
fi

[ -n "$TMP" ] && BATT_TEMP="$((TMP / 10)).$((TMP % 10))" || BATT_TEMP="?"
case "$HLT" in
    Good) BATT_HEALTH="良好" ;;
    Overheat) BATT_HEALTH="过热" ;;
    Dead) BATT_HEALTH="损坏" ;;
    "") BATT_HEALTH="未知" ;;
    *) BATT_HEALTH="$HLT" ;;
esac
case "$STS" in
    Charging) BATT_STATUS="充电中" ;;
    Discharging) BATT_STATUS="放电中" ;;
    Full) BATT_STATUS="已充满" ;;
    Not\ charging) BATT_STATUS="未充电" ;;
    *) BATT_STATUS="未知" ;;
esac

cat > "$TMP" << HTMLEOF
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<link rel="stylesheet" href="style.css">
<style>
body { padding: 0; background: #0a0e14; }
#app { max-width: 100%; margin: 0; padding: 8px; }
</style>
</head>
<body>
<div id="app">

<div class="card">
<h2><span class="dim">&gt;</span>SPOOF_STRIP</h2>
<div class="item"><span class="label">5G icon off</span>$(ok_fail $V_5G)</div>
<div class="item"><span class="label">4G label</span>$(ok_fail $V_LOGO)</div>
<div class="item"><span class="label">CPU 4-core</span>$(ok_fail $V_CPU)</div>
<div class="item"><span class="label">Fake off</span>$(ok_fail $V_FAKE)</div>
<div class="item"><span class="label">Real RAM</span>$(ok_fail $V_RAM)</div>
</div>

<div class="card">
<h2><span class="dim">&gt;</span>TELEMETRY_OFF</h2>
<div class="item"><span class="label">Statistics</span>$(ok_fail $V_STAT)</div>
<div class="item"><span class="label">IoT cloud</span>$(ok_fail $V_IOT)</div>
<div class="item"><span class="label">APR upload</span>$(ok_fail $V_APR)</div>
<div class="item"><span class="label">Heartbeat</span>$(ok_fail $V_HB)</div>
<div class="item"><span class="label">BS service</span>$(ok_fail $V_BS)</div>
</div>

<div class="card">
<h2><span class="dim">&gt;</span>BIOMETRIC_OFF</h2>
<div class="item"><span class="label">Fingerprint</span>$(ok_fail $V_FP)</div>
<div class="item"><span class="label">Face unlock</span>$(ok_fail $V_FACE)</div>
</div>

<div class="card">
<h2><span class="dim">&gt;</span>FEATURES_ON</h2>
<div class="item"><span class="label">Camera refocus</span>$(ok_fail $V_REFOCUS)</div>
<div class="item"><span class="label">Double-tap recents</span>$(ok_fail $V_DBL)</div>
<div class="item"><span class="label">Lock wallpaper</span>$(ok_fail $V_LOCK)</div>
</div>

<div class="card">
<h2><span class="dim">&gt;</span>DEX2OAT_4CORE</h2>
<div class="item"><span class="label">Threads</span><span class="value">$DEX_THREADS</span></div>
<div class="item"><span class="label">CPU set</span><span class="value">$DEX_CPUSET</span></div>
<div class="item"><span class="label">correct</span>$([ "$DEX_CPUSET" = "0,1,2,3" ] && echo '<span class="value ok">[OK]</span>' || echo '<span class="value fail">[NG]</span>')</div>
</div>

<div class="card">
<h2><span class="dim">&gt;</span>TCP_TUNING</h2>
<div class="item"><span class="label">rmem_max</span><span class="value">$TCP_RMEM</span></div>
<div class="item"><span class="label">wmem_max</span><span class="value">$TCP_WMEM</span></div>
<div class="item"><span class="label">congestion</span><span class="value">$TCP_CC</span></div>
<div class="item"><span class="label">rwnd</span>$(ok_fail $V_RWND)</div>
</div>

<div class="card">
<h2><span class="dim">&gt;</span>KERNEL</h2>
<div class="item"><span class="label">resampler</span>$(ok_fail $V_RESAMPLE)</div>
<div class="item"><span class="label">swappiness</span><span class="value">$SWAPPINESS</span></div>
<div class="item"><span class="label">i/o sched</span><span class="value">$IO_SHOW</span></div>
<div class="item"><span class="label">mem</span><span class="value">${MEM_AVAIL}/${MEM_TOTAL} MB</span></div>
</div>

<div class="card">
<h2><span class="dim">&gt;</span>ANDROID_GO</h2>
<div class="item"><span class="label">low_ram</span><span class="value">$GO_SHOW</span></div>
<div class="item"><span class="label">threshold</span><span class="value">$GO_THRESHOLD</span></div>
</div>

<div class="card">
<h2><span class="dim">&gt;</span>CHARGING</h2>
<div class="item"><span class="label">ZRAM off</span>$(ok_fail $V_ZRAM)</div>
<div class="item"><span class="label">input_limit</span><span class="value">${CHG_LIMIT_VAL:-?} mA</span></div>
<div class="item"><span class="label">ac_max</span><span class="value">${CHG_AC_VAL:-?} mA</span></div>
</div>

<div class="card">
<h2><span class="dim">&gt;</span>SF_PARAMS</h2>
<div class="item"><span class="label">bp restored</span>$(ok_fail $V_SF_BP)</div>
<div class="item"><span class="label">latch restored</span>$(ok_fail $V_SF_LATCH)</div>
</div>

<div class="card">
<h2><span class="dim">&gt;</span>WEAR_OS</h2>
<div class="item"><span class="label">wearable.jar</span>$(ok_fail $V_WJ)</div>
<div class="item"><span class="label">wear-service.jar</span>$(ok_fail $V_WS)</div>
<div class="item"><span class="label">permissions xml</span>$(ok_fail $V_WX)</div>
</div>

<div class="card">
<h2><span class="dim">&gt;</span>GITHUB_ACCEL</h2>
<div class="item"><span class="label">hosts</span>$(ok_fail $V_GH)</div>
<div class="item"><span class="label">dns guardian</span>$(ok_fail $V_DNS)</div>
<div class="item"><span class="label">github ip</span><span class="value">${GH_IP:-?}</span></div>
</div>

<div class="card">
<h2><span class="dim">&gt;</span>ANIMATION</h2>
<div class="item"><span class="label">window</span><span class="value">${ANIM_WIN:-?}x</span></div>
<div class="item"><span class="label">transition</span><span class="value">${ANIM_TRANS:-?}x</span></div>
<div class="item"><span class="label">duration</span><span class="value">${ANIM_DUR:-?}x</span></div>
</div>

<div class="card">
<h2><span class="dim">&gt;</span>BATTERY</h2>
<div class="item"><span class="label">level</span><span class="value big">${CAP:-?}%</span></div>
<div class="item"><span class="label">current</span><span class="value">${CUR_SHOW}</span></div>
<div class="item"><span class="label">temp</span><span class="value">${BATT_TEMP} °C</span></div>
<div class="item"><span class="label">health</span><span class="value">${BATT_HEALTH}</span></div>
<div class="item"><span class="label">status</span><span class="value">${BATT_STATUS}</span></div>
</div>

<footer>
<span class="dim">──</span> snapshot @ $(date "+%H:%M:%S") <span class="dim">──</span>
</footer>

</div>
</body>
</html>
HTMLEOF

mv "$TMP" "$OUT"
chmod 644 "$OUT" 2>/dev/null

exit 0