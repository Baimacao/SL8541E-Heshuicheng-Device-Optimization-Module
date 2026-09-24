#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════════════════
#  webroot/gen_status.sh —— 把状态渲染成 status_generated.html
#  ---------------------------------------------------------------------------
#  APatch 的 WebUI API（ksu.exec）是空壳，回调根本不触发，所以这里不用 JS 取数，
#  改成开机时和点「操作」时**生成一个静态 HTML**，index.html 用 iframe 加载它。
#  WebView 也在 80 版，能不用的新特性一概不用。
#
#  取值统一走 status.sh（唯一事实来源），本脚本只负责排版。
# ═══════════════════════════════════════════════════════════════════════════

MODDIR="${MODDIR:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
[ -d "$MODDIR" ] || MODDIR="/data/adb/modules/SL8541E_Config_Fix"

WEBROOT="$MODDIR/webroot"
[ -d "$WEBROOT" ] || exit 0

TMP="$WEBROOT/status_generated.html.tmp"
OUT="$WEBROOT/status_generated.html"
KV="$WEBROOT/.status.kv"

# ── 先取数，落到临时文件（不要在管道里跑循环，子 shell 里的变量出不来）──
sh "$WEBROOT/status.sh" > "$KV" 2>/dev/null

# kv <KEY> → 值
kv() { grep "^$1|" "$KV" 2>/dev/null | head -1 | cut -d'|' -f2-; }

# ok/ng 徽章
badge() {
    case "$1" in
        1) printf '<span class="v ok">[OK]</span>' ;;
        0) printf '<span class="v ng">[NG]</span>' ;;
        *) printf '<span class="v dim">%s</span>' "$(esc "$1")" ;;
    esac
}
# 简单转义：状态页的值全是我们自己拼的，但电池 health 之类是系统给的原文
esc() {
    printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
}
row()  { printf '    <div class="row"><span class="k">%s</span>%s</div>\n' "$1" "$2"; }
# 空值统一显示成 "—"：空白行会让人以为模块没生效，其实只是这项读不到
rowv() {
    _v="$2"
    [ -z "$_v" ] && _v="—"
    printf '    <div class="row"><span class="k">%s</span><span class="v">%s</span></div>\n' "$1" "$(esc "$_v")"
}
card() { printf '  <div class="card"><h2><span class="p">&gt;</span>%s</h2>\n' "$1"; }
endc() { printf '  </div>\n'; }

VER=$(kv VER)
[ -z "$VER" ] && VER="?"

{
cat << 'HEAD'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<link rel="stylesheet" href="style.css">
<style>
body { padding: 0; background: #0a0e14; }
#app { max-width: 100%; margin: 0; padding: 8px; }
</style>
</head>
<body>
<div id="app">
HEAD

card "SPOOF_STRIP · 虚标剥离"
row "5G 假图标关闭"  "$(badge "$(kv SPOOF_5G)")"
row "状态栏回落 4G"  "$(badge "$(kv SPOOF_LOGO)")"
row "CPU 报四核"     "$(badge "$(kv SPOOF_CPU)")"
row "虚标总开关"     "$(badge "$(kv SPOOF_FAKE)")"
row "真实内存显示"   "$(badge "$(kv SPOOF_RAM)")"
endc

card "TELEMETRY_OFF · 云控上报"
row "统计上报"       "$(badge "$(kv TEL_STAT)")"
row "IoT 云控"       "$(badge "$(kv TEL_IOT)")"
row "APR 自动上传"   "$(badge "$(kv TEL_APR)")"
row "心跳"           "$(badge "$(kv TEL_HB)")"
row "BS 服务"        "$(badge "$(kv TEL_BS)")"
endc

card "BIOMETRIC_OFF · 生物识别"
row "指纹"           "$(badge "$(kv BIO_FP)")"
row "人脸"           "$(badge "$(kv BIO_FACE)")"
endc

card "FEATURES_ON · 开着有用"
row "相机重对焦"     "$(badge "$(kv FEAT_REFOCUS)")"
row "双击打开后台"   "$(badge "$(kv FEAT_DBLTAP)")"
row "锁屏壁纸"       "$(badge "$(kv FEAT_LOCKWP)")"
row "开发者选项"     "$(badge "$(kv FEAT_DEVOPT)")"
endc

card "DEX2OAT · 四核修正"
rowv "线程数"        "$(kv DEX_THREADS)"
rowv "CPU set"       "$(kv DEX_CPUSET)"
row "set 正确"       "$(badge "$([ "$(kv DEX_CPUSET)" = "0,1,2,3" ] && echo 1 || echo 0)")"
endc

card "NETWORK · 网络"
rowv "rmem_max"      "$(kv NET_RMEM)"
rowv "wmem_max"      "$(kv NET_WMEM)"
rowv "拥塞算法"      "$(kv NET_CC)"
row "rwnd 属性"      "$(badge "$(kv NET_RWND)")"
row "hosts 挂载"     "$(badge "$(kv NET_HOSTS)")"
rowv "github.com"    "$(kv NET_GHIP)"
row "DNS 守护"       "$(badge "$(kv NET_DNSGUARD)")"
endc

card "KERNEL · 内核"
rowv "重采样质量"    "$(kv KRN_RESAMPLE)"
rowv "swappiness"    "$(kv KRN_SWAP)"
row "I/O 调度"       "$(badge "$(kv KRN_IO_SEL)")"
rowv "可用内存"      "$(kv MEM_AVAIL)/$(kv MEM_TOTAL) MB"
endc

card "CHARGING · 充电"
row "ZRAM 已关"      "$(badge "$(kv CHG_ZRAM)")"
rowv "input_limit"   "$(kv CHG_LIMIT) mA"
rowv "ac_max"        "$(kv CHG_AC) mA"
endc

card "GRAPHICS · 流畅度"
row "sf 背压恢复"    "$(badge "$(kv GFX_BP)")"
row "sf vsync 同步"  "$(badge "$(kv GFX_LATCH)")"
row "UI FIFO"        "$(badge "$(kv GFX_FIFO)")"
rowv "窗口动画"      "$(kv ANIM_WIN)x"
rowv "过渡动画"      "$(kv ANIM_TRANS)x"
rowv "动画时长"      "$(kv ANIM_DUR)x"
endc

card "WEAR_OS · 环境"
row "wearable.jar"   "$(badge "$(kv WEAR_JAR)")"
row "wear-service"   "$(badge "$(kv WEAR_SVC)")"
row "permissions"    "$(badge "$(kv WEAR_XML)")"
endc

card "BATTERY · 电池"
rowv "电量"          "$(kv BATT_CAP)%"
rowv "电压"          "$(kv BATT_VOLT)"
rowv "电流"          "$(kv BATT_CUR)"
rowv "温度"          "$(kv BATT_TEMP) °C"
rowv "健康"          "$(kv BATT_HEALTH)"
rowv "状态"          "$(kv BATT_STATUS)"
endc

cat << FOOT
  <footer>
    <span class="p">--</span> v$VER · snapshot $(date '+%m-%d %H:%M') <span class="p">--</span>
  </footer>
  <footer class="note">
    状态为开机快照。点模块卡片「操作」按钮刷新后再回来看。
  </footer>
</div>
</body>
</html>
FOOT
} > "$TMP" 2>/dev/null

mv "$TMP" "$OUT" 2>/dev/null
chmod 644 "$OUT" 2>/dev/null
rm -f "$KV" 2>/dev/null

exit 0
