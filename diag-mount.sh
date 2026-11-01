#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════════════════
#  diag-mount.sh —— 摸清这台设备到底有什么挂载手段可用
#  ---------------------------------------------------------------------------
#  背景：FolkPatch 自带的 Magic Mount 试过无效，内核又没编 overlayfs。
#  在写元模块之前，必须先回答一个问题：
#    **这台机器上，究竟哪种挂载方式是真能用的？**
#  不测就写，等于赌 —— 赌输了用户再装一遍、再重启一遍。
#
#  本脚本**只读**，唯一会"写"的地方是两处安全的临时挂载点（用完立即撤销）：
#    /data/local/tmp/sl8541e-mnt   （我们自己的目录，可随便建）
#  绝不碰 /system 的真实内容，也不做任何持久化修改。
#
#  用法：  su -c 'sh /data/adb/modules/SL8541E_Config_Fix/diag-mount.sh'
#  输出：  直接看屏幕；同时追加到模块目录下的 mount-diag.log
# ═══════════════════════════════════════════════════════════════════════════

MODDIR="${MODDIR:-${0%/*}}"
[ -d "$MODDIR" ] || MODDIR="/data/adb/modules/SL8541E_Config_Fix"
LOG="$MODDIR/mount-diag.log"
TMP=/data/local/tmp/sl8541e-mnt

say() { echo "$*"; echo "$*" >> "$LOG" 2>/dev/null; }
hr()  { say "──────────────────────────────────────────"; }

: > "$LOG" 2>/dev/null
say "【挂载能力诊断】$(date '+%Y-%m-%d %H:%M:%S')"
hr

# ── 0. 环境 ────────────────────────────────────────────────────────────────
say "内核:      $(uname -r)"
say "Android:   $(getprop ro.build.version.release) (SDK $(getprop ro.build.version.sdk))"
say "架构:      $(getprop ro.product.cpu.abi)"
say "SELinux:   $(getenforce 2>/dev/null)"
hr

# ── 1. overlayfs 到底有没有 ────────────────────────────────────────────────
say "【1】overlayfs"
if grep -q overlay /proc/filesystems 2>/dev/null; then
    say "  ✅ /proc/filesystems 里有 overlay"
else
    say "  ❌ /proc/filesystems 里没有 overlay（模块未编译或未注册）"
fi
if zcat /proc/config.gz 2>/dev/null | grep -q '^CONFIG_OVERLAY_FS=y'; then
    say "  ✅ CONFIG_OVERLAY_FS=y"
elif zcat /proc/config.gz 2>/dev/null | grep -q 'CONFIG_OVERLAY_FS'; then
    say "  ⚠ CONFIG_OVERLAY_FS 存在但可能 =m（模块未加载）"
elif [ ! -f /proc/config.gz ]; then
    say "  ? /proc/config.gz 不存在，无法查内核配置"
else
    say "  ❌ CONFIG_OVERLAY_FS 未设置"
fi
# 实测：真去 mount 一次 tmpfs+overlay，比看配置更可信
mkdir -p "$TMP/ov" 2>/dev/null
if mount -t tmpfs tmpfs "$TMP/ov" 2>/dev/null; then
    mkdir -p "$TMP/ov/lower" "$TMP/ov/upper" "$TMP/ov/work" "$TMP/ov/merged" 2>/dev/null
    _o=$(mount -t overlay overlay -o lowerdir="$TMP/ov/lower",upperdir="$TMP/ov/upper",workdir="$TMP/ov/work" "$TMP/ov/merged" 2>&1)
    if [ -z "$_o" ]; then
        say "  ✅ 实测 overlay 挂载成功 —— 其实可以用 meta-overlayfs"
        umount "$TMP/ov/merged" 2>/dev/null
    else
        say "  ❌ 实测 overlay 挂载失败：$_o"
    fi
    umount "$TMP/ov" 2>/dev/null
else
    say "  ❌ 连 tmpfs 都挂不上（连临时目录都不给挂，问题更靠前）"
fi
rmdir "$TMP/ov" 2>/dev/null
hr

# ── 2. /system 是什么文件系统、能不能 remount rw ──────────────────────────
say "【2】/system 文件系统"
_mnt=$(grep ' /system ' /proc/mounts 2>/dev/null | head -1)
say "  /proc/mounts: ${_mnt:-未找到 /system 挂载项}"
case "$_mnt" in
    *ext4*)     say "  类型: ext4（理论上可以 remount rw）" ;;
    *f2fs*)     say "  类型: f2fs" ;;
    *erofs*)    say "  类型: EROFS（只读，**无法写入**）" ;;
    *squashfs*) say "  类型: squashfs（只读）" ;;
    *overlay*)  say "  类型: overlay（本身已经是叠加层）" ;;
    "")         say "  类型: 未知" ;;
    *)          say "  类型: 其他（见上面原文）" ;;
esac
_ro=$(echo "$_mnt" | grep -o 'ro,' | head -1)
[ -n "$_ro" ] && say "  当前挂载为只读(ro)" || say "  当前挂载为可写(rw)"

# 实测 remount（失败无副作用）
_o=$(mount -o remount,rw /system 2>&1)
if [ -z "$_o" ]; then
    say "  ✅ mount -o remount,rw /system 成功 —— **这条最省事**"
    say "     可以直接把文件 cp 进 /system，不需要任何元模块"
    mount -o remount,ro /system 2>/dev/null   # 立刻恢复只读，不留下状态
    say "     （已立刻恢复只读）"
else
    say "  ❌ remount rw 失败：$_o"
fi
hr

# ── 3. bind mount 能力 ────────────────────────────────────────────────────
say "【3】bind mount（Magisk 那套的基础）"
mkdir -p "$TMP/b" 2>/dev/null
echo test > "$TMP/b/src" 2>/dev/null
echo orig > "$TMP/b/dst" 2>/dev/null
_o=$(mount --bind "$TMP/b/src" "$TMP/b/dst" 2>&1)
if [ -z "$_o" ]; then
    _now=$(cat "$TMP/b/dst" 2>/dev/null)
    if [ "$_now" = "test" ]; then
        say "  ✅ mount --bind 可用（内容已覆盖）"
    else
        say "  ⚠ bind 返回成功但内容没变，读回=[$_now]"
    fi
    umount "$TMP/b/dst" 2>/dev/null
else
    say "  ❌ mount --bind 失败：$_o"
fi
rm -rf "$TMP/b" 2>/dev/null
hr

# ── 4. 关键限制：能不能给 /system 里"新增"文件 ────────────────────────────
#  这是 bind mount 的死穴：只能覆盖**已存在**的路径。
#  我们模块要加的 ViPER4Android / wearable.jar / wearable.xml / libv4a_fx_ics.so
#  在原厂 /system 里根本不存在 —— 不能新增就等于这些功能全废。
say "【4】本模块需要处理的 5 个路径（关键！）"
for _rel in \
    system/etc/hosts \
    system/etc/permissions/com.google.android.wearable.xml \
    system/framework/com.google.android.wearable.jar \
    system/lib/soundfx/libv4a_fx_ics.so \
    system/priv-app/ViPER4Android/ViPER4Android.apk
do
    if [ -e "/$_rel" ]; then
        say "  已存在  /$_rel"
    else
        say "  ✗ 不存在 /$_rel   ← 这一项必须能「新增目录/文件」才能生效"
    fi
done
say "  → 只靠 bind mount（覆盖已存在文件）无法处理标 ✗ 的那几项"
hr

# ── 5. tmpfs + 目录镜像 + bind（Magisk 的做法）能不能走通 ─────────────────
#  思路：在某目录挂 tmpfs → 把原 /system 目标目录的内容复制进去 → 叠加模块文件
#        → 把 tmpfs 整体 bind 到 /system/目标目录。这样"新增文件"也就成立了。
say "【5】tmpfs 目录镜像方案（不依赖 overlayfs）"
mkdir -p "$TMP/mir" 2>/dev/null
if mount -t tmpfs tmpfs "$TMP/mir" 2>/dev/null; then
    say "  ✅ tmpfs 挂载成功"
    # 实测复制一个小目录（用 /system/etc/permissions 当样本）
    if [ -d /system/etc/permissions ]; then
        _n=0; _fail=0
        for _f in /system/etc/permissions/*; do
            [ -f "$_f" ] || continue
            _n=$((_n+1))
            cp -a "$_f" "$TMP/mir/" 2>/dev/null || _fail=$((_fail+1))
        done
        say "  样本复制 /system/etc/permissions：$((_n-_fail))/$_n 成功"
        [ "$_fail" -gt 0 ] && say "  ⚠ 有 $_fail 个复制失败（可能是 hardlink/权限问题）"
    fi
    # 实测能否把 tmpfs bind 到 /system 下的真实目录（挂上再立刻撤）
    _o=$(mount --bind "$TMP/mir" /system/etc/permissions 2>&1)
    if [ -z "$_o" ]; then
        say "  ✅ 能把 tmpfs bind 到 /system/etc/permissions —— **这条路可行**"
        umount /system/etc/permissions 2>/dev/null
    else
        say "  ❌ 无法 bind 到 /system：$_o"
        say "     （说明 /system 的挂载点不接受新的 bind，需要换策略）"
    fi
    umount "$TMP/mir" 2>/dev/null
else
    say "  ❌ tmpfs 挂不上"
fi
rm -rf "$TMP/mir" 2>/dev/null
hr

# ── 6. FolkPatch 的 Magic Mount 开关状态 ──────────────────────────────────
say "【6】FolkPatch Magic Mount 状态"
for _f in /data/adb/.magic_mount_enable /data/adb/ap/.magic_mount_enable; do
    [ -e "$_f" ] && say "  标记存在：$_f" || say "  标记不存在：$_f"
done
[ -d /data/adb/ap/magic_mount ] && say "  挂载源目录存在：/data/adb/ap/magic_mount（$(ls /data/adb/ap/magic_mount 2>/dev/null | wc -l) 项）" \
                               || say "  挂载源目录不存在：/data/adb/ap/magic_mount"
[ -d /data/adb/metamodule ] && say "  /data/adb/metamodule 已存在（说明已装过元模块）" \
                            || say "  /data/adb/metamodule 不存在（没装元模块）"
# 当前到底挂了什么
_mc=$(grep -c 'modules' /proc/mounts 2>/dev/null)
say "  /proc/mounts 里含 modules 的挂载项：${_mc:-0} 个"
[ "${_mc:-0}" -gt 0 ] && grep 'modules' /proc/mounts 2>/dev/null | head -5 | while IFS= read -r _l; do say "    $_l"; done
hr

# ── 7. 本模块自己的文件现在生效了吗 ──────────────────────────────────────
say "【7】本模块 5 个文件的当前实际状态"
for _rel in system/etc/hosts system/framework/com.google.android.wearable.jar; do
    _s="$MODDIR/$_rel"; _d="/$_rel"
    if [ -f "$_s" ] && [ -e "$_d" ]; then
        _a=$(wc -c < "$_s" 2>/dev/null | tr -d ' ')
        _b=$(wc -c < "$_d" 2>/dev/null | tr -d ' ')
        [ "$_a" = "$_b" ] && say "  $_rel：大小一致 ($_a) —— 可能已挂上" || say "  $_rel：大小不同 模块=$_a 系统=$_b —— **没挂上**"
    elif [ -f "$_s" ]; then
        say "  $_rel：模块内有，系统里没有 —— **没挂上**"
    fi
done
hr

# ── 结论 ─────────────────────────────────────────────────────────────────
say "【结论怎么读】"
say "  · 若【2】remount rw 成功 → 不需要元模块，直接 cp 进 /system 即可（最简单）"
say "  · 若【5】tmpfs+bind 成功 → 可以写一个不依赖 overlayfs 的元模块"
say "  · 若只有【3】bind 成功、【5】失败 → 只能覆盖已有文件，新增类功能无解"
say "  · 若【1】实测 overlay 成功 → 直接装现成的 meta-overlayfs 就够，不用自己写"
say ""
say "完整日志：$LOG"
say "把这份输出发给作者，就能确定该走哪条路。"

rm -rf "$TMP" 2>/dev/null
exit 0
