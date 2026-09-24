#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════════════════
#  customize.sh —— 安装入口
#  ---------------------------------------------------------------------------
#  ⚠ APatch 不执行 META-INF/com/google/android/update-binary，
#    模块根目录的这个 customize.sh 才是真正的安装入口。包装里那份
#    update-binary 只是给 Magisk 看的兼容壳。
#
#  这份脚本的三件事：
#    1. 完整性自检 —— 缺核心文件直接中止（半个模块比不装更坏）
#    2. 权限落位 —— 脚本 0755、配置 0644
#    3. 报环境 —— Root 方案 / 机型 / 安卓 / 内核，方便用户贴日志
#
#  ⚠ 不要在这里自己定义 ui_print：会把根管理器提供的那份覆盖掉，
#    结果就是安装过程"完全不输出"，看着像卡死。
# ═══════════════════════════════════════════════════════════════════════════

MODPATH="${MODPATH:-${0%/*}}"
LOG="/sdcard/SL8541E_install.log"
touch "$LOG" 2>/dev/null

say() {
    ui_print "$1"
    echo "$1" >> "$LOG" 2>/dev/null
}

# 从 module.prop 读版本，省得改了版本号忘了改文案
MOD_VER="?"
[ -f "$MODPATH/module.prop" ] && MOD_VER=$(grep '^version=' "$MODPATH/module.prop" 2>/dev/null | head -1 | cut -d= -f2)

# ── 完整性检查 ──────────────────────────────────────────────────────────────
MISSING=""
WARNINGS=""

check_file() {
    [ -f "$MODPATH/$1" ] || MISSING="$MISSING\n  缺失文件：$1（$2）"
}
check_dir() {
    [ -d "$MODPATH/$1" ] || MISSING="$MISSING\n  缺失目录：$1（$2）"
}
check_optional() {
    [ -f "$MODPATH/$1" ] || WARNINGS="$WARNINGS\n  未包含：$1（$2，可选）"
}

echo "════════════════════════════════════════" >> "$LOG"
echo "开始完整性检查 $(date)" >> "$LOG"

# 核心
check_file "module.prop"      "模块元信息"
check_file "system.prop"      "属性注入"
check_file "lib/common.sh"    "公共库★"
check_file "lib/prop.list"    "属性清单★"
check_file "lib/install.sh"   "更新器★"
check_file "post-fs-data.sh"  "开机早期脚本"
check_file "service.sh"       "开机后期脚本"
check_file "action.sh"        "操作按钮脚本"
check_file "uninstall.sh"     "卸载脚本"

# WebUI
check_dir  "webroot"                "WebUI 目录"
check_file "webroot/index.html"     "WebUI 主页面"
check_file "webroot/style.css"      "WebUI 样式"
check_file "webroot/script.js"      "WebUI 脚本"
check_file "webroot/status.sh"      "状态取值脚本"
check_file "webroot/gen_status.sh"  "状态页生成脚本"

# Wear OS
check_dir  "system/framework"                                        "框架目录"
check_file "system/etc/permissions/com.google.android.wearable.xml"  "Wear 权限声明"
check_file "system/framework/com.google.android.wearable.jar"        "Wear 核心库"
check_file "system/framework/wear-service.jar"                       "Wear 服务库"

# GitHub 加速
check_file "system/etc/hosts" "GitHub 加速 hosts"

# 可选件
check_optional "vendor/overlay/framework-res__auto_generated_rro.apk" "RRO 覆盖（power_profile）"

if [ -n "$MISSING" ]; then
    ui_print ""
    ui_print "  ╔══════════════════════════════════════╗"
    ui_print "  ║  🐟 等一下，这箱子是漏的              ║"
    ui_print "  ╚══════════════════════════════════════╝"
    ui_print ""
    ui_print "  检测到以下核心文件缺失："
    printf "$MISSING\n" | while IFS= read -r line; do
        [ -n "$line" ] && ui_print "  $line"
    done
    ui_print ""
    ui_print "  ❌ 安装已中止 —— 半个模块比不装更坏，去重新下载"
    echo "完整性检查失败：$MISSING" >> "$LOG"
    abort "   安装终止：文件不完整"
fi

if [ -n "$WARNINGS" ]; then
    ui_print ""
    ui_print "  ⚠ 可选组件没带上（不影响其他功能）："
    printf "$WARNINGS\n" | while IFS= read -r line; do
        [ -n "$line" ] && ui_print "  $line"
    done
fi
ui_print "  ✅ 完整性检查通过"
echo "完整性检查通过" >> "$LOG"

# ── Root 环境探测 ──────────────────────────────────────────────────────────
if [ -n "$APATCH" ] || [ -d /data/adb/ap ]; then
    ROOT_NAME="APatch"; ROOT_VER="${APATCH_VER_CODE:-未知}"
elif [ -n "$KSU" ]; then
    ROOT_NAME="KernelSU"; ROOT_VER="${KSU_VER_CODE:-未知}"
elif [ -n "$MAGISK_VER_CODE" ]; then
    ROOT_NAME="Magisk"; ROOT_VER="$MAGISK_VER_CODE"
else
    ROOT_NAME="未知"; ROOT_VER="-"
fi

say ""
say "        🐟  大 肥 鱼  上 岸  🐟"
say ""
say "  ┌──── 模块 ──────────────────────┐"
say "  │ zero-sl8541e和顺成方案设备优化"
say "  │ 版本 v$MOD_VER"
say "  │ B站白马曹 & DeepSeek"
say "  └────────────────────────────────┘"
say ""
say "  ┌──── 运行环境 ──────────────────┐"
say "  │ Root   : $ROOT_NAME ($ROOT_VER)"
say "  │ 机型   : $(getprop ro.product.brand) $(getprop ro.product.model)"
say "  │ 设备   : $(getprop ro.product.device)"
say "  │ 架构   : $(getprop ro.product.cpu.abi)"
say "  │ 安卓   : $(getprop ro.build.version.release) (SDK $(getprop ro.build.version.sdk))"
say "  │ 内核   : $(uname -r)"
say "  │ 构建   : $(getprop ro.build.date)"
say "  │ SELinux: $(getenforce 2>/dev/null)"
say "  └────────────────────────────────┘"
say ""
say "  🐟 正在搬运优化方案……"
say "     别断电。断了鱼会躺平，你还得重刷。"
say ""

# ── 权限落位 ───────────────────────────────────────────────────────────────
set_perm_recursive "$MODPATH" 0 0 0755 0644

for f in customize.sh post-fs-data.sh service.sh action.sh uninstall.sh; do
    [ -f "$MODPATH/$f" ] && set_perm "$MODPATH/$f" 0 0 0755
done

for f in module.prop system.prop; do
    [ -f "$MODPATH/$f" ] && set_perm "$MODPATH/$f" 0 0 0644
done

if [ -d "$MODPATH/lib" ]; then
    set_perm_recursive "$MODPATH/lib" 0 0 0755 0644
    # 库是被 source 的，不需要可执行位；dns-guard.sh 要 sh 执行，给上也无害
    [ -f "$MODPATH/lib/dns-guard.sh" ] && set_perm "$MODPATH/lib/dns-guard.sh" 0 0 0755
    say "  🐟 公共库就位（属性清单 + 电池读取 + DNS 守护）"
fi

if [ -d "$MODPATH/webroot" ]; then
    set_perm_recursive "$MODPATH/webroot" 0 0 0755 0644
    [ -f "$MODPATH/webroot/status.sh" ] && set_perm "$MODPATH/webroot/status.sh" 0 0 0755
    [ -f "$MODPATH/webroot/gen_status.sh" ] && set_perm "$MODPATH/webroot/gen_status.sh" 0 0 0755
    say "  🐟 顺手装了 WebUI（圆屏适配好了）"
fi

if [ -d "$MODPATH/system" ]; then
    set_perm_recursive "$MODPATH/system" 0 0 0755 0644
    say "  🐟 顺手捎上了 Wear OS 库"
fi

if [ -d "$MODPATH/vendor" ]; then
    set_perm_recursive "$MODPATH/vendor" 0 0 0755 0644
    say "  🐟 顺手塞了个 RRO（power_profile 修正）"
fi

if [ -f "$MODPATH/system/etc/hosts" ] && grep -q "github.com" "$MODPATH/system/etc/hosts" 2>/dev/null; then
    say "  🐟 顺手铺了条 GitHub 高速路"
fi

say "  ────────────────────────────────"
say "  ✅ 装好了。重启之后鱼才正式上班。"
say ""
say "  重启后可以："
say "    · 点模块「WebUI」看状态页 / 排查 FAQ"
say "    · 点模块「操作」看纯文本体检报告"
say "  ────────────────────────────────"
say ""
say "  咕噜咕噜…… 大肥鱼下潜。"
say ""
say "   ╭──────────────────────────────────╮"
say "   │  (˘ω˘)  本鱼上线                  │"
say "   │  穷是穷了点，活还是要干好的。      │"
say "   │  胆子可以肥嘟嘟，代码不能。        │"
say "   ╰──────────────────────────────────╯"
say ""
