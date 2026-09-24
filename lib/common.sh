#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════════════════
#  SL8541E 和顺成方案设备优化 · 公共库
#  ---------------------------------------------------------------------------
#  本文件不执行任何动作，只提供函数与常量。由下面几个入口脚本 source：
#      post-fs-data.sh   开机最早（属性 + 充电，节点还没上锁）
#      service.sh        开机完成后（二次保险 + sysctl + DNS 守护 + 设置项）
#      action.sh         用户点「操作」按钮
#      uninstall.sh      卸载
#      webroot/*.sh      WebUI 状态页
#
#  为什么要抽这一层：v1.2 里同一段属性写了三遍、充电块写了两遍、电池读取
#  与格式化抄了四份。改一个值要改四个文件，漏一个就是"这个设备上没生效"。
#  现在只留一份，属性清单在 prop.list（纯文本表，脚本解析）。
#
#  上古环境约束（改代码前先读这段）：
#    · toybox 没有 awk、没有 stat -c、没有 bc → 只用 shell 内建算术
#    · set -e 会让开机流程因为一个不存在的节点直接死掉 → 全篇不启用
#    · 所有外部命令都要 2>/dev/null 兜底，节点缺失属于正常情况
#    · 脚本一律 LF 行尾，sh 解释执行（不依赖可执行位）
# ═══════════════════════════════════════════════════════════════════════════

# ── 模块目录：优先用根管理器提供的 MODDIR/MODPATH，再退回脚本自身位置 ──
if [ -z "$MODDIR" ]; then
    if [ -n "$MODPATH" ]; then
        MODDIR="$MODPATH"
    elif [ -n "$0" ]; then
        MODDIR="${0%/*}"
    fi
fi
[ -d "$MODDIR" ] || MODDIR="/data/adb/modules/SL8541E_Config_Fix"

LIB="$MODDIR/lib"
PROP_LIST="$LIB/prop.list"
LOG="${FISH_LOG:-$MODDIR/fix.log}"
STATE="$MODDIR/.run"

# ── 日志：任何一句写不进去都不许中断开机 ──
fish_log() {
    echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$LOG" 2>/dev/null
}

# ── 属性写入 ──
# resetprop 是 Magisk/APatch/KernelSU 提供的（能改只读 ro.*、能删属性）；
# 没有它的时候退回系统自带的 setprop，功能打折但不至于整段失效。
HAS_RESETPROP=0
command -v resetprop >/dev/null 2>&1 && HAS_RESETPROP=1

# prop_set <key> <value>
#   读到旧值才写：resetprop -n 每次都会落盘 persistent_properties，
#   开机路径上无脑刷写等于白送 I/O。
prop_set() {
    _k="$1"; _v="$2"; _cur=""
    _cur=$(getprop "$_k" 2>/dev/null)
    [ "$_cur" = "$_v" ] && { prop_ok=$((prop_ok+1)); return 0; }

    if [ "$HAS_RESETPROP" = "1" ]; then
        resetprop -n "$_k" "$_v" 2>/dev/null
    else
        case "$_k" in
            ro.*) return 2 ;;                 # ro.* 只读，没 resetprop 就无解
            *)    setprop "$_k" "$_v" 2>/dev/null ;;
        esac
    fi

    [ "$(getprop "$_k" 2>/dev/null)" = "$_v" ] && { prop_ok=$((prop_ok+1)); return 0; }
    prop_bad=$((prop_bad+1))
    return 1
}

# prop_apply [scope...]
#   按 prop.list 批量写入；scope 是列1 的标签（core/service/action）。
#   不传 scope = 全写。用 while read 而不是 for，逐行处理不吃内存。
prop_apply() {
    _want="$*"
    [ -f "$PROP_LIST" ] || { fish_log "prop.list 不见了，属性全部跳过"; return 1; }
    prop_ok=0; prop_bad=0

    while IFS='|' read -r _kind _key _val _note; do
        case "$_kind" in ''|\#*) continue ;; esac
        _key=$(echo "$_key" | tr -d ' \t')
        [ -n "$_key" ] || continue

        if [ -n "$_want" ]; then
            _hit=0
            for _s in $_want; do [ "$_kind" = "$_s" ] && _hit=1; done
            [ "$_hit" = "1" ] || continue
        fi
        prop_set "$_key" "$_val"
    done < "$PROP_LIST"

    fish_log "属性清单：命中 $prop_ok 项，未生效 $prop_bad 项"
    return 0
}

# ── 数值读取（sysfs 会返回空串、带空格、甚至负数）──
# node_int <path>  → 干净整数；读不到则输出空串
node_int() {
    [ -e "$1" ] || return 1
    _raw=$(cat "$1" 2>/dev/null | tr -d ' \r\n\t')
    [ -n "$_raw" ] || return 1
    case "$_raw" in
        -*) _neg=1; _raw="${_raw#-}" ;;
        *)  _neg=0 ;;
    esac
    case "$_raw" in
        *[!0-9]*) return 1 ;;                 # 不是纯数字就别硬算
    esac
    if [ "$_neg" = "1" ]; then echo "-$_raw"; else echo "$_raw"; fi
}

# ── 充电节点 ──
# 单位是 µA：原厂 500000 = 500mA，我们写 3000000 = 3A。
# 只能在 post-fs-data 阶段写，开机完成后节点会被锁住（写了也不生效）。
CHG_TARGET=3000000
CHG_NODES="
/sys/devices/platform/battery/power_supply/ac/current_max
/sys/devices/platform/battery/power_supply/usb/current_max
/sys/devices/platform/battery/power_supply/battery/input_current_limit
/sys/devices/platform/battery/power_supply/battery/current_max
"

# charge_boost <标签>  → 回显一行"节点 = XµA (YmA)"摘要
charge_boost() {
    _tag="$1"; _hit=0; _summary=""
    for _n in $CHG_NODES; do
        [ -e "$_n" ] || continue
        echo "$CHG_TARGET" > "$_n" 2>/dev/null
        _raw=$(node_int "$_n")
        [ -n "$_raw" ] || continue
        _hit=$((_hit+1))
        _ma=$((_raw / 1000))
        _summary="$_summary $(basename "${_n%/*}")=$(echo "$_raw" | tr -d '\n')uA(${_ma}mA)"
    done
    fish_log "充电[$_tag]：命中 $_hit 个节点 →$_summary"
    echo "$_hit"
}

# ── 电池读取（三套可能的 sysfs 路径，挨个试）──
BATT_DIRS="/sys/class/power_supply/battery /sys/class/power_supply/sprdbattery /sys/class/power_supply/BAT0"

batt_node() {
    for _d in $BATT_DIRS; do
        [ -e "$_d/$1" ] && { echo "$_d/$1"; return 0; }
    done
    return 1
}

# batt_read <属性名> → 值（无则空串）
batt_read() {
    _p=$(batt_node "$1") || return 1
    node_int "$_p"
}

# batt_voltage_show <µV>   → "3.98 V"
batt_voltage_show() {
    _v="$1"
    [ -n "$_v" ] || { echo "未知"; return; }
    if [ "$_v" -gt 100000 ] 2>/dev/null; then
        echo "$((_v / 1000000)).$(printf '%02d' $(((_v % 1000000) / 10000))) V"
    elif [ "$_v" -gt 1000 ] 2>/dev/null; then
        echo "$((_v / 1000)).$(printf '%02d' $(((_v % 1000) / 10))) V"
    else
        echo "${_v} mV"
    fi
}

# batt_current_show <µA，负数=放电> → "充电 890 mA"
batt_current_show() {
    _c="$1"
    [ -n "$_c" ] || { echo "未知"; return; }
    if [ "$_c" -lt 0 ] 2>/dev/null; then
        echo "放电 $(( (0 - _c) / 1000 )) mA"
    else
        echo "充电 $((_c / 1000)) mA"
    fi
}

# batt_temp_show <0.1°C> → "36.5"   温度偏高时带一句提醒
#   45°C 是提醒线，不是温控线——本模块从头到尾没碰过展锐的温控阈值。
batt_temp_show() {
    _t="$1"
    [ -n "$_t" ] || { echo "未知"; return; }
    _d=$((_t / 10)); _f=$((_t % 10))
    [ "$_f" -lt 0 ] && _f=$((0 - _f))
    echo "${_d}.${_f}"
}

batt_health_show() {
    case "$1" in
        Good)     echo "良好" ;;
        Overheat) echo "过热" ;;
        Dead)     echo "损坏" ;;
        "")       echo "未知" ;;
        *)        echo "$1" ;;
    esac
}

batt_status_show() {
    case "$1" in
        Charging)     echo "充电中" ;;
        Discharging)  echo "放电中" ;;
        Full)         echo "已充满" ;;
        Not\ charging) echo "未充电" ;;
        "")           echo "未知" ;;
        *)            echo "$1" ;;
    esac
}

# ── 设置项：settings 命令在某些上下文连不上 system_server，改读 XML 兜底 ──
SETTINGS_XMLS="/data/system/users/0/settings_global.xml /data/system/settings_global.xml"

# xml_get <key> → value（读不到空串）
xml_get() {
    for _xml in $SETTINGS_XMLS; do
        [ -f "$_xml" ] || continue
        _val=$(grep -o "name=\"$1\"[^/]*" "$_xml" 2>/dev/null \
               | grep -o 'value="[^"]*"' | head -1 | sed 's/value="//;s/"$//')
        [ -n "$_val" ] && { echo "$_val"; return 0; }
    done
    return 1
}

# settings_get <key> → 先问 settings，失败再读 XML
#   注意 settings 失败时会吐出 "cmd: Failure calling service ..." 这种话，
#   直接当值用会把 UI 搞乱，所以要先过滤掉。
settings_get() {
    _out=$(settings get global "$1" 2>/dev/null)
    case "$_out" in
        *Failure*|*cmd:*|*Error*|*null|"") ;;
        *) echo "$_out"; return 0 ;;
    esac
    xml_get "$1"
}

# settings_put <key> <value> [重试次数]
#   写一次不放心：settings 与 XML 各验一次，最多重试 5 轮。
settings_put() {
    _key="$1"; _val="$2"; _try="${3:-5}"
    _i=1
    while [ "$_i" -le "$_try" ]; do
        settings put global "$_key" "$_val" 2>/dev/null
        [ "$(settings_get "$_key")" = "$_val" ] && return 0
        cmd settings put global "$_key" "$_val" 2>/dev/null
        [ "$(settings_get "$_key")" = "$_val" ] && return 0
        sleep 3
        _i=$((_i + 1))
    done
    return 1
}

# 直接改 XML（settings 完全失灵时的兜底路径）
settings_xml_force() {
    _key="$1"; _val="$2"
    _xml="$SETTINGS_XMLS"
    for _f in $_xml; do
        [ -f "$_f" ] || continue
        cp "$_f" "$_f.bak" 2>/dev/null
        if grep -q "name=\"$_key\"" "$_f" 2>/dev/null; then
            sed -i "s|name=\"$_key\" value=\"[^\"]*\"|name=\"$_key\" value=\"$_val\"|" "$_f" 2>/dev/null
        else
            sed -i "s|</settings>|<setting id=\"0\" name=\"$_key\" value=\"$_val\" package=\"android\" />\n</settings>|" "$_f" 2>/dev/null
        fi
    done
}

# ── 等开机完成 ──
wait_boot() {
    _n=0
    while [ "$(getprop sys.boot_completed 2>/dev/null)" != "1" ] && [ "$_n" -lt 60 ]; do
        sleep 2
        _n=$((_n + 1))
    done
    sleep 5
    fish_log "等开机完成用了 $((_n * 2)) 秒"
}

# ── 状态判定 ──
# chkv <key> <期望值> → 1/0
chkv() {
    [ "$(getprop "$1" 2>/dev/null)" = "$2" ] && echo 1 || echo 0
}

# ── 头图 ──
fish_banner() {
    echo "      ___"
    echo "     /   \\     SL8541E"
    echo "    | o o |    config_fix"
    echo "     \\___/     $(module_version)"
    echo "      |_|"
}

module_version() {
    if [ -f "$MODDIR/module.prop" ]; then
        grep '^version=' "$MODDIR/module.prop" 2>/dev/null | head -1 | cut -d= -f2
    else
        echo "?"
    fi
}

fish_log "lib/common.sh 已加载（resetprop=$HAS_RESETPROP）"
