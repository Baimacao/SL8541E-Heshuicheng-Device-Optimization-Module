#!/system/bin/sh

MODDIR="${MODDIR:-${0%/*}}"
[ ! -d "$MODDIR" ] && MODDIR="/data/adb/modules/SL8541E_Config_Fix"
LOG="$MODDIR/fix.log"

echo "[$(date)] 大肥鱼上岸，开始清理虚标海洋……" >> "$LOG"

# ─── 关闭虚标 ───
resetprop -n persist.sys.5g false
resetprop -n persist.sys.logo 4G
resetprop -n persist.sys.cpu 4
resetprop -n persist.sys.rom.fake 0
resetprop -n persist.sys.isshowrealram 1
resetprop -n persist.sys.android.version 8.1

# ─── 云控 / 上传全量关闭 ───
resetprop -n persist.sys.apr.enabled 0
resetprop -n persist.sys.apr.autoupload 0
resetprop -n persist.sys.apr.reportlevel 0
resetprop -n persist.sys.apr.intervaltime 0
resetprop -n persist.sys.apr.lifetime 0
resetprop -n persist.sys.apr.reload 0
resetprop -n persist.sys.apr.exceptionnode 0
resetprop -n persist.sys.bsservice.enable 0
resetprop -n persist.sys.heartbeat.enable 0
resetprop -n persist.sys.start_udpdatastall 0

# ─── 关闭指纹 / 人脸 ───
resetprop -n persist.support.fingerprint false
resetprop -n persist.sprd.fp.lockapp false
resetprop -n persist.sprd.fp.launchapp false
resetprop -n heils.facelock 0
resetprop -n persist.sys.cam.faceid.version 0

# ─── 相机重对焦 ───
resetprop -n persist.sys.cam.refocus.enable true

# ─── ro 属性二次保险 ───
resetprop ro.config.f14_double_click_recent_tasks true
resetprop ro.lockwallpaper.enable true

# ─── dex2oat（修正 CPU set）───
resetprop dalvik.vm.dex2oat-threads 4
resetprop dalvik.vm.image-dex2oat-threads 4
resetprop dalvik.vm.bg-dex2oat-threads 4
resetprop dalvik.vm.boot-dex2oat-threads 4
resetprop dalvik.vm.dex2oat-cpu-set 0,1,2,3
resetprop dalvik.vm.boot-dex2oat-cpu-set 0,1,2,3
resetprop dalvik.vm.background-dex2oat-cpu-set 0,1,2,3
resetprop dalvik.vm.default-dex2oat-cpu-set 0,1,2,3

# ─── TCP 属性 ───
resetprop net.tcp.default_init_rwnd 256

# ─── 动画底层参数 ───
resetprop debug.sf.disable_backpressure 0
resetprop debug.sf.latch_unsignaled 0

# ─── UI 实时优先级 ───
resetprop sys.use_fifo_ui 1

# ═══════════════════════════════════════
# 强制关闭 ZRAM
# ═══════════════════════════════════════
setprop ctl.stop zram 2>/dev/null
swapoff /dev/block/zram0 2>/dev/null
resetprop ro.config.zram.support false
echo "[$(date)] ZRAM 已强制关闭" >> "$LOG"

# ═══════════════════════════════════════
# 充电加速 3A（必须在开机早期写）
#   节点单位：µA
#   原厂 500000 = 500mA，目标 3000000 = 3000mA
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

echo "[$(date)] 虚标已被大鱼吃掉，收工摸鱼去 ~" >> "$LOG"