#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════════════════
#  lib/install.sh —— 从 GitHub 检查并安装模块更新
#  ---------------------------------------------------------------------------
#  用法：
#      sh lib/install.sh check    只检查，把结果写进 update.state
#      sh lib/install.sh install  检查 + 下载 + 安装
#
#  两次点击保护：install 必须连续调用两次（3 分钟内），否则只下载不安装。
#  理由是这活会替换掉模块自己，刷错版本的下场是重启后模块消失、用户一脸懵。
#
#  更新检查为什么不用 API：
#      设备是匿名访问，api.github.com 限速 60 次/小时/IP，别人一蹭就没了。
#      /releases/latest 的 302 跳转里直接带着 tag，不消耗配额：
#          Location: https://github.com/OWNER/REPO/releases/tag/v1.3
#
#  安装为什么分几级：
#      magisk --install-module / ksud module install / apd module install
#      各根管理器 CLI 不一样，挨个试；都不可用就只下载并把路径告诉用户，
#      让他在管理器里手动装 —— 绝不无声无息地手动解包覆盖自身。
# ═══════════════════════════════════════════════════════════════════════════

MODDIR="${MODDIR:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
[ -d "$MODDIR" ] || MODDIR="/data/adb/modules/SL8541E_Config_Fix"

# shellcheck source=common.sh
. "$MODDIR/lib/common.sh"

OWNER="Baimacao"
REPO="SL8541E-Heshuicheng-Device-Optimization-Module"
STATE="$MODDIR/update.state"
CONFIRM="$MODDIR/.update.confirm"
DL="$MODDIR/update.zip"
API="https://api.github.com/repos/$OWNER/$REPO/releases/latest"
LATEST="https://github.com/$OWNER/$REPO/releases/latest"

ACTION="${1:-check}"
CUR_VER=$(module_version)
CUR_CODE=$(module_version_code)

# ── 取远端最新 tag ──
get_remote_tag() {
    _tag=""

    # 路子 1：/releases/latest 的 302（首选，不吃 API 配额）
    _loc=$(http_location "$LATEST")
    case "$_loc" in
        */releases/tag/*) _tag="${_loc##*/releases/tag/}" ;;
    esac

    # 路子 2：转成 API 路径（github.com/X/releases/tag/T → api.../releases/tags/T）
    if [ -z "$_tag" ] && [ -n "$_loc" ]; then
        case "$_loc" in
            */releases/tag/*)
                _t="${_loc##*/releases/tag/}"
                if http_get "https://api.github.com/repos/$OWNER/$REPO/releases/tags/$_t" "$STATE.api" >/dev/null 2>&1; then
                    [ "$(file_kind "$STATE.api")" = "其他" ] && _tag=$(grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' "$STATE.api" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
                fi
                ;;
        esac
    fi

    # 路子 3：直接打 API（限速兜底）
    if [ -z "$_tag" ]; then
        if http_get "$API" "$STATE.api" >/dev/null 2>&1; then
            _tag=$(grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' "$STATE.api" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
        fi
    fi

    rm -f "$STATE.api" 2>/dev/null
    [ -n "$_tag" ] && echo "$_tag"
}

# ── 把结果落盘，顺便更新 module.prop 的描述（根管理器列表里就能看到）──
write_state() {
    _status="$1"; _remote="$2"; _note="$3"
    {
        echo "status=$_status"
        echo "current=$CUR_VER"
        echo "remote=$_remote"
        echo "note=$_note"
        echo "checked=$(date '+%Y-%m-%d %H:%M')"
    } > "$STATE" 2>/dev/null
}

# module.prop 的 description 是模块列表里显示的那行，可以借它提示更新
RESTORE_DESC="$MODDIR/.desc.bak"
set_list_hint() {
    _hint="$1"
    [ -f "$MODDIR/module.prop" ] || return 0
    grep -q '^description=' "$MODDIR/module.prop" 2>/dev/null || return 0
    # 首次改写前存一份原文，恢复时用
    [ -f "$RESTORE_DESC" ] || grep '^description=' "$MODDIR/module.prop" > "$RESTORE_DESC" 2>/dev/null
    _base=$(sed 's/^description=//' "$RESTORE_DESC" 2>/dev/null | head -1)
    [ -n "$_base" ] || return 0
    _tmp="$MODDIR/module.prop.tmp"
    sed "s|^description=.*|description=$_hint$_base|" "$MODDIR/module.prop" > "$_tmp" 2>/dev/null
    mv "$_tmp" "$MODDIR/module.prop" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════════════════
#  检查
# ══════════════════════════════════════════════════════════════════════════
fish_log "── 更新检查 ──"
fish_log "当前版本 v$CUR_VER (code $CUR_CODE)"

REMOTE=$(get_remote_tag)
if [ -z "$REMOTE" ]; then
    write_state "error" "" "网络不通或 GitHub 被墙"
    set_list_hint "[检查失败] "
    fish_log "⚠ 拿不到远端版本（curl/wget 都没有，或网络不通）"
    echo "STATUS=error"
    exit 1
fi
fish_log "远端最新 tag：$REMOTE"

# tag 形如 v1.3；把版本段抠出来比较
REMOTE_VER=$(echo "$REMOTE" | sed 's/^[vV]//')
CMP=$(ver_cmp "$CUR_VER" "$REMOTE_VER")
fish_log "版本比较：v$CUR_VER vs v$REMOTE_VER → $CMP"

case "$CMP" in
    1)
        write_state "ahead" "$REMOTE_VER" "本地比远端新"
        set_list_hint ""
        echo "STATUS=ahead"
        fish_log "本地版本更新（可能是自己编的包），不动"
        ;;
    0)
        write_state "same" "$REMOTE_VER" "已是最新"
        set_list_hint ""
        echo "STATUS=same"
        fish_log "✅ 已是最新版本"
        ;;
    *)
        write_state "newer" "$REMOTE_VER" "有新版本"
        set_list_hint "[有新版本 v$REMOTE_VER] "
        echo "STATUS=newer"
        echo "REMOTE=$REMOTE_VER"
        fish_log "🆕 发现新版本 v$REMOTE_VER"
        ;;
esac

# ══════════════════════════════════════════════════════════════════════════
#  安装（只有 check 之外的调用才会走到这里）
# ══════════════════════════════════════════════════════════════════════════
[ "$ACTION" = "check" ] && exit 0

if [ "$CMP" != "-1" ]; then
    fish_log "没有更新可装（$CMP），install 中止"
    echo "RESULT=no_update"
    exit 0
fi

# ── 两次点击保护 ──
# 第一次：只下载并落一个确认标记；第二次（3 分钟内）：真正安装。
MARK=""
[ -f "$CONFIRM" ] && MARK=$(cat "$CONFIRM" 2>/dev/null | tr -d ' \n')
if [ "$MARK" != "$REMOTE_VER" ]; then
    echo "$REMOTE_VER" > "$CONFIRM" 2>/dev/null
    fish_log "第一次确认：已记下目标版本 v$REMOTE_VER，3 分钟内再点一次才真装"
    echo "RESULT=need_confirm"
    echo "REMOTE=$REMOTE_VER"
    exit 0
fi

# ── 下载 ──
ZIPNAME="SL8541E_Config_Fix_${REMOTE}.zip"
URL="https://github.com/$OWNER/$REPO/releases/download/$REMOTE/$ZIPNAME"
fish_log "开始下载 $URL"
rm -f "$DL" 2>/dev/null
if ! http_get "$URL" "$DL"; then
    fish_log "⚠ 下载失败（网络/被墙/IP 池失效）"
    write_state "newer" "$REMOTE_VER" "下载失败"
    echo "RESULT=download_failed"
    exit 1
fi

# ── 校验 ──
# 1) 魔数必须是 zip（防盗链页面、HTML 错误页）
KIND=$(file_kind "$DL")
if [ "$KIND" != "zip" ]; then
    fish_log "⚠ 下载到的东西不是 zip（判定=$KIND），已丢弃"
    mv "$DL" "$DL.bad" 2>/dev/null
    echo "RESULT=bad_download"
    exit 1
fi
# 2) 必须能列目录，且含 module.prop 与 customize.sh（防残缺包）
if command -v unzip >/dev/null 2>&1; then
    _list=$(unzip -l "$DL" 2>/dev/null)
    if ! echo "$_list" | grep -q 'module.prop'; then
        fish_log "⚠ 包里没有 module.prop，不是有效模块"
        rm -f "$DL"
        echo "RESULT=bad_package"
        exit 1
    fi
    if ! echo "$_list" | grep -q 'customize.sh'; then
        fish_log "⚠ 包里没有 customize.sh（APatch 的安装入口就是它）"
        rm -f "$DL"
        echo "RESULT=bad_package"
        exit 1
    fi
    _n=$(echo "$_list" | tail -1 | tr -s ' ' | sed 's/^ *//' | cut -d' ' -f1)
    case "$_n" in ''|*[!0-9]*) _n="?" ;; esac
    fish_log "包校验通过：$_n 个条目"
else
    fish_log "⚠ 没有 unzip，跳过包内清单校验（只验了 zip 魔数）"
fi
_sz=$(wc -c < "$DL" 2>/dev/null | tr -d ' ')
[ -n "$_sz" ] || _sz="?"
fish_log "下载完成：$_sz 字节"

# ── 安装 ──
rm -f "$CONFIRM" 2>/dev/null

if module_install "$DL"; then
    fish_log "✅ 已交给根管理器安装，重启后生效"
    write_state "installed" "$REMOTE_VER" "已安装，待重启"
    set_list_hint "[已装 v$REMOTE_VER，待重启] "
    echo "RESULT=installed"
    echo "REMOTE=$REMOTE_VER"
    echo "REBOOT_REQUIRED=1"
elif [ -d /data/adb/ap ] || [ -n "${APATCH:-}" ]; then
    # APatch 没有模块安装 CLI，走目录级兜底
    # （前提已经过二次点击 + 包魔数校验 + 包内 id 与自己一致）
    fish_log "没有安装 CLI，检测到 APatch，走目录级兜底安装"
    _self_id=$(grep '^id=' "$MODDIR/module.prop" 2>/dev/null | head -1 | cut -d= -f2 | tr -d ' \r\n')
    if module_install_apatch "$DL" "$_self_id"; then
        fish_log "✅ APatch 兜底安装完成，重启后生效"
        write_state "installed" "$REMOTE_VER" "已安装(APatch)，待重启"
        set_list_hint "[已装 v$REMOTE_VER，待重启] "
        echo "RESULT=installed_apatch"
        echo "REMOTE=$REMOTE_VER"
        echo "REBOOT_REQUIRED=1"
    else
        fish_log "⚠ APatch 兜底安装失败，包留在 $DL"
        write_state "downloaded" "$REMOTE_VER" "已下载，兜底安装失败"
        set_list_hint "[已下 v$REMOTE_VER，去管理器手动装] "
        echo "RESULT=manual_needed"
        echo "REMOTE=$REMOTE_VER"
        echo "ZIP=$DL"
    fi
else
    fish_log "⚠ 没有可用的安装 CLI，也不是 APatch，包留在 $DL"
    write_state "downloaded" "$REMOTE_VER" "已下载，需手动安装"
    set_list_hint "[已下 v$REMOTE_VER，去管理器手动装] "
    echo "RESULT=manual_needed"
    echo "REMOTE=$REMOTE_VER"
    echo "ZIP=$DL"
fi
exit 0

