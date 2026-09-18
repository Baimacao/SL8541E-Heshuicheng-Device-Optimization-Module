#!/system/bin/sh

LOG="/sdcard/SL8541E_install.log"
touch "$LOG" 2>/dev/null

say() {
    ui_print "$1"
    echo "$1" >> "$LOG" 2>/dev/null
}

# ═══════════════════════════════════════
# 完整性检查
# ═══════════════════════════════════════
MISSING=""

check_file() {
    if [ ! -f "$MODPATH/$1" ]; then
        MISSING="$MISSING\n  缺失：$1（$2）"
    fi
}

check_dir() {
    if [ ! -d "$MODPATH/$1" ]; then
        MISSING="$MISSING\n  缺失目录：$1（$2）"
    fi
}

echo "════════════════════════════════════════" >> "$LOG"
echo "开始完整性检查 $(date)" >> "$LOG"

check_file "module.prop"       "模块元信息"
check_file "system.prop"       "属性注入"
check_file "post-fs-data.sh"   "早期脚本"
check_file "service.sh"        "后期脚本"
check_file "action.sh"         "操作按钮脚本"
check_file "uninstall.sh"      "卸载脚本"

check_dir  "system"                                "系统目录"
check_dir  "system/etc"                            "配置目录"
check_dir  "system/etc/permissions"                "权限目录"
check_dir  "system/framework"                      "框架目录"
check_file "system/etc/permissions/com.google.android.wearable.xml" "Wear 权限"
check_file "system/framework/com.google.android.wearable.jar"        "Wear 核心库"
check_file "system/framework/wear-service.jar"                       "Wear 服务库"
check_file "system/etc/hosts"                      "GitHub 加速"

if [ -n "$MISSING" ]; then
    ui_print ""
    ui_print "  ╔══════════════════════════════════╗"
    ui_print "  ║  🐟 大肥鱼：等等，箱子是漏的！   ║"
    ui_print "  ╚══════════════════════════════════╝"
    ui_print ""
    ui_print "  检测到以下文件缺失："
    printf "$MISSING\n" | while IFS= read -r line; do
        [ -n "$line" ] && ui_print "  $line"
    done
    ui_print ""
    ui_print "  ❌ 安装已中止，请重新下载模块压缩包"
    echo "完整性检查失败：$MISSING" >> "$LOG"
    abort "   安装终止：文件不完整"
fi

ui_print "  ✅ 完整性检查通过"
echo "完整性检查通过" >> "$LOG"

# ═══════════════════════════════════════
# Root 环境探测
# ═══════════════════════════════════════
if [ -n "$APATCH" ] || [ -d /data/adb/ap ]; then
    ROOT_NAME="APatch"
    ROOT_VER="${APATCH_VER_CODE:-未知}"
elif [ -n "$KSU" ]; then
    ROOT_NAME="KernelSU"
    ROOT_VER="${KSU_VER_CODE:-未知}"
elif [ -n "$MAGISK_VER_CODE" ]; then
    ROOT_NAME="Magisk"
    ROOT_VER="$MAGISK_VER_CODE"
else
    ROOT_NAME="未知"
    ROOT_VER="-"
fi

BRAND=$(getprop ro.product.brand)
MODEL=$(getprop ro.product.model)
DEVICE=$(getprop ro.product.device)
ARCH=$(getprop ro.product.cpu.abi)
ANDROID=$(getprop ro.build.version.release)
SDK=$(getprop ro.build.version.sdk)
KERNEL=$(uname -r)
BUILD_DATE=$(getprop ro.build.date)
SE=$(getenforce 2>/dev/null)

say ""
say "        🐟  大 肥 鱼  上 岸  🐟"
say ""
say "  ┌──── 模块信息 ──────────────────┐"
say "  │ zero-sl8541e和顺成方案设备优化"
say "  │ 版本 v1.1"
say "  │ B站白马曹 & DeepSeek"
say "  └────────────────────────────────┘"
say ""
say "  ┌──── 运行环境 ──────────────────┐"
say "  │ Root   : $ROOT_NAME ($ROOT_VER)"
say "  │ 机型   : $BRAND $MODEL"
say "  │ 设备   : $DEVICE"
say "  │ 架构   : $ARCH"
say "  │ 安卓   : $ANDROID (SDK $SDK)"
say "  │ 内核   : $KERNEL"
say "  │ 构建   : $BUILD_DATE"
say "  │ SELinux: $SE"
say "  └────────────────────────────────┘"
say ""
say "  🐟 大肥鱼正在搬运优化方案……"
say "     请勿断电，否则鱼会躺平"
say ""

set_perm_recursive "$MODPATH" 0 0 0755 0644

for f in action.sh post-fs-data.sh service.sh customize.sh uninstall.sh; do
    [ -f "$MODPATH/$f" ] && set_perm "$MODPATH/$f" 0 0 0755
done

for f in module.prop system.prop; do
    [ -f "$MODPATH/$f" ] && set_perm "$MODPATH/$f" 0 0 0644
done

if [ -d "$MODPATH/system" ]; then
    set_perm_recursive "$MODPATH/system" 0 0 0755 0644
    say "  🐟 大肥鱼顺手捎上了 Wear OS 库"
fi

if [ -f "$MODPATH/system/etc/hosts" ] && grep -q "github.com" "$MODPATH/system/etc/hosts" 2>/dev/null; then
    say "  🐟 大肥鱼顺手铺了 GitHub 高速路"
fi

say "  ────────────────────────────────"
say "  ✅ 安装完成！重启后大肥鱼上线"
say "  📋 进模块页点「操作」按钮"
say "     可查看状态与电池信息 🐟"
say "  ────────────────────────────────"
say ""
say "  咕噜咕噜…… 大肥鱼潜入深海"
say ""
say "   ╭─────────────────────────────╮"
say "   │  (˘ω˘) 本鱼上线              │"
say "   │  穷是穷了点，活还是要干好的  │"
say "   ╰─────────────────────────────╯"
say ""