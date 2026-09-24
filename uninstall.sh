#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════════════════
#  uninstall.sh —— 卸载清理
#  ---------------------------------------------------------------------------
#  为什么卸载还要专门写个脚本：persist.* 一旦被 resetprop 写过，就落盘进了
#  /data/property/persistent_properties。删掉模块目录**不会**把那些值删掉，
#  虚标会一半留一半 —— 那才叫真的脏。所以这里逐个清掉。
#
#  另外顺手收拾自己起的后台进程和状态文件，别留一堆孤儿。
# ═══════════════════════════════════════════════════════════════════════════

MODDIR="${MODDIR:-${0%/*}}"
[ -d "$MODDIR" ] || MODDIR="/data/adb/modules/SL8541E_Config_Fix"

LOG="/sdcard/SL8541E_uninstall.log"
touch "$LOG" 2>/dev/null

echo "════════════════════════════════════════" >> "$LOG"
echo "开始卸载 $(date)" >> "$LOG"

# ── 要清的属性：凡是模块写过的 persist.* / 非 ro 属性 ──
#   直接从 prop.list 里抓，避免"加了属性忘了加这里"。
PERSIST_PROPS=""
if [ -f "$MODDIR/lib/prop.list" ]; then
    PERSIST_PROPS=$(grep -v '^#' "$MODDIR/lib/prop.list" 2>/dev/null \
        | cut -d'|' -f2 | tr -d ' \t' | grep -E '^persist\.' )
fi

# prop.list 丢了也要能清干净 —— 这份是兜底硬编码
PERSIST_PROPS="$PERSIST_PROPS
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
persist.logd.size.events"

EXTRA_PROPS="heils.facelock ro.config.zram.support"

DELETED=0
SKIPPED=0

remove_prop() {
    _p="$1"
    # 先看还在不在：不在的算"跳过"，不该报成功，也不该报错
    _cur=$(getprop "$_p" 2>/dev/null)
    if [ -z "$_cur" ]; then
        SKIPPED=$((SKIPPED + 1))
        return 0
    fi
    resetprop --delete "$_p" 2>/dev/null
    if [ -z "$(getprop "$_p" 2>/dev/null)" ]; then
        DELETED=$((DELETED + 1))
        echo "  ✅ 已清除 $_p（原值 $_cur）" >> "$LOG"
    else
        SKIPPED=$((SKIPPED + 1))
        echo "  ⚠ 清除失败 $_p（仍为 $_cur）" >> "$LOG"
    fi
}

# 去重后逐个清（prop.list 与兜底清单会重叠）
for p in $(echo "$PERSIST_PROPS $EXTRA_PROPS" | tr ' ' '\n' | grep -v '^$' | sort -u); do
    remove_prop "$p"
done

# ── 收拾自己起的后台进程和状态文件 ──
PIDFILE="$MODDIR/.dnsguard.pid"
if [ -f "$PIDFILE" ]; then
    _pid=$(cat "$PIDFILE" 2>/dev/null | tr -d ' \n')
    if [ -n "$_pid" ] && [ -d "/proc/$_pid" ]; then
        kill "$_pid" 2>/dev/null
        echo "  ✅ 已停止 DNS 守护（pid $_pid）" >> "$LOG"
    fi
fi
rm -f "$PIDFILE" "$MODDIR/.run.lock" "$MODDIR/.run" 2>/dev/null
rm -f "$MODDIR/webroot/status_generated.html" "$MODDIR/webroot/status_generated.html.tmp" 2>/dev/null

echo "" >> "$LOG"
echo "清理完成：清除 $DELETED 项，跳过 $SKIPPED 项" >> "$LOG"
echo "（跳过 = 本来就没被写过，属正常）" >> "$LOG"
echo "════════════════════════════════════════" >> "$LOG"

exit 0
