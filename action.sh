#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════════════════
#  action.sh —— 模块卡片上那个「操作」按钮
#  ---------------------------------------------------------------------------
#  在 APatch / KernelSU / Magisk 里，这个按钮的 stdout 会直接弹给用户，
#  所以这里只做两件事：**刷新一下 WebUI 状态页**，再**吐一份人看的纯文本体检报告**。
#
#  两条纪律（都是踩出来的）：
#    1. settings 在这个上下文里大概连不上 system_server，读值一律走
#       settings_get()，它自己会退到 XML。
#    2. 读不到值必须显示"未知"，不许显示空 —— 空行会让人以为模块没生效。
# ═══════════════════════════════════════════════════════════════════════════

MODDIR="${MODDIR:-${0%/*}}"
[ -d "$MODDIR" ] || MODDIR="/data/adb/modules/SL8541E_Config_Fix"

# shellcheck source=lib/common.sh
. "$MODDIR/lib/common.sh"

# ── 先看有没有更新（根管理器基本不给按钮传参，所以 install 只能靠
#    `sh action.sh install` 手动触发，见 README 的"手动更新"一节）──
UPD=$(sh "$MODDIR/lib/install.sh" "${1:-check}" 2>/dev/null)
UPD_STATUS=$(echo "$UPD" | grep '^STATUS=' | cut -d= -f2)
UPD_RESULT=$(echo "$UPD" | grep '^RESULT=' | cut -d= -f2)
UPD_REMOTE=$(echo "$UPD" | grep '^REMOTE=' | cut -d= -f2)

case "$UPD_STATUS" in
    newer)  UPD_LINE="有新版本 v$UPD_REMOTE 🆕" ;;
    same)   UPD_LINE="已是最新 ✓" ;;
    ahead)  UPD_LINE="本地比远端新（自编包）" ;;
    error)  UPD_LINE="检查失败（网络/被墙）" ;;
    *)      UPD_LINE="未检查" ;;
esac
case "$UPD_RESULT" in
    need_confirm)     UPD_LINE="$UPD_LINE → 再点一次「操作」即安装" ;;
    installed)        UPD_LINE="✅ 已安装 v$UPD_REMOTE，重启后生效" ;;
    installed_apatch) UPD_LINE="✅ 已装 v$UPD_REMOTE（APatch 目录级兜底），重启后生效" ;;
    manual_needed)    UPD_LINE="已下载 v$UPD_REMOTE，需去管理器手动安装" ;;
    download_failed)  UPD_LINE="$UPD_LINE（下载失败）" ;;
    bad_download|bad_package) UPD_LINE="$UPD_LINE（包校验失败，已丢弃）" ;;
esac

# ── 顺手刷新状态页（WebUI 的「状态」Tab 读的就是它）──
[ -f "$MODDIR/webroot/gen_status.sh" ] && sh "$MODDIR/webroot/gen_status.sh" 2>/dev/null

# ── 震动反馈：三套节点挨个试 ──
#   这表不同批次走的振动节点不一样，全试一遍最省事。
vibrate() {
    if [ -e /sys/class/timed_output/vibrator/enable ]; then
        echo 150 > /sys/class/timed_output/vibrator/enable 2>/dev/null
        return 0
    fi
    if [ -e /sys/class/leds/vibrator/brightness ]; then
        echo 1 > /sys/class/leds/vibrator/brightness 2>/dev/null
        sleep 0.2
        echo 0 > /sys/class/leds/vibrator/brightness 2>/dev/null
        return 0
    fi
    cmd vibrator vibrate 150 2>/dev/null
}
vibrate

# ── 打印小工具 ──
ok_fail() { [ "$(chkv "$1" "$2")" = "1" ] && echo "已生效 ✓" || echo "未生效 ✗"; }

# 动画值比较：0.75 与 0.750 要算相等，所以折算成整数再比，容差 1 个刻度
anim_state() {
    _cur=$(settings_get "$1")
    [ -n "$_cur" ] || { echo "读不到值 ✗"; return; }
    [ "$_cur" = "$2" ] && { echo "已生效 ✓"; return; }
    _a=$(echo "$_cur" | sed 's/\.//'); _b=$(echo "$2" | sed 's/\.//')
    while [ ${#_a} -lt ${#_b} ]; do _a="${_a}0"; done
    while [ ${#_b} -lt ${#_a} ]; do _b="${_b}0"; done
    _d=$((_a - _b)); [ "$_d" -lt 0 ] && _d=$((0 - _d))
    [ "$_d" -le 1 ] && echo "已生效 ✓" || echo "未生效 ✗ (当前 $_cur)"
}

# ── 采集一次现场数据 ──
DEV_OPT=$(settings_get development_settings_enabled)
[ "$DEV_OPT" = "1" ] && S_DEV="已生效 ✓" || S_DEV="未生效 ✗ (值=${DEV_OPT:-空})"

MEM_TOTAL=$(grep MemTotal /proc/meminfo 2>/dev/null | tr -s ' ' | cut -d' ' -f2)
MEM_AVAIL=$(grep MemAvailable /proc/meminfo 2>/dev/null | tr -s ' ' | cut -d' ' -f2)
TOT_MB=""; AVAIL_MB=""
[ -n "$MEM_TOTAL" ] && TOT_MB=$((MEM_TOTAL / 1024))
[ -n "$MEM_AVAIL" ] && AVAIL_MB=$((MEM_AVAIL / 1024))

IO_RAW=$(cat /sys/block/mmcblk0/queue/scheduler 2>/dev/null)
IO_SEL=$(echo "$IO_RAW" | grep -o '\[[a-z]*\]' | tr -d '[]')
IO_SHOW=$(echo "$IO_RAW" | sed 's/\[/【/;s/\]/】/')

CHG_LIMIT=$(node_int /sys/devices/platform/battery/power_supply/battery/input_current_limit)
CHG_AC=$(node_int /sys/devices/platform/battery/power_supply/ac/current_max)
TEMP=$(batt_read temp)
TEMP_C=$(batt_temp_show "$TEMP")
TEMP_WARN=""
case "$TEMP" in
    ''|*[!0-9-]*) ;;
    *) [ "$((TEMP / 10))" -gt 45 ] 2>/dev/null && TEMP_WARN="  ⚠ 温度偏高，建议歇一会儿" ;;
esac

# ── 出报告 ──
echo "【SL8541E 优化模块 · 体检报告】"
echo "🐟 大肥鱼上线。别慌，我先看看这表还剩几口气。"
echo "   (˘ω˘) 女仆装已穿好，开始扫描"
echo "──────────────────"
echo "模块更新："
echo "  $(module_version) → $UPD_LINE"
[ -f "$MODDIR/update.state" ] && { echo "  上次检查：$(grep '^checked=' "$MODDIR/update.state" 2>/dev/null | cut -d= -f2)"; }
echo "──────────────────"
echo "虚标剥离："
echo "  5G假图标关闭：   $(ok_fail persist.sys.5g false)"
echo "  状态栏4G：       $(ok_fail persist.sys.logo 4G)"
echo "  CPU显示4核：     $(ok_fail persist.sys.cpu 4)"
echo "  虚标开关关闭：   $(ok_fail persist.sys.rom.fake 0)"
echo "  真实内存显示：   $(ok_fail persist.sys.isshowrealram 1)"
echo "──────────────────"
echo "云控 / 上报（全关才算数）："
echo "  统计上报：       $(ok_fail ro.hsc.statistics false)"
echo "  IoT 云控：       $(ok_fail ro.hsc.iot false)"
echo "  APR 自动上传：   $(ok_fail persist.sys.apr.autoupload 0)"
echo "  心跳上报：       $(ok_fail persist.sys.heartbeat.enable 0)"
echo "  BS 服务：        $(ok_fail persist.sys.bsservice.enable 0)"
echo "──────────────────"
echo "生物识别："
echo "  指纹关闭：       $(ok_fail persist.support.fingerprint false)"
echo "  人脸关闭：       $(ok_fail heils.facelock 0)"
echo "──────────────────"
echo "开着有用的："
echo "  相机重对焦：     $(ok_fail persist.sys.cam.refocus.enable true)"
echo "  双击打开后台：   $(ok_fail ro.config.f14_double_click_recent_tasks true)"
echo "  锁屏壁纸：       $(ok_fail ro.lockwallpaper.enable true)"
echo "  开发者选项：     $S_DEV"
echo "──────────────────"
echo "dex2oat 四核（原厂写成 4,5,6,7，这颗表只有 0~3）："
echo "  编译线程：       $(ok_fail dalvik.vm.dex2oat-threads 4)"
echo "  CPU set：        $(getprop dalvik.vm.dex2oat-cpu-set)"
echo "  set 正确：       $(ok_fail dalvik.vm.dex2oat-cpu-set 0,1,2,3)"
echo "──────────────────"
echo "网络："
echo "  rmem_max：       $(cat /proc/sys/net/core/rmem_max 2>/dev/null)"
echo "  wmem_max：       $(cat /proc/sys/net/core/wmem_max 2>/dev/null)"
echo "  拥塞算法：       $(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)"
echo "  rwnd 属性：      $(ok_fail net.tcp.default_init_rwnd 256)"
echo "  hosts 挂载：     $([ -f /system/etc/hosts ] && echo '在 ✓' || echo '不在 ✗')"
echo "  github.com IP：  $(grep -E '^[0-9.]+[[:space:]]+github\.com' /system/etc/hosts 2>/dev/null | head -1 | tr -s ' ' | cut -d' ' -f1)"
if [ -f "$MODDIR/.dnsguard.pid" ] && [ -d "/proc/$(cat "$MODDIR/.dnsguard.pid" 2>/dev/null | tr -d ' \n')" ]; then
    echo "  DNS 守护：       运行中 ✓"
else
    echo "  DNS 守护：       未运行 ✗"
fi
echo "──────────────────"
echo "内核 / 音频："
echo "  重采样质量：     $(ok_fail af.resampler.quality 4)"
echo "  swappiness：     $(cat /proc/sys/vm/swappiness 2>/dev/null)"
echo "  I/O 调度：       $IO_SHOW"
echo "  I/O 生效：       $([ "$IO_SEL" = noop ] && echo '已生效 ✓' || echo "未生效 ✗ (当前 $IO_SEL)")"
[ -n "$TOT_MB" ] && echo "  可用内存：       ${AVAIL_MB}MB / ${TOT_MB}MB"
echo "──────────────────"
echo "Android Go（原厂没开，仅供参考）："
echo "  低内存模式：     $(getprop ro.config.low_ram)"
echo "  内存阈值：       $(getprop ro.config.low_ram.threshold_gb)"
if [ -n "$TOT_MB" ] && [ "$TOT_MB" -lt 2048 ] 2>/dev/null && [ "$(getprop ro.config.low_ram)" != "true" ]; then
    echo "  建议：           内存 < 2GB，可以考虑 Go 模式"
fi
echo "──────────────────"
echo "充电（节点单位 µA，写 3000000 = 3A）："
if grep -q zram /proc/swaps 2>/dev/null; then
    echo "  ZRAM：          仍开着 ✗"
else
    echo "  ZRAM：          已关闭 ✓"
fi
[ -n "$CHG_LIMIT" ] && echo "  input_limit：   $((CHG_LIMIT / 1000)) mA"
[ -n "$CHG_AC" ] && echo "  ac_max：        $((CHG_AC / 1000)) mA"
echo "  ※ 实际上限取决于充电器：5V1A 约 890mA，电脑 USB 口锁死 500mA"
echo "──────────────────"
echo "动画 / 流畅度："
echo "  sf 背压：        $(ok_fail debug.sf.disable_backpressure 0)"
echo "  sf 同步：        $(ok_fail debug.sf.latch_unsignaled 0)"
echo "  UI FIFO：        $(ok_fail sys.use_fifo_ui 1)"
echo "  窗口 0.75：      $(anim_state window_animation_scale 0.75)"
echo "  过渡 0.75：      $(anim_state transition_animation_scale 0.75)"
echo "  时长 0.5：       $(anim_state animator_duration_scale 0.5)"
echo "──────────────────"
echo "Wear OS 库："
WEAR_OK=1
for f in /system/framework/com.google.android.wearable.jar \
         /system/framework/wear-service.jar \
         /system/etc/permissions/com.google.android.wearable.xml; do
    if [ -f "$f" ]; then
        echo "  $(basename "$f")：已挂载 ✓"
    else
        echo "  $(basename "$f")：未挂载 ✗"
        WEAR_OK=0
    fi
done
[ "$WEAR_OK" = "1" ] && echo "  总体：全部就绪 ✓" || echo "  总体：有缺失 ✗"
echo "──────────────────"
echo "🔋 电池"
echo "  电量：  $(batt_read capacity | sed 's/$/%/' | sed 's/^%$/未知/')"
echo "  电压：  $(batt_voltage_show "$(batt_read voltage_now)")"
echo "  电流：  $(batt_current_show "$(batt_read current_now)")"
echo "  温度：  ${TEMP_C} °C$TEMP_WARN"
echo "  健康：  $(batt_health_show "$(batt_read health)")"
echo "  状态：  $(batt_status_show "$(batt_read status)")"
echo "──────────────────"
echo "🐟 扫描完毕。这表的水平就这样了，能榨的都榨了。"
echo "   状态页已刷新，切过去看更省事。"
echo "   仅和顺成方案可用。"
exit 0
