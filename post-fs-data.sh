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

# ═══════════════════════════════════════
# 清理电池校正文件
# ═══════════════════════════════════════
CLEANED=0
for f in \
    /data/system/batterystats.bin \
    /data/system/batterystats.bin.bak \
    /data/system/battery_stats.bin \
    /data/system/batterystats.bin.tmp; do
    [ -f "$f" ] && rm -f "$f" && CLEANED=$((CLEANED+1))
done

if [ "$CLEANED" -gt 0 ]; then
    echo "[$(date)] 电池旧账已清（$CLEANED 个文件），重新做人" >> "$LOG"
else
    echo "[$(date)] 电池校正文件本来就不在，无账可清" >> "$LOG"
fi

echo "[$(date)] 虚标已被大鱼吃掉，收工摸鱼去 ~" >> "$LOG"