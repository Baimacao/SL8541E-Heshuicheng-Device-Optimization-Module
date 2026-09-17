#!/system/bin/sh

MODDIR="${MODDIR:-${0%/*}}"
[ ! -d "$MODDIR" ] && MODDIR="/data/adb/modules/SL8541E_Config_Fix"

# ═══════════════════════════════════════
# 定位 BusyBox（APatch 自带，提供 awk）
# ═══════════════════════════════════════
BUSYBOX=""
for p in /data/adb/ap/bin/busybox /data/adb/magisk/busybox /system/bin/busybox /system/xbin/busybox; do
    [ -x "$p" ] && { BUSYBOX="$p"; break; }
done

if [ -n "$BUSYBOX" ]; then
    AWK="$BUSYBOX awk"
else
    AWK="awk"
fi

# ═══════════════════════════════════════
# 震动反馈
# ═══════════════════════════════════════
vibrate() {
    if [ -e /sys/class/timed_output/vibrator/enable ]; then
        echo 150 > /sys/class/timed_output/vibrator/enable 2>/dev/null
        return
    fi
    if [ -e /sys/class/leds/vibrator/brightness ]; then
        echo 1 > /sys/class/leds/vibrator/brightness 2>/dev/null
        sleep 0.2
        echo 0 > /sys/class/leds/vibrator/brightness 2>/dev/null
        return
    fi
    cmd vibrator vibrate 150 2>/dev/null
}
vibrate

# ═══════════════════════════════════════
# 属性检测
# ═══════════════════════════════════════
chk() {
    if [ "$(getprop "$1")" = "$2" ]; then
        echo "已生效 ✓"
    else
        echo "未生效 ✗"
    fi
}

# ═══════════════════════════════════════
# Settings 读值（内存优先，XML 兜底）
# ═══════════════════════════════════════
SETTINGS_XMLS="
/data/system/users/0/settings_global.xml
/data/system/settings_global.xml
"

xml_get() {
    for xml in $SETTINGS_XMLS; do
        [ -f "$xml" ] || continue
        val=$(grep -o "name=\"$1\"[^/]*" "$xml" 2>/dev/null | \
              grep -o 'value="[^"]*"' | head -1 | \
              sed 's/value="//;s/"$//')
        [ -n "$val" ] && { echo "$val"; return; }
    done
    echo ""
}

sget() {
    out=$(settings get global "$1" 2>/dev/null)
    case "$out" in
        *"Failure"*|*"cmd:"*|*"Error"*|"null"|"") ;;
        *) echo "$out"; return ;;
    esac
    xml_get "$1"
}

# ═══════════════════════════════════════
# 动画检测（纯 shell 浮点近似比较，无 awk）
# ═══════════════════════════════════════
chk_anim() {
    key="$1"; exp="$2"
    cur=$(sget "$key")
    [ -z "$cur" ] && { echo "读不到值 ✗"; return; }

    # 精确字符串匹配
    [ "$cur" = "$exp" ] && { echo "已生效 ✓"; return; }

    # 数值近似：乘以 1000 转整数比较，容差 1 (即 0.001)
    cur_i=$(echo "$cur" | sed 's/\.//')
    exp_i=$(echo "$exp" | sed 's/\.//')
    # 补齐到相同位数
    while [ ${#cur_i} -lt ${#exp_i} ]; do cur_i="${cur_i}0"; done
    while [ ${#exp_i} -lt ${#cur_i} ]; do exp_i="${exp_i}0"; done

    diff=$((cur_i - exp_i))
    [ $diff -lt 0 ] && diff=$((0 - diff))

    if [ $diff -le 1 ]; then
        echo "已生效 ✓"
    else
        echo "未生效 ✗ (当前 $cur)"
    fi
}

DEV=$(sget development_settings_enabled)
[ "$DEV" = "1" ] && S_DEV="已生效 ✓" || S_DEV="未生效 ✗ (值=${DEV:-空})"

# ═══════════════════════════════════════
# 电池信息
# ═══════════════════════════════════════
BATT_DIRS="/sys/class/power_supply/battery /sys/class/power_supply/sprdbattery /sys/class/power_supply/BAT0"

find_node() {
    for d in $BATT_DIRS; do
        [ -e "$d/$1" ] && { echo "$d/$1"; return; }
    done
    echo ""
}
read_node() {
    p=$(find_node "$1")
    [ -z "$p" ] && return
    cat "$p" 2>/dev/null | tr -d ' \r\n'
}
tr_health() {
    case "$1" in
        Good) echo "良好" ;;
        Overheat) echo "过热" ;;
        Dead) echo "损坏" ;;
        "") echo "未知" ;;
        *) echo "$1" ;;
    esac
}
tr_status() {
    case "$1" in
        Charging) echo "充电中" ;;
        Discharging) echo "放电中" ;;
        Full) echo "已充满" ;;
        Not\ charging) echo "未充电" ;;
        "") echo "未知" ;;
        *) echo "$1" ;;
    esac
}

# 格式化电压（纯 shell 整数运算）
fmt_voltage() {
    v="$1"
    [ -z "$v" ] && { echo "未知"; return; }
    if [ "$v" -gt 100000 ] 2>/dev/null; then
        # 微伏 -> 伏特
        volt=$((v / 1000000))
        frac=$(((v % 1000000) / 10000))
        printf "%d.%02d V" "$volt" "$frac"
    elif [ "$v" -gt 1000 ] 2>/dev/null; then
        # 毫伏 -> 伏特
        volt=$((v / 1000))
        frac=$(((v % 1000) / 10))
        printf "%d.%02d V" "$volt" "$frac"
    else
        echo "${v} mV"
    fi
}

# 格式化电流（纯 shell 整数运算）
fmt_current() {
    c="$1"
    [ -z "$c" ] && { echo "未知"; return; }
    if [ "$c" -lt 0 ] 2>/dev/null; then
        d="放电 "; c=$((0 - c))
    else
        d="充电 "
    fi
    if [ "$c" -gt 10000 ] 2>/dev/null; then
        printf "%s%d mA" "$d" $((c / 1000))
    else
        printf "%s%d mA" "$d" "$c"
    fi
}

# 格式化温度（纯 shell 整数运算）
fmt_temp() {
    t="$1"
    [ -z "$t" ] && { echo "未知"; return; }
    deg=$((t / 10))
    frac=$((t % 10))
    printf "%d.%d °C" "$deg" "$frac"
}

CAP=$(read_node capacity)
VOL=$(read_node voltage_now)
CUR=$(read_node current_now)
TMP=$(read_node temp)
HLT=$(read_node health)
STS=$(read_node status)

TMP_RAW=$((TMP / 10))
WARN=""
[ "$TMP_RAW" -gt 45 ] 2>/dev/null && WARN="  ⚠ 温度偏高，建议歇一会儿"

# ═══════════════════════════════════════
# 输出
# ═══════════════════════════════════════
echo "【优化模块 · 状态检测】"
echo "大肥鱼正在扫描…… 咕噜咕噜"
echo "──────────────────"
echo "5G假图标关闭：   $(chk persist.sys.5g false)"
echo "状态栏4G：       $(chk persist.sys.logo 4G)"
echo "CPU显示4核：     $(chk persist.sys.cpu 4)"
echo "虚标开关关闭：   $(chk persist.sys.rom.fake 0)"
echo "真实内存显示：   $(chk persist.sys.isshowrealram 1)"
echo "指纹功能关闭：   $(chk persist.support.fingerprint false)"
echo "人脸功能关闭：   $(chk heils.facelock 0)"
echo "相机重对焦开启： $(chk persist.sys.cam.refocus.enable true)"
echo "双击打开后台：   $(chk ro.config.f14_double_click_recent_tasks true)"
echo "锁屏壁纸开启：   $(chk ro.lockwallpaper.enable true)"
echo "开发者选项：     $S_DEV"
echo "──────────────────"
echo "云控/上传关闭："
echo "  统计上报：     $(chk ro.hsc.statistics false)"
echo "  IoT 云控：     $(chk ro.hsc.iot false)"
echo "  APR 自动上传： $(chk persist.sys.apr.autoupload 0)"
echo "  心跳上报：     $(chk persist.sys.heartbeat.enable 0)"
echo "  BS 服务：      $(chk persist.sys.bsservice.enable 0)"
echo "──────────────────"
echo "dex2oat 4 核（修正 CPU set）："
echo "  编译线程：     $(chk dalvik.vm.dex2oat-threads 4)"
echo "  镜像线程：     $(chk dalvik.vm.image-dex2oat-threads 4)"
echo "  CPU set：      $(getprop dalvik.vm.dex2oat-cpu-set)"
echo "  set 正确：     $([ "$(getprop dalvik.vm.dex2oat-cpu-set)" = "0,1,2,3" ] && echo '已生效 ✓' || echo '未生效 ✗')"
echo "──────────────────"
echo "TCP 优化："
echo "  rmem_max：     $(cat /proc/sys/net/core/rmem_max 2>/dev/null)"
echo "  wmem_max：     $(cat /proc/sys/net/core/wmem_max 2>/dev/null)"
echo "  拥塞算法：     $(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)"
echo "  rwnd 属性：    $(chk net.tcp.default_init_rwnd 256)"
echo "──────────────────"
echo "音频/内核低抖动："
echo "  重采样质量：   $(chk af.resampler.quality 4)"
echo "  swappiness：   $(cat /proc/sys/vm/swappiness 2>/dev/null)"
IO_RAW=$(cat /sys/block/mmcblk0/queue/scheduler 2>/dev/null)
IO_SEL=$(echo "$IO_RAW" | grep -o '\[[a-z]*\]' | tr -d '[]')
IO_SHOW=$(echo "$IO_RAW" | sed 's/\[/【/;s/\]/】/')
echo "  I/O 调度：     $IO_SHOW"
[ "$IO_SEL" = "noop" ] && echo "  I/O 生效：     已生效 ✓" || echo "  I/O 生效：     未生效 ✗ (当前 $IO_SEL)"
echo "──────────────────"
echo "Wear OS 库："
WEAR_OK=1
for f in \
    /system/framework/com.google.android.wearable.jar \
    /system/framework/wear-service.jar \
    /system/etc/permissions/com.google.android.wearable.xml; do
    name=$(basename "$f")
    if [ -f "$f" ]; then
        # 用 ls -l 替代 stat -c，兼容 toybox
        perm=$(ls -l "$f" 2>/dev/null | cut -c1-10)
        if [ -n "$perm" ]; then
            echo "  $name：已挂载 ✓"
        else
            echo "  $name：权限读取失败 ⚠"
            WEAR_OK=0
        fi
    else
        echo "  $name：未挂载 ✗"
        WEAR_OK=0
    fi
done
WEAR_FEAT=$(pm list features 2>/dev/null | grep -iE "wearable|watch" | head -1)
WEAR_LIB=$(pm list libraries 2>/dev/null | grep -iE "wearable|wear" | head -1)
if [ -n "$WEAR_FEAT" ]; then
    echo "  系统 feature： 已识别 ✓"
elif [ -n "$WEAR_LIB" ]; then
    echo "  系统 library： 已识别 ✓"
else
    echo "  系统识别：     未见 feature/library"
    echo "                 （若 App 能调用 Wear API 则实际已生效）"
fi
[ "$WEAR_OK" = "1" ] && echo "  总体状态：     全部就绪 ✓" || echo "  总体状态：     有缺失 ✗"
echo "──────────────────"
echo "动画修复："
echo "  窗口 0.75：    $(chk_anim window_animation_scale 0.75)"
echo "  过渡 0.75：    $(chk_anim transition_animation_scale 0.75)"
echo "  时长 0.5：     $(chk_anim animator_duration_scale 0.5)"
echo "──────────────────"
echo "🔋 电池状态"
echo "  电量：  ${CAP:-未知}%"
echo "  电压：  $(fmt_voltage "$VOL")"
echo "  电流：  $(fmt_current "$CUR")"
echo "  温度：  $(fmt_temp "$TMP")$WARN"
echo "  健康：  $(tr_health "$HLT")"
echo "  状态：  $(tr_status "$STS")"
echo "──────────────────"
echo "扫描完毕，大肥鱼表示很满意 🐟"
echo "仅和顺成方案可用"