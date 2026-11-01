#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════════════════
#  boot-completed.sh —— 系统完全启动完毕（收到 BOOT_COMPLETED 之后）
#  ---------------------------------------------------------------------------
#  这个钩子是 **KernelSU 专有**的。在 Magisk / APatch / FolkPatch 上
#  它不会被调用 —— 所以这里不能放"必须执行"的逻辑，只能做"KSU 上做得更好"的事。
#
#  存在的意义只有一个：**给动画缩放一个比 service.sh 更准的时机参照点。**
#    service.sh 挂在 late_start，那时 system_server 可能还在初始化设置项，
#    所以我们只能靠 wait_boot() 轮询 sys.boot_completed + 5 秒沉降去赌。
#    boot-completed.sh 是系统自己确认"起完了"之后才调用的，
#    在这里补一次同样的两步法写入，等于给 service.sh 兜一道底。
#
#  ⚠ 但**不能改变 service.sh 里那段的语义**：
#    用户明确要求动画实现与 1.x 完全一致 —— 一遍、不循环、不守护、不重试。
#    所以这里写入的是**同一套两步法**，只是多了一个不同的触发时机，
#    不是"再来轮循环"。两段各跑一次，互不依赖。
#    并且只在"值确实没到位"时才补写，到位了就不动（避免无谓的
#    CONFIGURATION_CHANGED 打扰系统）。
# ═══════════════════════════════════════════════════════════════════════════

MODDIR="${MODDIR:-${0%/*}}"
[ -d "$MODDIR" ] || MODDIR="/data/adb/modules/SL8541E_Config_Fix"

# shellcheck source=lib/common.sh
. "$MODDIR/lib/common.sh"

fish_log "══ boot-completed 开始（$ROOT_NAME）══"

# ── 动画兜底：只检查、不到位才补，绝不无条件重写 ──────────────────────────
_W=$(settings_get window_animation_scale)
_T=$(settings_get transition_animation_scale)
_A=$(settings_get animator_duration_scale)
fish_log "boot-completed 动画值: 窗口=$_W 过渡=$_T 时长=$_A"

_need=0
[ "$_W" = "0.75" ] || _need=1
[ "$_T" = "0.75" ] || _need=1
[ "$_A" = "0.5" ]  || _need=1

if [ "$_need" = "1" ]; then
    fish_log "boot-completed：动画值未到位，按 1.x 两步法补写一次"
    anim_put window_animation_scale 1.0
    anim_put transition_animation_scale 1.0
    anim_put animator_duration_scale 1.0
    sleep 1
    anim_put window_animation_scale 0.75
    anim_put transition_animation_scale 0.75
    anim_put animator_duration_scale 0.5
    fish_log "boot-completed 动画补写完成: 窗口=$(settings_get window_animation_scale) 过渡=$(settings_get transition_animation_scale) 时长=$(settings_get animator_duration_scale)"
else
    fish_log "boot-completed：动画值已到位，不重复写入（避免多余 CONFIGURATION_CHANGED）"
fi

# ── 元模块状态复检：开机跑完再看一眼，结论比 post-mount 阶段更接近稳态 ──
_MM=$(metamodule_status)
_MOUNT=$(module_mount_state)
fish_log "boot-completed：元模块=$_MM，system/ 挂载=$_MOUNT"
if [ "$_MOUNT" = "unmounted" ] && [ "$_MM" = "none" ]; then
    fish_log "⚠ boot-completed 确认：KSU 下未装元模块，system/ 文件始终不会生效（装 meta-overlayfs 后重启）"
fi

fish_log "══ boot-completed 结束 ══"
exit 0
