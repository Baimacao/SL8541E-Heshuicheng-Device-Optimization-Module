#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════════════════
#  webroot/status.sh —— 状态取值（唯一事实来源）
#  ---------------------------------------------------------------------------
#  输出格式：  KEY|VALUE     每行一条
#      1 = 已生效   0 = 未生效   其他 = 原始值
#
#  为什么单独抽出来：v1.2 里 gen_status.sh（生成 HTML）和 action.sh（文本报告）
#  各自抄了一份取值逻辑，同一件事写两遍，改一处漏一处。现在两边都读这一份。
#
#  被 gen_status.sh 这样消费：
#      sh status.sh | while IFS='|' read -r k v; do ... done
# ═══════════════════════════════════════════════════════════════════════════

MODDIR="${MODDIR:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
[ -d "$MODDIR" ] || MODDIR="/data/adb/modules/SL8541E_Config_Fix"

# shellcheck source=../lib/common.sh
. "$MODDIR/lib/common.sh"

out() { echo "$1|$2"; }

out "VER" "$(module_version)"

# ── 更新状态（由 lib/install.sh check 写进 update.state）──
UPD_STATE="$MODDIR/update.state"
if [ -f "$UPD_STATE" ]; then
    out "UPD_STATUS"  "$(grep '^status=' "$UPD_STATE" 2>/dev/null | head -1 | cut -d= -f2)"
    out "UPD_REMOTE"  "$(grep '^remote=' "$UPD_STATE" 2>/dev/null | head -1 | cut -d= -f2)"
    out "UPD_CHECKED" "$(grep '^checked=' "$UPD_STATE" 2>/dev/null | head -1 | cut -d= -f2)"
else
    out "UPD_STATUS" "unknown"
fi

# ── 虚标剥离 ──
out "SPOOF_5G"    "$(chkv persist.sys.5g false)"
out "SPOOF_LOGO"  "$(chkv persist.sys.logo 4G)"
out "SPOOF_CPU"   "$(chkv persist.sys.cpu 4)"
out "SPOOF_FAKE"  "$(chkv persist.sys.rom.fake 0)"
out "SPOOF_RAM"   "$(chkv persist.sys.isshowrealram 1)"

# ── 云控 / 上报 ──
out "TEL_STAT" "$(chkv ro.hsc.statistics false)"
out "TEL_IOT"  "$(chkv ro.hsc.iot false)"
out "TEL_APR"  "$(chkv persist.sys.apr.autoupload 0)"
out "TEL_HB"   "$(chkv persist.sys.heartbeat.enable 0)"
out "TEL_BS"   "$(chkv persist.sys.bsservice.enable 0)"

# ── 生物识别 ──
out "BIO_FP"   "$(chkv persist.support.fingerprint false)"
out "BIO_FACE" "$(chkv heils.facelock 0)"

# ── 开着有用的 ──
out "FEAT_REFOCUS" "$(chkv persist.sys.cam.refocus.enable true)"
out "FEAT_DBLTAP"  "$(chkv ro.config.f14_double_click_recent_tasks true)"
out "FEAT_LOCKWP"  "$(chkv ro.lockwallpaper.enable true)"
[ "$(settings_get development_settings_enabled)" = "1" ] && out "FEAT_DEVOPT" "1" || out "FEAT_DEVOPT" "0"

# ── dex2oat ──
out "DEX_THREADS" "$(getprop dalvik.vm.dex2oat-threads)"
out "DEX_CPUSET"  "$(getprop dalvik.vm.dex2oat-cpu-set)"

# ── 网络 ──
out "NET_RMEM" "$(cat /proc/sys/net/core/rmem_max 2>/dev/null)"
out "NET_WMEM" "$(cat /proc/sys/net/core/wmem_max 2>/dev/null)"
out "NET_CC"   "$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)"
out "NET_RWND" "$(chkv net.tcp.default_init_rwnd 256)"
out "NET_HOSTS" "$([ -f /system/etc/hosts ] && echo 1 || echo 0)"
out "NET_GHIP"  "$(grep -E '^[0-9.]+[[:space:]]+github\.com' /system/etc/hosts 2>/dev/null | head -1 | tr -s ' ' | cut -d' ' -f1)"
if [ -f "$MODDIR/.dnsguard.pid" ] && [ -d "/proc/$(cat "$MODDIR/.dnsguard.pid" 2>/dev/null | tr -d ' \n')" ]; then
    out "NET_DNSGUARD" "1"
else
    out "NET_DNSGUARD" "0"
fi

# ── 内核 / 音频 ──
out "KRN_RESAMPLE" "$(chkv af.resampler.quality 4)"
out "KRN_SWAP"     "$(cat /proc/sys/vm/swappiness 2>/dev/null)"
IO_RAW=$(cat /sys/block/mmcblk0/queue/scheduler 2>/dev/null)
IO_SEL=$(echo "$IO_RAW" | grep -o '\[[a-z]*\]' | tr -d '[]')
out "KRN_IO_SEL" "$IO_SEL"
MEM_TOTAL=$(grep MemTotal /proc/meminfo 2>/dev/null | tr -s ' ' | cut -d' ' -f2)
MEM_AVAIL=$(grep MemAvailable /proc/meminfo 2>/dev/null | tr -s ' ' | cut -d' ' -f2)
[ -n "$MEM_TOTAL" ] && out "MEM_TOTAL" "$((MEM_TOTAL / 1024))"
[ -n "$MEM_AVAIL" ] && out "MEM_AVAIL" "$((MEM_AVAIL / 1024))"

# ── Android Go 信息（原厂没开，仅展示）──
out "GO_MODE" "$(getprop ro.config.low_ram)"
out "GO_THRESHOLD" "$(getprop ro.config.low_ram.threshold_gb)"

# ── 充电 / ZRAM ──
if grep -q zram /proc/swaps 2>/dev/null; then out "CHG_ZRAM" "0"; else out "CHG_ZRAM" "1"; fi
CHG_LIMIT=$(node_int /sys/devices/platform/battery/power_supply/battery/input_current_limit)
CHG_AC=$(node_int /sys/devices/platform/battery/power_supply/ac/current_max)
[ -n "$CHG_LIMIT" ] && out "CHG_LIMIT" "$((CHG_LIMIT / 1000))"
[ -n "$CHG_AC" ] && out "CHG_AC" "$((CHG_AC / 1000))"

# ── 图形 / 动画 ──
out "GFX_BP"    "$(chkv debug.sf.disable_backpressure 0)"
out "GFX_LATCH" "$(chkv debug.sf.latch_unsignaled 0)"
out "GFX_FIFO"  "$(chkv sys.use_fifo_ui 1)"
out "ANIM_WIN"   "$(settings_get window_animation_scale)"
out "ANIM_TRANS" "$(settings_get transition_animation_scale)"
out "ANIM_DUR"   "$(settings_get animator_duration_scale)"

# ── Wear OS ──
[ -f /system/framework/com.google.android.wearable.jar ] && out "WEAR_JAR" "1" || out "WEAR_JAR" "0"
[ -f /system/framework/wear-service.jar ] && out "WEAR_SVC" "1" || out "WEAR_SVC" "0"
[ -f /system/etc/permissions/com.google.android.wearable.xml ] && out "WEAR_XML" "1" || out "WEAR_XML" "0"

# ── 电池 ──
out "BATT_CAP" "$(batt_read capacity)"
out "BATT_VOLT" "$(batt_voltage_show "$(batt_read voltage_now)")"
out "BATT_CUR" "$(batt_current_show "$(batt_read current_now)")"
out "BATT_TEMP" "$(batt_temp_show "$(batt_read temp)")"
out "BATT_HEALTH" "$(batt_health_show "$(batt_read health)")"
out "BATT_STATUS" "$(batt_status_show "$(batt_read status)")"

exit 0
