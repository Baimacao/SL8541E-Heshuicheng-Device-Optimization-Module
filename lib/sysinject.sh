#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════════════════
#  lib/sysinject.sh —— 把 system/ 里的文件真正弄到 /system 上
#  ---------------------------------------------------------------------------
#  本机实测事实（mount-diag.log，2026-11-01）：
#    内核 4.4.83，**无 overlayfs**（mount -t overlay → No such device）
#    所以 meta-overlayfs / meta-rs / meta-hybrid 这类元模块**全部无效**，
#    装了也是白装 —— 它们全建在 overlayfs 上。
#
#    FolkPatch 自带的 Magic Mount 也救不了：
#      1. /data/adb/ap/magic_mount 源目录根本没被创建（开关写了，引擎没跑）
#      2. 更根本：bind mount **只能覆盖已存在路径**。
#         com.google.android.wearable.jar / .xml 原厂 /system 里没有，
#         没有路径给它绑，于是"挂载成功"但等于什么都没做。
#
#    /system 是 ext4（不是 EROFS），`mount -o remount,rw /system` **实测成功**。
#    用户也已经亲手把 V4A 写进过 /system —— 这条路是真通的。
#
#  所以策略按"能有多直接就用多直接"排三级：
#      ① direct  —— remount rw + cp 进 /system + 恢复 ro。最干净、重启后仍在。
#      ② mirror  —— tmpfs 镜像 + bind 整个目录（不依赖 overlayfs）。重启失效，需每次开机做。
#      ③ none    —— 都不行，如实记日志，不假装成功。
#
#  纪律：
#    · 每一级都**实测验证**（比内容），绝不"执行完就报成功"
#    · ① 用完全部恢复 ro，不在系统上留可写状态
#    · 只碰本模块自己的 5 个文件，不删不改系统原有文件
# ═══════════════════════════════════════════════════════════════════════════

SYSINJ_ROOT="$MODDIR/.sysinj"
SYSINJ_MAX_MB="${SYSINJ_MAX_MB:-256}"

_si_log() { fish_log "[sysinject] $*"; }

si_dir_of() { echo "$1" | sed 's#/[^/]*$##'; }

si_mb() {
    _k=$(du -sk "$1" 2>/dev/null | cut -f1)
    case "$_k" in
        ''|*[!0-9]*) echo 0 ;;
        *) echo $((_k / 1024)) ;;
    esac
}

# si_same <模块文件> <系统文件> → 0 = 内容一致
si_same() {
    _a="$1"; _b="$2"
    [ -f "$_a" ] && [ -f "$_b" ] || return 1
    _sa=$(wc -c < "$_a" 2>/dev/null | tr -d ' ')
    _sb=$(wc -c < "$_b" 2>/dev/null | tr -d ' ')
    [ -n "$_sa" ] && [ "$_sa" = "$_sb" ] || return 1
    if command -v sha256sum >/dev/null 2>&1; then
        _ha=$(sha256sum "$_a" 2>/dev/null | cut -d' ' -f1)
        _hb=$(sha256sum "$_b" 2>/dev/null | cut -d' ' -f1)
        [ -n "$_ha" ] && [ "$_ha" = "$_hb" ] && return 0
        return 1
    fi
    return 0
}

# si_pending → 列出"模块里有、但系统里缺失或内容不一致"的相对路径
si_pending() {
    for _rel in $(cd "$MODDIR" 2>/dev/null && find system -type f 2>/dev/null | sed 's#^\./##'); do
        si_same "$MODDIR/$_rel" "/$_rel" || echo "$_rel"
    done
}

# si_fix_attrs <路径> — 修正属主/权限/SELinux 标签
#   ⚠ 这步不能省：写进 /system 的文件如果 SELinux 标签不对，
#     system_server 读不到，"文件明明在那却没生效"就是这么来的。
si_fix_attrs() {
    _p="$1"
    chown 0:0 "$_p" 2>/dev/null
    if [ -d "$_p" ]; then chmod 0755 "$_p" 2>/dev/null; else chmod 0644 "$_p" 2>/dev/null; fi
    if command -v restorecon >/dev/null 2>&1; then
        restorecon "$_p" >/dev/null 2>&1
    else
        chcon u:object_r:system_file:s0 "$_p" >/dev/null 2>&1
    fi
}

# ── ① 直接写入 /system ─────────────────────────────────────────────────────
#   返回 0 = 全部写成功且验证通过
sysinject_direct() {
    _list=$(si_pending)
    [ -z "$_list" ] && { _si_log "① 所有文件已就位，无需写入"; return 0; }

    # 先确认真的能 remount —— 有些 ROM 会在 SELinux Enforcing 下拒绝
    _err=$(mount -o remount,rw /system 2>&1)
    if [ -n "$_err" ]; then
        _si_log "① remount rw 失败：$_err"
        return 1
    fi

    _ok=0; _bad=0
    for _rel in $_list; do
        _dst="/$_rel"

        # ★ 必须先备份再写。备份失败就跳过这一项 —— 宁可不生效，
        #   也不能留下"改了系统却撤不回来"的状态。
        si_backup "$_rel" || { _si_log "① $_rel 备份失败，跳过写入"; _bad=$((_bad+1)); continue; }

        _need_mkdir=0
        [ -d "${_dst%/*}" ] || _need_mkdir=1

        if [ "$_need_mkdir" = "1" ]; then
            mkdir -p "${_dst%/*}" 2>/dev/null || { _si_log "① 建目录失败：${_dst%/*}"; _bad=$((_bad+1)); continue; }
            si_fix_attrs "${_dst%/*}"
        fi

        if cp -f "$MODDIR/$_rel" "$_dst" 2>/dev/null; then
            chmod 0644 "$_dst" 2>/dev/null
            _err=$(chown 0:0 "$_dst" 2>&1)
            [ -n "$_err" ] && _si_log "① chown $_rel 报错：$_err"
            if command -v restorecon >/dev/null 2>&1; then
                restorecon "$_dst" >/dev/null 2>&1
            else
                chcon u:object_r:system_file:s0 "$_dst" >/dev/null 2>&1
            fi
            # 写回后立刻验证，不信 cp 的返回值
            if si_same "$MODDIR/$_rel" "$_dst"; then
                _ok=$((_ok+1))
            else
                _si_log "① $_rel 写入后内容不一致"
                _bad=$((_bad+1))
            fi
        else
            _si_log "① 复制失败：$_rel"
            _bad=$((_bad+1))
        fi
    done

    # 无论成败都要恢复只读 —— 不能在系统上留可写状态
    mount -o remount,ro /system 2>/dev/null

    _si_log "① 直接写入：成功 $_ok，失败 $_bad"
    [ "$_bad" -eq 0 ] && [ "$_ok" -gt 0 ] && return 0
    [ "$_bad" -eq 0 ] && return 0
    return 1
}

# ── ② tmpfs 目录镜像 + bind 整个目录 ───────────────────────────────────────
#   为什么用 tmpfs 而不是 /data 普通目录：tmpfs 在内存里，不磨损闪存，
#   重启自动清空（不用清理逻辑）。代价是占内存 —— 所以有大小上限。
si_build_mirror() {
    _drel="$1"
    _src="/$_drel"
    _mir="$SYSINJ_ROOT/$_drel"

    [ -d "$_src" ] || { _si_log "② /$_drel 不存在，跳过"; return 1; }

    if grep -q " $_src " /proc/mounts 2>/dev/null; then
        umount "$_src" 2>/dev/null
    fi

    _mb=$(si_mb "$_src")
    if [ "$_mb" -gt "$SYSINJ_MAX_MB" ]; then
        _si_log "② /$_drel 有 ${_mb}MB > 上限 ${SYSINJ_MAX_MB}MB，跳过"
        return 1
    fi

    mkdir -p "$_mir" 2>/dev/null || return 1
    # 挂 tmpfs（8MB 起步，按实际内容大小给，至少能装下原目录 + 模块文件）
    umount "$_mir" 2>/dev/null
    _size=$(( _mb + 16 ))
    if ! mount -t tmpfs -o size=${_size}M tmpfs "$_mir" 2>/dev/null; then
        _si_log "② tmpfs 挂载失败：$_mir"
        rmdir "$_mir" 2>/dev/null
        return 1
    fi

    _err=$(cp -a "$_src"/. "$_mir"/ 2>&1)
    [ -n "$_err" ] && _si_log "② 复制 /$_drel 有报错：$_err"

    _n=0
    for _f in $(cd "$MODDIR" && find "$_drel" -type f 2>/dev/null | sed 's#^\./##'); do
        _sub="${_f#$_drel/}"
        _dst="$_mir/$_sub"
        mkdir -p "${_dst%/*}" 2>/dev/null
        cp -f "$MODDIR/$_f" "$_dst" 2>/dev/null && _n=$((_n+1))
    done
    _si_log "② /$_drel 叠加 $_n 个文件"

    chown -R 0:0 "$_mir" 2>/dev/null
    find "$_mir" -type f -exec chmod 0644 {} \; 2>/dev/null
    find "$_mir" -type d -exec chmod 0755 {} \; 2>/dev/null
    if command -v restorecon >/dev/null 2>&1; then
        restorecon -R "$_mir" >/dev/null 2>&1
    else
        chcon -R u:object_r:system_file:s0 "$_mir" >/dev/null 2>&1
    fi

    _err=$(mount --bind "$_mir" "$_src" 2>&1)
    if [ -n "$_err" ]; then
        _si_log "② bind 失败 /$_drel：$_err"
        return 1
    fi

    _v=0; _c=0
    for _f in $(cd "$MODDIR" && find "$_drel" -type f 2>/dev/null | sed 's#^\./##' | head -3); do
        _c=$((_c+1)); si_same "$MODDIR/$_f" "/$_f" && _v=$((_v+1))
    done
    if [ "$_c" -gt 0 ] && [ "$_v" = "$_c" ]; then
        _si_log "✅ /$_drel 镜像注入成功（验证 $_v/$_c）"
        return 0
    fi
    _si_log "⚠ /$_drel 已 bind 但验证未过（$_v/$_c）"
    return 1
}

sysinject_mirror() {
    _list=$(si_pending)
    [ -z "$_list" ] && { _si_log "② 所有文件已就位"; return 0; }

    _dirs=""
    for _rel in $_list; do
        _d=$(si_dir_of "$_rel")
        case " $_dirs " in *" $_d "*) continue ;; esac
        _dirs="$_dirs $_d"
    done

    _ok=0; _bad=0
    for _d in $_dirs; do
        if si_build_mirror "$_d"; then _ok=$((_ok+1)); else _bad=$((_bad+1)); fi
    done
    _si_log "② 镜像注入：成功 $_ok 个目录，失败 $_bad 个"
    [ "$_bad" -eq 0 ] && return 0
    return 1
}

# ── 主入口 ────────────────────────────────────────────────────────────────
#   返回码只用于记日志，调用方**不该**中断开机。
sysinject_apply() {
    # 根管理器自己挂好了就不重复劳动（Magisk / 已装元模块的 KSU 走这条）
    case "$(module_mount_state)" in
        mounted)          _si_log "根管理器已挂载 system/，无需自注入"; return 0 ;;
        skipped|disabled) _si_log "模块被 skip_mount/disable 标记，跳过"; return 0 ;;
    esac

    if [ -z "$(si_pending)" ]; then
        _si_log "所有 system/ 文件均已就位"
        return 0
    fi

    # ① 直接写 /system —— 本机实测可行，且重启后仍然有效，优先
    sysinject_direct && { _si_log "采用方式：直写 /system"; return 0; }

    # ② 降级到 tmpfs 镜像 + bind
    #   ⚠ 这条默认**关闭**（SYSINJ_ALLOW_MIRROR=1 才启用），原因：
    #     镜像要把整个目录（/system/framework 可能上百 MB）复制进 tmpfs，
    #     等于开机时吃掉同等内存 + 几秒到几十秒。手表只有 3G 内存，
    #     为了两个文件付这个代价不划算，而且重启后要重做。
    #     直写成功的话完全不需要它。
    if [ "${SYSINJ_ALLOW_MIRROR:-0}" = "1" ]; then
        _si_log "直写失败，降级为目录镜像（SYSINJ_ALLOW_MIRROR=1）"
        sysinject_mirror && { _si_log "采用方式：目录镜像"; return 0; }
    else
        _si_log "直写失败；目录镜像未启用（要启用就设 SYSINJ_ALLOW_MIRROR=1）"
    fi

    _si_log "✗ 两种方式都失败：Wear OS 库 / hosts 加速不会生效"
    _si_log "  （属性、TCP、充电、动画等与 system/ 无关的功能不受影响）"
    return 1
}

# 给 action.sh / status.sh 用：ok / direct / mirror / fail / na
sysinject_report() {
    case "$(module_mount_state)" in
        mounted)          echo "rootmgr" ; return 0 ;;
        skipped|disabled) echo "na" ; return 0 ;;
    esac
    [ -z "$(si_pending)" ] && { echo "ok"; return 0; }
    # 有未就位的：说明这次开机是直写还是镜像（看 /proc/mounts 有没有我们的镜像）
    if grep -q "$SYSINJ_ROOT" /proc/mounts 2>/dev/null; then
        echo "mirror"
    else
        echo "fail"
    fi
}

sysinject_cleanup() {
    # tmpfs 挂载重启自动消失；这里只清可能残留的空目录
    umount "$SYSINJ_ROOT"/*/* 2>/dev/null
    rm -rf "$SYSINJ_ROOT" 2>/dev/null
}

# ═══════════════════════════════════════════════════════════════════════════
#  备份与还原 —— 直写 /system 的前提
#  ---------------------------------------------------------------------------
#  写进 /system 是**真实修改系统分区**，重刷模块不会撤销它。
#  所以直写之前必须先把原文件存一份，卸载时还原。
#  这也是"直写"这条路唯一比挂载危险的地方 —— 必须正视，不能回避。
#
#  备份位置：$MODDIR/.sysbak/  （随模块删除，不会变成孤儿）
#  记录文件：$MODDIR/.sysbak/manifest  每行 "相对路径|原状态"
#    原状态 = exist  → 系统原本有，备份在 .sysbak/<相对路径>
#    原状态 = absent → 系统原本没有，卸载时直接删掉我们放进去的
# ═══════════════════════════════════════════════════════════════════════════

SYSINJ_BAK="$MODDIR/.sysbak"
SYSINJ_MANIFEST="$SYSINJ_BAK/manifest"

# si_backup <相对路径> —— 写之前调用；幂等（已备过就不重复备）
si_backup() {
    _rel="$1"
    mkdir -p "$SYSINJ_BAK" 2>/dev/null
    # 已经记录过就跳过（同一路径只记第一次的原貌）
    if [ -f "$SYSINJ_MANIFEST" ] && grep -q "^$_rel|" "$SYSINJ_MANIFEST" 2>/dev/null; then
        return 0
    fi
    if [ -e "/$_rel" ]; then
        mkdir -p "$SYSINJ_BAK/$(si_dir_of "$_rel")" 2>/dev/null
        if cp -a "/$_rel" "$SYSINJ_BAK/$_rel" 2>/dev/null; then
            echo "$_rel|exist" >> "$SYSINJ_MANIFEST"
        else
            _si_log "⚠ 备份失败：/$_rel —— 为安全起见不写这一项"
            return 1
        fi
    else
        echo "$_rel|absent" >> "$SYSINJ_MANIFEST"
    fi
    return 0
}

# si_restore_all —— 卸载时调用，把所有直写进去的文件还原
#   回显：还原了几个 / 删了几个
si_restore_all() {
    [ -f "$SYSINJ_MANIFEST" ] || { echo "无备份记录"; return 0; }

    _err=$(mount -o remount,rw /system 2>&1)
    if [ -n "$_err" ]; then
        echo "remount rw 失败，无法还原：$_err"
        echo "⚠ 需要手动处理：/system 下仍留着本模块写入的文件"
        return 1
    fi

    _restored=0; _removed=0; _failed=0
    while IFS='|' read -r _rel _state; do
        [ -n "$_rel" ] || continue
        case "$_state" in
            exist)
                if cp -a "$SYSINJ_BAK/$_rel" "/$_rel" 2>/dev/null; then
                    _restored=$((_restored+1))
                else
                    _failed=$((_failed+1))
                fi
                ;;
            absent)
                # 原本没有 → 删掉我们放进去的；空目录一并清掉
                if [ -e "/$_rel" ]; then
                    rm -f "/$_rel" 2>/dev/null && _removed=$((_removed+1)) || _failed=$((_failed+1))
                fi
                _parent=$(si_dir_of "$_rel")
                [ -n "$_parent" ] && rmdir "/$_parent" 2>/dev/null
                ;;
        esac
    done < "$SYSINJ_MANIFEST"

    mount -o remount,ro /system 2>/dev/null
    echo "还原 $_restored 个，删除 $_removed 个，失败 $_failed 个"
    return 0
}
