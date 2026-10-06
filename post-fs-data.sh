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

# 启动指纹：不带这一行就无法判断"这一轮到底跑没跑"。
# 起因：体检报告显示充电还是原厂值，但离线模拟里写入是成功的 ——
# 到底是脚本没跑、写失败、还是写了被系统改回去，全靠这行 + charge_boost 的明细来分。
fish_log "══ post-fs-data 开始（包型 $VARIANT，模块 v$(module_version)，boot=$(getprop ro.boottime.init 2>/dev/null || echo '?')) ══"
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
#   有些驱动在开机早期对充电节点只读，过一会儿才解锁，所以用 charge_retry 做
#   有界重试（最多 5 次、每次间隔 4 秒，全部成功就提前退出）。
#   「原值→现值」明细由 charge_boost 写进日志。
charge_retry post-fs-data 5 4

# ── 4. 清理空文件夹 ──
#   放 post-fs-data 而不是 service：这个阶段动手最早，用户还没开始翻文件管理器。
#   实现里用的是 rmdir（只能删空目录），所以不存在"误删有内容的目录"这种事故。
_clean=$(clean_empty_dirs)
fish_log "空文件夹清理完成：$_clean 个"

fish_log "══ post-fs-data 结束 ══"
fish_log "🐟 虚标处理完了。红烧肉呢？"
exit 0
