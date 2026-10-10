#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════════════════
#  diag-anim.sh —— 动画"写进去却不生效"的取证
#  ---------------------------------------------------------------------------
#  用法（手表上，建议开机 2 分钟后再跑）：
#      su -c 'sh /data/adb/modules/SL8541E_Config_Fix/diag-anim.sh' > /sdcard/diag-anim.txt
#
#  要回答的问题：
#    报告读回是 0.75，但系统设置界面显示 1.0x —— 到底哪个是真的？
#
#  三个读数来源必须分开看：
#    ① settings get           → settings provider 的内存值（模块和报告读的就是它）
#    ② settings_global.xml    → 落盘的持久值（系统设置界面读的是它）
#    ③ dumpsys window         → WindowManager 实际用的值（决定动画快慢的真正的那个）
#  如果 ①=0.75 而 ②或③=1.0，就说明"写进了内存但没落盘/没被采用"。
# ═══════════════════════════════════════════════════════════════════════════

M="${MODDIR:-/data/adb/modules/SL8541E_Config_Fix}"
XML="/data/system/users/0/settings_global.xml"
[ -f "$XML" ] || XML="/data/system/settings_global.xml"

echo "=== 0. 环境 ==="
echo "时间:     $(date)"
echo "boot_completed: $(getprop sys.boot_completed)"
echo "开机时长: $(cut -d' ' -f1 /proc/uptime 2>/dev/null) 秒"
echo "模块版本: $(grep '^version=' $M/module.prop 2>/dev/null | cut -d= -f2)"
echo

echo "=== 1. 三个来源逐个读（每项读 3 次，看稳不稳）==="
for k in window_animation_scale transition_animation_scale animator_duration_scale; do
    echo "--- $k ---"
    printf '  ① settings get      : '
    for i in 1 2 3; do printf '[%s] ' "$(settings get global $k 2>&1)"; done
    echo
    printf '  ② settings_global.xml: '
    if [ -f "$XML" ]; then
        _x=$(grep -o "name=\"$k\" value=\"[^\"]*\"" "$XML" 2>/dev/null | head -1 | sed 's/.*value="//;s/"//')
        echo "[${_x:-未找到}]"
    else
        echo "[XML 不存在: $XML]"
    fi
    printf '  ③ dumpsys window     : '
    dumpsys window 2>/dev/null | grep -i "m${k%%_*}" | head -2 | tr -s ' ' | tr '\n' ' '
    echo
done
echo

echo "=== 2. settings_global.xml 的修改时间（判断有没有被重写）==="
if [ -f "$XML" ]; then
    ls -l "$XML" 2>/dev/null | tr -s ' '
    echo "  当前时间: $(date '+%Y-%m-%d %H:%M:%S')"
else
    echo "  XML 不存在，找找看："
    find /data/system -name 'settings*.xml' 2>/dev/null | head -10
fi
echo

echo "=== 3. 现在写一次，立刻连读 5 次（每次隔 2 秒），看会不会掉 ==="
echo "  写入: window=0.75 transition=0.75 animator=0.5"
settings put global window_animation_scale 0.75
settings put global transition_animation_scale 0.75
settings put global animator_duration_scale 0.5
_n=1
while [ "$_n" -le 5 ]; do
    echo "  第 $_n 次（+$(( (_n-1) * 2 ))秒）: $(settings get global window_animation_scale) / $(settings get global animator_duration_scale)"
    _n=$((_n + 1)); sleep 2
done
echo

echo "=== 4. 再等 30 秒看最终值 ==="
sleep 30
echo "  settings get : $(settings get global window_animation_scale) / $(settings get global animator_duration_scale)"
if [ -f "$XML" ]; then
    echo "  XML          : $(grep -o 'name="window_animation_scale" value="[^"]*"' "$XML" 2>/dev/null | head -1 | sed 's/.*value="//;s/"//')"
fi
echo

echo "=== 5. 开发者选项 / transition 相关系统属性 ==="
for p in ro.config.low_ram persist.sys.animation ro.animation.scale debug.anim; do
    v=$(getprop "$p" 2>/dev/null)
    [ -n "$v" ] && echo "  $p = $v"
done
echo

echo "=== 6. 有没有别的东西在改它（看 settings provider 的日志）==="
logcat -d -t 200 2>/dev/null | grep -iE 'animation_scale|SettingsProvider' | tail -15
echo
echo "=== 取证结束 ==="
