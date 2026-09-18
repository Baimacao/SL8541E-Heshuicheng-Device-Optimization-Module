#!/system/bin/sh

MODDIR="${MODDIR:-${0%/*}}"
LOG="/sdcard/SL8541E_uninstall.log"
touch "$LOG" 2>/dev/null

echo "════════════════════════════════════════" >> "$LOG"
echo "开始卸载 $(date)" >> "$LOG"

PERSIST_PROPS="
persist.sys.5g
persist.sys.logo
persist.sys.cpu
persist.sys.rom.fake
persist.sys.isshowrealram
persist.sys.android.version
persist.sys.romSP
persist.sys.apr.enabled
persist.sys.apr.autoupload
persist.sys.apr.reportlevel
persist.sys.apr.intervaltime
persist.sys.apr.lifetime
persist.sys.apr.reload
persist.sys.apr.exceptionnode
persist.sys.bsservice.enable
persist.sys.heartbeat.enable
persist.sys.start_udpdatastall
persist.support.fingerprint
persist.sprd.fp.lockapp
persist.sprd.fp.launchapp
persist.sys.cam.faceid.version
persist.sys.cam.refocus.enable
persist.logd.logpersistd
persist.logd.size
persist.logd.size.crash
persist.logd.size.system
persist.logd.size.main
persist.logd.size.radio
persist.logd.size.events
"

EXTRA_PROPS="heils.facelock"

DELETED=0
FAILED=0

for p in $PERSIST_PROPS $EXTRA_PROPS; do
    resetprop --delete "$p" 2>/dev/null
    if [ $? -eq 0 ]; then
        DELETED=$((DELETED+1))
        echo "  ✅ 已清除 $p" >> "$LOG"
    else
        FAILED=$((FAILED+1))
        echo "  ⚠ 跳过 $p（可能不存在）" >> "$LOG"
    fi
done

resetprop --delete ro.config.zram.support 2>/dev/null

echo "" >> "$LOG"
echo "清除完成：成功 $DELETED 项，跳过 $FAILED 项" >> "$LOG"
echo "════════════════════════════════════════" >> "$LOG"

exit 0