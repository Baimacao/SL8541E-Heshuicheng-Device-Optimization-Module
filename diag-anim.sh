#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════════════════
#  diag-anim.sh v2 —— 动画"写进去却不生效"的取证
#  ---------------------------------------------------------------------------
#  用法（手表上）：
#      su -c 'sh /data/adb/modules/SL8541E_Config_Fix/diag-anim.sh' > /sdcard/diag-anim.txt
#
#  v1 已经查明的事实（2026-10-10）：
#    · `settings get global xxx` **全部失败**：Failed transaction (2147483646)
#    · 但 /data/system/users/0/settings_global.xml 里 **0.75 / 0.75 / 0.5 都在** ← 写成功了
#  所以本版重点回答：**四条读写路径里，哪几条能用？**
#    ① settings get/put          （传统命令，已知 get 失败）
#    ② cmd settings get/put      （另一条代码路径，模块里从没用过）
#    ③ settings_global.xml       （落盘文件，已知可读）
#    ④ settings list global      （列出全部，看键到底在不在）
# ═══════════════════════════════════════════════════════════════════════════

M="${MODDIR:-/data/adb/modules/SL8541E_Config_Fix}"
XMLS="/data/system/users/0/settings_global.xml /data/system/users/10/settings_global.xml /data/system/settings_global.xml"

xread() {  # xread <key> → 值@文件（从所有可能的 XML 里找）
    for x in $XMLS; do
        [ -f "$x" ] || continue
        v=$(grep -o "name=\"$1\"[^/]*" "$x" 2>/dev/null | grep -o 'value="[^"]*"' | head -1 | sed 's/value="//;s/"$//')
        [ -n "$v" ] && { echo "$v@$x"; return 0; }
    done
    return 1
}

echo "=== 0. 环境 ==="
echo "时间:     $(date)"
echo "boot_completed: $(getprop sys.boot_completed)"
echo "开机时长: $(cut -d' ' -f1 /proc/uptime 2>/dev/null) 秒"
echo "模块版本: $(grep '^version=' $M/module.prop 2>/dev/null | cut -d= -f2)"
echo "当前 uid: $(id -u 2>/dev/null)"
echo

echo "=== 1. 四条读取路径逐个试（本版重点）==="
for k in window_animation_scale animator_duration_scale; do
    echo "--- $k ---"
    printf '  ① settings get      : %s\n' "$(settings get global $k 2>&1 | head -1)"
    printf '  ② cmd settings get  : %s\n' "$(cmd settings get global $k 2>&1 | head -1)"
    printf '  ③ XML 落盘值        : %s\n' "$(xread $k 2>/dev/null || echo 未找到)"
    printf '  ④ settings list 命中: %s 条\n' "$(settings list global 2>/dev/null | grep -c "$k")"
done
echo

echo "=== 2. XML 分布在哪些用户目录 ==="
ls -l /data/system/users/*/settings_global.xml 2>/dev/null | tr -s ' '
echo

echo "=== 3. 关键测试：命令路径能否触发一次「值的变化」（动画靠这个激活）==="
echo "  机制：手表要检测到【调整】这个动作才激活动画，不是单纯给值。"
echo "        settings put → 设置服务 → CONFIGURATION_CHANGED → WindowManager 采用"
echo
_before=$(xread window_animation_scale 2>/dev/null)
echo "  写前 XML: $_before"
echo
echo "  [A] settings put 写 1.0（制造一次变化）"
settings put global window_animation_scale 1.0 2>&1 | head -1
sleep 3
_mid=$(xread window_animation_scale 2>/dev/null)
echo "      写后 XML: $_mid"
echo
echo "  [B] settings put 写 0.75（制造第二次变化 → 目标值）"
settings put global window_animation_scale 0.75 2>&1 | head -1
sleep 3
_after=$(xread window_animation_scale 2>/dev/null)
echo "      写后 XML: $_after"
echo
if [ "$_mid" != "$_before" ] || [ "$_after" != "$_mid" ]; then
    echo "  ✅ 值发生了实际变化 —— 命令路径经过设置服务，动画应当被激活"
else
    echo "  ❌ 值没有变化 —— 命令路径没能到达设置服务。"
    echo "     此时模块会退到「直写 XML」保底：值能落盘，但**不会激活动画**，"
    echo "     要下次开机系统读 XML 时才采用。"
fi
echo

echo "=== 4. 恢复三项目标值（走命令路径）==="
settings put global window_animation_scale 0.75 2>/dev/null
settings put global transition_animation_scale 0.75 2>/dev/null
settings put global animator_duration_scale 0.5 2>/dev/null
cmd settings put global window_animation_scale 0.75 2>/dev/null
cmd settings put global transition_animation_scale 0.75 2>/dev/null
cmd settings put global animator_duration_scale 0.5 2>/dev/null
sleep 2
for k in window_animation_scale transition_animation_scale animator_duration_scale; do
    printf '    %-26s XML=%s\n' "$k" "$(xread $k 2>/dev/null)"
done
echo

echo "=== 4b. 设置服务到底是死是活（关键判定）==="
_alive=0
settings list global 2>/dev/null | head -1 | grep -q . && _alive=1
if [ "$_alive" = "1" ]; then
    echo "  设置服务：**活着**（settings list 能返回内容）"
else
    echo "  设置服务：**读不出来**（settings list 返回空）"
    echo "    → 这台 ROM 上服务处于异常状态。结论："
    echo "      · 命令路径（settings / cmd settings）都到不了它，读写全废"
    echo "      · 只有 /data/system/users/0/settings_global.xml 可靠"
    echo "      · 模块已改为 **XML 优先写入**（v2.5 起），值一定能落盘"
    echo "      · 但直接改 XML 不会触发变更通知 → **动画要下次开机才生效**"
fi
echo

echo "=== 5. settings provider 进程与近期日志 ==="
ps -A 2>/dev/null | grep -i setting | head -5
echo "  --- logcat（settings / animation / Failed transaction，最近 25 条）---"
logcat -d -t 500 2>/dev/null | grep -iE 'settings|animation_scale|Failed transaction' | tail -25
echo

echo "=== 6. 模块自己的动画日志 ==="
grep '动画' $M/fix.log 2>/dev/null | tail -5
echo
echo "=== 取证结束 ==="
