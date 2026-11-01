#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════════════════
#  post-mount.sh —— 模块挂载完成之后、zygote 启动之前
#  ---------------------------------------------------------------------------
#  这个钩子是 **KernelSU 专有**的（Magisk / APatch / FolkPatch 都没有这个阶段）。
#  在非 KSU 环境下它根本不会被调用，所以这里不需要再判断"要不要执行"。
#
#  为什么值得单独加一个文件：
#    KSU 把 system/ 的挂载**委托给元模块**（如 meta-overlayfs）。没装元模块时，
#    system/ 一个字节都不会挂上，但 post-fs-data.sh / service.sh / system.prop
#    全都照常跑 —— 于是出现最难查的一类故障：
#      **日志全绿、属性都写了、体检报告全 ✓，V4A 和 Wear OS 库就是不生效。**
#    而 post-mount.sh 是唯一"挂载已结束、系统还没起完"的窗口，
#    在这里取证最准：早了还没挂，晚了结论会被别的东西干扰。
#
#  本文件只读不写、只记日志、绝不 abort —— 它是取证，不是修复。
# ═══════════════════════════════════════════════════════════════════════════

MODDIR="${MODDIR:-${0%/*}}"
[ -d "$MODDIR" ] || MODDIR="/data/adb/modules/SL8541E_Config_Fix"

# shellcheck source=lib/common.sh
. "$MODDIR/lib/common.sh"
# shellcheck source=lib/sysinject.sh
[ -f "$MODDIR/lib/sysinject.sh" ] && . "$MODDIR/lib/sysinject.sh"

root_manager_detect
_mm=$(metamodule_status)
_mount=$(module_mount_state)

fish_log "══ post-mount 开始（根管理器 $ROOT_NAME，元模块 $_mm，挂载 $_mount）══"

# ── 判定：本模块的 system/ 到底该不该挂上 ─────────────────────────────────
#   三种"不该挂"是正常状态，不该报错：
#     · 非 KSU 族      → 挂载由根管理器内置，没有元模块概念
#     · skip_mount 存在 → 用户/管理器显式要求不挂
#     · disable/remove 存在 → 模块被禁用或待删
#   只有"应该挂、但没挂上"才是真问题。
_should_mount="yes"
case "$_mm" in
    not_applicable) _should_mount="n/a（非 KSU，挂载内置）" ;;
    none)           _should_mount="yes" ;;   # KSU 没装元模块 → 应该挂但挂不上
    active:*)       _should_mount="yes" ;;
    unknown)        _should_mount="unknown" ;;
esac
case "$_mount" in
    disabled) _should_mount="n/a（模块被禁用）" ;;
    skipped)  _should_mount="n/a（skip_mount）" ;;
esac

fish_log "post-mount：应挂载=$_should_mount，实际=$_mount"

# ── 真问题只有一个：该生效的东西没生效 ────────────────────────────────────
#   注意判据：不是"有没有元模块"，而是"文件在不在 /system 上"。
#   本机内核没 overlayfs，meta-overlayfs 之类的元模块**装了也用不了**，
#   拿它当判据只会误导。真正的兜底是 lib/sysinject.sh（直写 /system）。
if command -v sysinject_report >/dev/null 2>&1; then
    case "$(sysinject_report)" in
        rootmgr) fish_log "post-mount：system/ 已由根管理器挂载，无需干预" ;;
        ok)      fish_log "post-mount：system/ 文件均已就位" ;;
        mirror)  fish_log "post-mount：本次开机用目录镜像注入（重启后需重做，属正常）" ;;
        na)      fish_log "post-mount：模块被禁用/跳过挂载" ;;
        *)
            fish_log "⚠ 诊断：system/ 里的文件未能生效。"
            fish_log "⚠ 影响：Wear OS 库、hosts 加速不生效（属性/TCP/充电/动画不受影响）。"
            fish_log "⚠ 这台机器没 overlayfs，元模块无效；请查 fix.log 的 [sysinject] 段。"
            ;;
    esac
else
    # 库里没这个函数说明是旧包，退回旧判据
    if [ "$_mount" = "unmounted" ]; then
        fish_log "⚠ system/ 未挂载（未加载 sysinject 库，无法自动注入）"
    else
        fish_log "post-mount：system/ 已挂载"
    fi
fi

fish_log "══ post-mount 结束 ══"
exit 0
