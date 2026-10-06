#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════════════════
#  diagnose.sh —— 充电节点写不动的一次性取证
#  ---------------------------------------------------------------------------
#  用法（手表上）：
#      su -c 'sh /data/adb/modules/SL8541E_Config_Fix/diagnose.sh' > /sdcard/diag.txt
#    然后把 /sdcard/diag.txt 拿回来。
#
#  背景：实证日志显示 4 个充电节点全部 500000→500000（写了没变化），
#  但离线模拟里同一份代码写入正常。到底是"只读"、"写被忽略"、
#  还是"节点找错了"，只有现场数据能定 —— 不要猜。
# ═══════════════════════════════════════════════════════════════════════════

echo "=== 0. 环境 ==="
echo "时间: $(date)"
echo "内核: $(uname -r)"
echo "id  : $(id)"
echo "SELinux: $(getenforce 2>/dev/null)"
echo

echo "=== 1. 报告里用的那 4 个节点是否存在 / 权限 / 可写 ==="
for n in \
  /sys/devices/platform/battery/power_supply/ac/current_max \
  /sys/devices/platform/battery/power_supply/usb/current_max \
  /sys/devices/platform/battery/power_supply/battery/input_current_limit \
  /sys/devices/platform/battery/power_supply/battery/current_max ; do
    if [ -e "$n" ]; then
        echo "[存在] $n"
        echo "       值=$(cat "$n" 2>&1)"
        echo "       权限=$(ls -l "$n" 2>&1 | tr -s ' ' | cut -d' ' -f1,3,4)"
        if [ -w "$n" ]; then echo "       -w 测试: 可写"; else echo "       -w 测试: 不可写 ⛔"; fi
    else
        echo "[缺失] $n"
    fi
done
echo

echo "=== 2. 真实尝试写入并报告结果（含 stderr）==="
for n in \
  /sys/devices/platform/battery/power_supply/ac/current_max \
  /sys/devices/platform/battery/power_supply/battery/input_current_limit ; do
    [ -e "$n" ] || continue
    before=$(cat "$n" 2>/dev/null)
    err=$(echo 3000000 > "$n" 2>&1)
    rc=$?
    after=$(cat "$n" 2>/dev/null)
    echo "$n"
    echo "   写入 rc=$rc  原值=$before  现值=$after"
    [ -n "$err" ] && echo "   stderr: $err"
done
echo

echo "=== 3. 全盘搜索还有哪些 current 节点（可能我们盯错了目标）==="
echo "--- /sys/class/power_supply/ 下所有 current* ---"
for d in /sys/class/power_supply/*/; do
    [ -d "$d" ] || continue
    for f in "$d"current_max "$d"input_current_limit "$d"constant_charge_current "$d"current_now; do
        [ -e "$f" ] && echo "  $f = $(cat "$f" 2>&1)"
    done
done
echo "--- /sys/devices/platform/battery/ 下所有含 current 的文件 ---"
find /sys/devices/platform/battery -name '*current*' 2>/dev/null | head -30 | while read -r f; do
    echo "  $f = $(cat "$f" 2>/dev/null)"
done
echo

echo "=== 4. 有没有其他充电控制接口（HAL / 节点）==="
for p in /sys/class/power_supply/battery/constant_charge_current_max \
         /sys/class/power_supply/battery/charge_control_limit \
         /sys/class/power_supply/battery/charge_control_limit_max \
         /sys/class/power_supply/usb/current_max \
         /sys/class/power_supply/ac/current_max ; do
    [ -e "$p" ] && echo "  [有] $p = $(cat "$p" 2>/dev/null)  ($(ls -l "$p" 2>/dev/null | tr -s ' ' | cut -d' ' -f1))"
done
echo

echo "=== 5. dmesg 里跟充电/电流相关的近期信息 ==="
dmesg 2>/dev/null | grep -iE 'charg|current_limit|input_current|sprd.*bat' | tail -20
echo

echo "=== 6. 当前充电状态（判断是否插着充电器）==="
for f in status health capacity voltage_now current_now temp; do
    for d in /sys/class/power_supply/battery /sys/class/power_supply/sprdbattery; do
        [ -e "$d/$f" ] && echo "  $d/$f = $(cat "$d/$f" 2>/dev/null)"
    done
done
for d in ac usb; do
    [ -e "/sys/class/power_supply/$d/online" ] && echo "  $d/online = $(cat /sys/class/power_supply/$d/online 2>/dev/null)"
done
echo

echo "=== 7. 模块自身状态 ==="
M=/data/adb/modules/SL8541E_Config_Fix
echo "  包型   : $(cat $M/lib/variant 2>/dev/null)"
echo "  版本   : $(grep '^version=' $M/module.prop 2>/dev/null | cut -d= -f2)"
echo "  prop.list 行数: $(grep -vc '^\s*#\|^\s*$' $M/lib/prop.list 2>/dev/null)"
echo "  prop.list 里非 5 列的行:"
awk -F'|' '!/^[[:space:]]*#/ && NF && NF!=5 {print "      L" NR " 列数=" NF "  " $0}' $M/lib/prop.list 2>/dev/null | head -15
echo "  （上面若为空 = 清单格式正常；若非空 = 这些行会被跳过）"
echo

echo "=== 8. 网络可达性（更新按钮能不能用）==="
for u in https://api.github.com https://github.com https://raw.githubusercontent.com ; do
    if command -v curl >/dev/null 2>&1; then
        code=$(curl -s -o /dev/null -w '%{http_code}' -m 8 "$u" 2>/dev/null)
        echo "  $u -> HTTP ${code:-超时}"
    else
        echo "  curl 不存在"
        break
    fi
done
echo "  /system/etc/hosts 里的 github 行:"
grep -i github /system/etc/hosts 2>/dev/null | head -5
echo "  hosts 可写? $([ -w /system/etc/hosts ] && echo 是 || echo 否)"
echo
echo "=== 诊断结束 ==="
