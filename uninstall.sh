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

# ── 要清的属性：凡是模块写过的 persist.* ──
#   直接从 prop.list 里抓，避免"加了属性忘了加这里"。
#   prop.list 列序： scope | key | variant | value | 说明
#   按变体过滤：通用包没写过 hsc 专属属性，就不该去删它们。
VARIANT="hsc"
[ -f "$MODDIR/lib/variant" ] && VARIANT=$(cat "$MODDIR/lib/variant" 2>/dev/null | tr -d ' \r\n')
[ -n "$VARIANT" ] || VARIANT="hsc"
echo "包型：$VARIANT" >> "$LOG"

PERSIST_PROPS=""
if [ -f "$MODDIR/lib/prop.list" ]; then
    # ⚠ 本机玩具箱（toybox）没有 awk，纯 shell 过滤，别改回 awk
    while IFS='|' read -r _s _k _var _v _n; do
        case "$_s" in ''|\#*) continue ;; esac
        _k=$(echo "$_k" | tr -d ' \t')
        case "$_k" in persist.*) ;; *) continue ;; esac
        if [ "$_var" = "hsc" ] && [ "$VARIANT" != "hsc" ]; then continue; fi
        PERSIST_PROPS="$PERSIST_PROPS $_k"
    done < "$MODDIR/lib/prop.list"
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

# ── 还原开机时改过的设置项（开发者选项 / USB 调试）──
#   模块在 service.sh 里打开这两个开关，并把**原值**记在 .orig-settings。
#   不还原的话，卸载后 USB 调试会一直开着 —— 独立审计专门指出了这一条。
#
#   三种情况：
#     原值为空（当时根本没这个键）→ 删掉它
#     原值是 0/其它               → 写回原值
#     原值本来就是 1              → 用户自己开的，保持不动
ORIG_SETTINGS="$MODDIR/.orig-settings"
if [ -f "$ORIG_SETTINGS" ]; then
    while IFS='=' read -r _k _v; do
        case "$_k" in ''|\#*) continue ;; esac
        [ -n "$_k" ] || continue
        if [ -z "$_v" ]; then
            settings delete global "$_k" 2>/dev/null
            echo "  ✅ 已删除设置 $_k（原本不存在）" >> "$LOG"
        elif [ "$_v" = "1" ]; then
            echo "  · 设置 $_k 原本就是 1，保持不动" >> "$LOG"
        else
            settings put global "$_k" "$_v" 2>/dev/null
            echo "  ✅ 已还原设置 $_k=$_v" >> "$LOG"
        fi
    done < "$ORIG_SETTINGS"
    rm -f "$ORIG_SETTINGS" 2>/dev/null
fi

# ── 收拾自己起的后台进程和状态文件 ──
#   两个常驻进程都要收：DNS 守护 + 充电复写循环。
#   充电那个如果不收，卸载后它会继续跑满 20 轮（约 10 分钟）才自己退出。
for _pf in "$MODDIR/.dnsguard.pid" "$MODDIR/.charge-keepalive.pid"; do
    [ -f "$_pf" ] || continue
    _pid=$(cat "$_pf" 2>/dev/null | tr -d ' \n')
    if [ -n "$_pid" ] && [ -d "/proc/$_pid" ]; then
        kill "$_pid" 2>/dev/null
        echo "  ✅ 已停止后台进程（pid $_pid）：$(basename "$_pf")" >> "$LOG"
    fi
    rm -f "$_pf" 2>/dev/null
done
rm -f "$MODDIR/.run.lock" "$MODDIR/.run" 2>/dev/null
rm -f "$MODDIR/webroot/status_generated.html" "$MODDIR/webroot/status_generated.html.tmp" 2>/dev/null

echo "" >> "$LOG"
echo "清理完成：清除 $DELETED 项，跳过 $SKIPPED 项" >> "$LOG"
echo "（跳过 = 本来就没被写过，属正常）" >> "$LOG"
echo "════════════════════════════════════════" >> "$LOG"

exit 0
