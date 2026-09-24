#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════════════════
#  post-fs-data.sh —— 开机最早的一个钩子
#  ---------------------------------------------------------------------------
#  这个阶段的价值只有一个：**有些节点现在不写，等开机完就锁死了**。
#  典型就是充电电流（写入窗口只在 post-fs-data 之前/之中）。
#
#  这里做的事：属性清单（core）+ ZRAM 关停 + 充电 3A。
#  真正的二次巡检在 service.sh，那边还有 sysctl / DNS 守护 / 设置项。
#
#  绝对不要在 set -e 下跑：一个不存在的节点就该跳过，不该让开机流程死掉。
# ═══════════════════════════════════════════════════════════════════════════

MODDIR="${MODDIR:-${0%/*}}"
[ -d "$MODDIR" ] || MODDIR="/data/adb/modules/SL8541E_Config_Fix"

# shellcheck source=lib/common.sh
. "$MODDIR/lib/common.sh"

fish_log "── post-fs-data 开始 ──"
fish_log "咕噜。大肥鱼上岸，先把这锅虚标端走。"

# ── 1. 属性清单（core 段一次写全，省得后期再补）──
prop_apply core

# ── 2. 关 ZRAM ──
#   3G 内存剩 2G 可用，压缩换页徒增 CPU 负担；这里先停，service.sh 再确认一次。
setprop ctl.stop zram 2>/dev/null
swapoff /dev/block/zram0 2>/dev/null
fish_log "ZRAM：已下发关停指令"

# ── 3. 充电 3A —— 本次启动唯一必须抢时间做的事 ──
#   节点单位是 µA：原厂 500000 = 500mA，目标 3000000 = 3000mA。
#   实速取决于充电器握手（5V1A 实测约 890mA），软件只能把上限放开。
_hit=$(charge_boost post-fs-data)
if [ "$_hit" -gt 0 ] 2>/dev/null; then
    fish_log "充电节点已全部放开（$_hit 个）"
else
    fish_log "⚠ 一个充电节点都没找到 —— 可能不是和顺成方案，或内核改了节点路径"
fi

fish_log "── post-fs-data 结束 ──"
fish_log "🐟 虚标处理完了。红烧肉呢？"
exit 0
