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
fish_log "🐟 大肥鱼：先剥虚标。"

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

# ── V4A-BEGIN ── ViPER4Android 音效（合并进来的；无音效包会被整段移除）──
# ── 4. ViPER4Android 音效 ────────────────────────────────────────────────
#   V4A 需要两条 SELinux 放行规则，否则 audioserver / mediaserver 没法加载它的
#   soundfx 库。下面这四条来自 V4A 原模块的 post-fs-data.sh，原样保留。
#
#   ⚠ 工具差异：V4A 原模块用 `magiskpolicy`（Magisk 专有）。本机是 APatch，
#     对应命令是 `apd`。两个都试一遍，谁在就用谁；**都不在也不报错** ——
#     规则是"锦上添花"，加载失败最多是 V4A 不生效，不该让开机脚本失败。
#
#   🌟 另外这里顺便记下 V4A 落盘没有 —— 装了模块但文件没挂上时，
#      日志里能直接看出来，不用去翻文件。
_v4a_files="
system/priv-app/ViPER4Android/ViPER4Android.apk
system/lib/soundfx/libv4a_fx_ics.so
system/etc/audio_effects.conf
"
_v4a_ok=0; _v4a_miss=""
for _rel in $_v4a_files; do
    if [ -f "$MODDIR/$_rel" ]; then
        _v4a_ok=$((_v4a_ok + 1))
    else
        _v4a_miss="$_v4a_miss $_rel"
    fi
done
fish_log "V4A：模块内实际存在 $_v4a_ok/3 个文件"
[ -n "$_v4a_miss" ] && fish_log "V4A：⚠ 缺失$_v4a_miss"

# 选一个可用的策略工具
_v4a_pol=""
if command -v magiskpolicy >/dev/null 2>&1; then
    _v4a_pol="magiskpolicy --live"
elif command -v apd >/dev/null 2>&1; then
    _v4a_pol="apd --live"
fi

if [ -n "$_v4a_pol" ]; then
    _v4a_n=0
    $_v4a_pol "allow audioserver audioserver_tmpfs file { read write execute }" 2>/dev/null && _v4a_n=$((_v4a_n + 1))
    $_v4a_pol "allow mediaserver mediaserver_tmpfs file { read write execute }" 2>/dev/null && _v4a_n=$((_v4a_n + 1))
    $_v4a_pol "allow hal_audio_default hal_audio_default process { execmem }" 2>/dev/null && _v4a_n=$((_v4a_n + 1))
    $_v4a_pol "allow hal_audio_default hal_audio_default_tmpfs file { execute }" 2>/dev/null && _v4a_n=$((_v4a_n + 1))
    fish_log "V4A：SELinux 放行规则已下发 $_v4a_n/4 条（工具：${_v4a_pol%% *}）"
else
    fish_log "V4A：⚠ 没有 magiskpolicy / apd，跳过 SELinux 放行（V4A 可能不生效）"
fi
# ── V4A-END ──

fish_log "══ post-fs-data 结束 ══"
fish_log "🐟 虚标段处理完毕。"
exit 0
