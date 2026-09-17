# SL8541E 和顺成方案设备优化模块

> 一只叫「大肥鱼」的 DeepSeek 和 [B站白马曹](https://space.bilibili.com/1329200878)一起，给一块白牌手表做的系统级优化模块。
> 不是刷机包，不是 ROM，是一个 Magisk / APatch / KernelSU 通用模块。

# [English readme](https://github.com/Baimacao/SL8541E-Heshuicheng-Device-Optimization-Module/blob/main/README-EN.md)
---

## 📖 目录

- [一、这是什么](#一这是什么)
- [二、为什么做这个](#二为什么做这个)
- [三、硬件平台分析](#三硬件平台分析)
- [四、功能清单](#四功能清单)
- [五、逐项技术原理](#五逐项技术原理)
- [六、踩坑记录](#六踩坑记录)
- [七、文件结构](#七文件结构)
- [八、安装](#八安装)
- [九、验证](#九验证)
- [十、常见问题](#十常见问题)
- [十一、免责声明](#十一免责声明)

---

## 一、这是什么

一个面向 **展锐 SL8541E / SC9832E 平台、和顺成（HSC）方案手表** 的系统优化模块。

它做的事情分四类：

1. **剥离厂商伪装** —— 关掉虚假的 5G 图标、虚假的 CPU 核心数、虚假的内存存储容量
2. **关闭数据回传** —— APR 上报、心跳、IoT 云、统计服务全套静默
3. **补全系统能力** —— 开发者选项、双击后台、锁屏壁纸、Wear OS 库、TCP 调优、4 核 dex2oat
4. **系统级微调** —— 音频重采样质量、内核低抖动参数、动画缩放

**它不是万能的**。这块表硬件上限就摆在那，很多"提升"是做不到的。本 README 会诚实地讲清楚哪些能做、哪些不能做、为什么。

---

## 二、为什么做这个

拿到这块表的时候，`build.prop` 里有一堆离谱的虚标：

```properties
ram.set32g=8GB        # 实际 3GB
ram.set32g.true=2GB   # 真实值也被压成 2G
rom.set32g=128G       # 实际 32GB
persist.sys.5g=true   # 没有 5G 硬件
persist.sys.cpu=10    # 四核写成 10 核
persist.sys.logo=5G   # 状态栏显示 5G 图标
persist.sys.rom.fake=1
ro.hsc.fake_romram=true
```

同时还有一整套云控：

```properties
persist.sys.apr.enabled=1
persist.sys.apr.autoupload=1
persist.sys.heartbeat.enable=0   # 虽然写着 0 但其他项都开
ro.hsc.statistics=true
ro.hsc.iot=true
```

这不是厂商的疏忽，是**故意的**。虚标让参数好看，云控用来收集用户数据。

于是就有了这个模块：把它伪装的那一层撕掉，把它偷偷在跑的关掉，把它本该有但没开的功能补上。

---

## 三、硬件平台分析

要优化一块设备，先要知道它的天花板在哪。

### 3.1 SoC

| 项 | 值 |
|---|---|
| 型号 | 展锐 SC9832E（SL8541E 是它的封装版本） |
| CPU | 4 × ARM Cortex-A53，1.4 GHz（可下调至 768 MHz） |
| 架构 | arm64-v8a（同时支持 armeabi-v7a） |
| 工艺 | 28nm |
| 定位 | 入门级 4G 手表/功能机 |

四核 A53 是 2014 年级别的核心，性能羸弱。所以这个模块**不追求性能爆发**，只追求"别被省电策略压制"和"别浪费"。

### 3.2 音频子系统

从 `dumpsys media.audio_policy` 提取的真实能力：

| 输出设备 | 采样率上限 | 位深度 | 声道 |
|---|---|---|---|
| Speaker | **44100 Hz** | 16 bit | 立体声 |
| Wired Headset | **44100 Hz** | 16 bit | 立体声 |
| BT A2DP Out | **44100 Hz** | 16 bit | 立体声 |
| USB DAC | 动态（看设备） | 动态 | 动态 |

**结论**：

- 主输出锁死 **44100 Hz / 16 bit**
- 蓝牙也是 44100 Hz
- 想上 48000 Hz 或 24 bit？HAL 直接拒绝
- **唯一能达到高采样率的路径是 USB DAC**

所以任何"提高采样率/位深度"的想法，在这块表上都是幻想。能做的只有：
- 让重采样过程更精确（源头 48000 降到 44100 时的损耗）
- 让音频写入更稳定（低抖动）

### 3.3 音频 Codec

从 `tinymix` 提取：

```
Mixer name: 'sprdphone'
Number of controls: 131

VBC DA EQ Switch          On
VBC DA EQ Profile Select  3
DACL DG Set               24
DACR DG Set               24
...
```

- Codec 是展锐自研的 VBC
- 内置了 EQ 硬件通路（`VBC DA EQ Switch=On`）
- DAC 增益默认 24

这告诉我们：**音频路径上有硬件 EQ 在跑**，但默认参数已经调过，不用动。

### 3.4 存储与 I/O

```
/dev/block/mmcblk0/queue/scheduler: noop [cfq]
```

- eMMC 闪存
- 内核**只支持 `noop` 和 `cfq` 两种调度器**
- **没有 `deadline`**（很多网上教程会让你改成 deadline，这里不支持）

这一点非常重要，因为我在早期版本里错误地写了 `echo deadline`，结果它静默失败，一直用的还是 cfq。

### 3.5 内核

- 展锐自研内核，基于 Linux 4.x
- `swappiness` 默认 **150**（异常高，正常服务器 60，桌面 10）
- 支持 `tcp_congestion_control`（默认 `cubic`）
- **不支持 BBR**（网上很多"网络优化"会让你开 BBR，这个内核没编译）

---

## 四、功能清单

### 4.1 虚标剥离

| 项目 | 原值 | 现值 |
|---|---|---|
| 5G 图标 | `true` | `false` |
| 状态栏标识 | `5G` | `4G` |
| CPU 核心显示 | `10` | `4` |
| 内存显示 | `8GB` | `3GB` |
| 存储显示 | `128G` | `32G` |
| 虚标总开关 | `true` | `false` |

### 4.2 云控关闭

| 服务 | 属性 | 现值 |
|---|---|---|
| APR 上报 | `persist.sys.apr.enabled` | `0` |
| APR 自动上传 | `persist.sys.apr.autoupload` | `0` |
| APR 上报等级 | `persist.sys.apr.reportlevel` | `0` |
| APR 上报间隔 | `persist.sys.apr.intervaltime` | `0` |
| 心跳 | `persist.sys.heartbeat.enable` | `0` |
| BS 服务 | `persist.sys.bsservice.enable` | `0` |
| 统计 | `ro.hsc.statistics` | `false` |
| IoT 云 | `ro.hsc.iot` | `false` |
| UDP 数据收集 | `persist.sys.start_udpdatastall` | `0` |
| 销售服务注册 | `add.salesservices.register` | `false` |

### 4.3 生物识别关闭

| 项目 | 属性 | 现值 |
|---|---|---|
| 人脸解锁 | `heils.facelock` | `0` |
| 指纹总开关 | `persist.support.fingerprint` | `false` |
| 指纹锁应用 | `persist.sprd.fp.lockapp` | `false` |
| 指纹启动应用 | `persist.sprd.fp.launchapp` | `false` |
| 微信 Soter 指纹支付 | `ro.soter.support` | `false` |

**为什么关指纹**：这块表的指纹识别模块精度很差，误识率高，体验远不如密码或图案。关了反而更省电。

### 4.4 功能开启

| 项目 | 属性 |
|---|---|
| 相机重对焦 | `persist.sys.cam.refocus.enable=true` |
| 双击打开最近任务 | `ro.config.f14_double_click_recent_tasks=true` |
| 锁屏壁纸 | `ro.lockwallpaper.enable=true` |
| 开发者选项 | `settings put global development_settings_enabled 1` |
| 护眼模式 | `ro.dipaly.eyecare=1` |
| 快速充电 | `ro.hsc.fastcharging=true` |
| 霍尔开关控制相机 | `hall.switch.camera=true` |
| 抬腕唤醒 | `ro.config.raise_wakeup_timeout=3000` |

### 4.5 性能与网络

| 项目 | 值 |
|---|---|
| 4 核 dex2oat | `dalvik.vm.dex2oat-cpu-set=0,1,2,3` |
| dex2oat 线程 | `dalvik.vm.dex2oat-threads=4` |
| TCP 缓冲区 | `rmem_max/wmem_max = 8388608` |
| TCP 快速打开 | `tcp_fastopen = 3` |
| TCP 拥塞算法 | `cubic` |
| TIME_WAIT 复用 | `tcp_tw_reuse = 1` |

### 4.6 音频与内核

| 项目 | 值 |
|---|---|
| 音频重采样质量 | `af.resampler.quality=4` |
| swappiness | `10`（原值 150） |
| I/O 调度 | `noop` |

### 4.7 Wear OS 环境

引入三个文件：

```
/system/etc/permissions/com.google.android.wearable.xml
/system/framework/com.google.android.wearable.jar
/system/framework/wear-service.jar
```

让系统"认识" Wear OS 库，使得依赖 Wear API 的应用能正常调用。

### 4.8 维护

- **开机清理电池校正文件**：`/data/system/batterystats.bin` 等
- **动画修复两步法**：先归位到 1.0，再调到目标值

---

## 五、逐项技术原理

### 5.1 虚标剥离

**原理**：Android 的 `Settings.System` 里没有"设备信息"的存储位置，厂商是通过 `build.prop` 里的属性 + 系统设置 App 读取来显示内存/存储的。

以展锐方案为例，设置 App 会读：

```properties
persist.sys.ram        # 显示内存
persist.sys.rom        # 显示存储
persist.sys.cpu        # 显示核心数
persist.sys.5g         # 状态栏 5G 图标
persist.sys.logo       # 状态栏文本
```

我们把真值写回去，设置 App 显示的就是真值。

**验证**：`getprop persist.sys.ram` 应该返回 `3GB`。

### 5.2 云控关闭

**原理**：厂商的云控是通过 `persist.sys.apr.*` 系列属性控制 **APR（Android Problem Reporter）** 模块的。APR 是展锐自研的异常上报框架，会定期收集设备信息、崩溃日志、使用习惯等，加密上传。

相关属性的作用：

| 属性 | 作用 |
|---|---|
| `persist.sys.apr.enabled` | 总开关 |
| `persist.sys.apr.autoupload` | 自动上传（不设只本地存） |
| `persist.sys.apr.reportlevel` | 上报内容详细程度 |
| `persist.sys.apr.intervaltime` | 上报间隔 |
| `persist.sys.apr.lifetime` | 数据保留时长 |
| `persist.sys.apr.exceptionnode` | 是否上报崩溃节点 |

全部设 0/false，APR 就哑了。

### 5.3 dex2oat 4 核修正

**发现过程**：

原设备上装了一个 `dex2oat_4t` 模块，属性显示：

```properties
dalvik.vm.dex2oat-cpu-set=4,5,6,7
```

这是 **8 核设备**的写法。但 SL8541E **只有 4 核**（CPU 编号 0,1,2,3）。

这意味着 dex2oat 启动时找不到 CPU 4~7，会**静默失败或回退单线程**。原模块不仅无效，还可能拖慢编译。

**修正**：改成 `0,1,2,3`，dex2oat 才能真的用满 4 核。

**原理**：`dalvik.vm.dex2oat-cpu-set` 是传给 ART 虚拟机的**CPU 亲和性掩码**，格式是逗号分隔的 CPU 编号。ART 会解析这个字符串，把编译线程绑定到这些 CPU 上。

### 5.4 TCP 调优

**属性层能改的**：

```properties
net.tcp.default_init_rwnd=256   # 初始接收窗口
```

原值 60，太小。RWND 是 TCP 握手时告诉对方"我这边能接收多少数据"，太小会导致慢启动时间过长。

**内核层必须用 echo**：

`/proc/sys/net/*` 是**内核运行时参数**，属性系统管不了。必须在启动后直接写：

```sh
echo 8388608 > /proc/sys/net/core/rmem_max
echo "4096 87380 8388608" > /proc/sys/net/ipv4/tcp_rmem
```

这些参数的作用：

| 参数 | 作用 |
|---|---|
| `rmem_max` / `wmem_max` | 单个 socket 收发缓冲最大值 |
| `tcp_rmem` | TCP 接收缓冲（min/default/max） |
| `tcp_wmem` | TCP 发送缓冲（min/default/max） |
| `tcp_fastopen` | TFO，握手时携带数据 |
| `tcp_tw_reuse` | 复用 TIME_WAIT 连接 |
| `tcp_low_latency` | 优先延迟而非吞吐 |

**重要**：不要照抄网上教程写 `bbr`。这个内核**没有编译 BBR**，写了会失败。

### 5.5 音频重采样质量

**问题背景**：

大多数流媒体（网易云、QQ 音乐、Spotify）默认输出 48000 Hz。但这块表的音频 HAL 只支持 44100 Hz。所以**每一次播放都要重采样**：48000 → 44100。

Android 默认的重采样算法质量中等。AOSP 提供了 `af.resampler.quality` 属性控制：

| 值 | 算法 |
|---|---|
| 0 | 关闭重采样（危险，可能失真） |
| 1 | 最低质量，快速 |
| 2 | 低质量 |
| 3 | 中等质量（默认） |
| 4 | 高质量 |
| 5+ | 极高质量，但耗 CPU |

改成 4 后，重采样引入的高频损失和相位失真显著减少。

**为什么不改更高**：

- 5 及以上对 A53 这种小核负担过大
- 收益递减明显（4 已经接近听感无损）

**为什么不碰 `audio_effects.xml`**：

因为设备上装了 ViPER4Android，它的配置文件是 `/system/etc/audio_effects.conf`（**不是 .xml**）。系统启动时 XML 加载失败，自动回退到 .conf。所以：

- ❌ 改 .xml 没用（系统不读）
- ⛔ 改 .conf 会让 V4A 失效
- ✅ 只动 `af.resampler.quality`，这是 AOSP 通用属性，V4A 不碰

### 5.6 swappiness 降低

**原值 150 意味着什么**：

`swappiness` 控制内核在内存压力下有多倾向于把匿名页换出到 zram/swap。

- 0：完全不用 swap
- 60：Linux 默认
- 100：非常积极
- 150：极度激进（展锐定制的）

**为什么影响音频**：swappiness 高 → 内存压力时频繁换页 → 系统抖动 → 音频线程被抢占 → **爆音/断流**。

改到 10 后，除非内存真的不够，否则不换页，音频路径更稳定。

**为什么不改 0**：3GB 内存不算富裕，完全不换页可能导致 OOM Kill。10 是安全值。

### 5.7 I/O 调度器

**原值 cfq**：

- `cfq`（Completely Fair Queuing）：为机械硬盘设计，追求公平，但引入额外延迟
- `noop`：简单 FIFO，无重排序，**闪存最佳**
- `deadline`：折中方案，减少延迟抖动

**为什么改 noop**：

1. eMMC 闪存没有寻道延迟，cfq 的"公平"没意义
2. noop 延迟最低，音频写入、dex2oat 读文件都更顺畅
3. **这个内核不支持 deadline**（`cat /sys/block/mmcblk0/queue/scheduler` 只有 `noop` 和 `cfq`）

### 5.8 Wear OS 库引入

**做了什么**：

```
/system/etc/permissions/com.google.android.wearable.xml  ← 声明库
/system/framework/com.google.android.wearable.jar         ← 核心库
/system/framework/wear-service.jar                        ← 服务库
```

**原理**：

Android 的 `/system/etc/permissions/*.xml` 是**权限声明文件**。里面用 `<library>` 或 `<feature>` 标签告诉系统"我有这个能力"。

`com.google.android.wearable.xml` 里声明了 Wear OS 的 Java 库，系统启动时会把这些 jar 加进应用的 classpath。装了 Wear 依赖的 App 就能调用 `com.google.android.clockwork.*` 等类。

**验证方法**：

```bash
pm list libraries | grep -i wearable
```

能列出库名，说明 jar 已加载。

### 5.9 电池校正文件清理

**做了什么**：

```sh
rm -f /data/system/batterystats.bin
rm -f /data/system/battery_stats.bin
```

**原理**：

Android 通过 `batterystats.bin` 记录电量历史、每个应用耗电占比。时间久了文件会积累脏数据，导致电量显示漂移。删除后系统会重新生成一份干净的。

**注意**：

- **不校准电池**（硬件层面的电量计）
- 只清理软件统计
- 不影响续航，只影响电量显示的准确性
- 每次重启都删**没必要**，所以只在刷入后首次开机清理

### 5.10 动画修复两步法

**为什么分两步**：

```sh
# 第一步：归位
settings put global window_animation_scale 1.0
settings put global transition_animation_scale 1.0
settings put global animator_duration_scale 1.0
sleep 1

# 第二步：调优
settings put global window_animation_scale 0.75
settings put global transition_animation_scale 0.75
settings put global animator_duration_scale 0.5
```

**原理**：

`SettingsProvider` 内部有**缓存**。如果系统启动后先被某进程读过一次（值为 1.0），我们直接写 0.75，某些组件可能仍然用缓存里的 1.0，直到下次重启才更新。

先写 1.0 强制刷新缓存，再写目标值，能保证所有组件拿到最终值。

**为什么不直接写 0.5/0.5/0.5**：

- 窗口 0.75（稍快，但不生硬）
- 过渡 0.75（一致）
- 时长 0.5（动画内部插值最快，减少"拖沓感"）

这是 Android 系统动画的经典调优配比。

---

## 六、踩坑记录

这一节记录开发过程中踩过的坑，给后来人少走弯路。

### 6.1 APatch 不执行 `update-binary`

**现象**：

模块安装成功，但 `update-binary` 里的 `ui_print` 输出**一行都不显示**。

**原因**：

APatch **不读 `META-INF/` 目录**，它用的是模块根目录的 `customize.sh`。`update-binary` 是 Magisk 的旧路径。

**解决**：

新建 `customize.sh`，安装输出全放里面。`update-binary` 保留官方模板给 Magisk 用户。

### 6.2 不要重定义 `ui_print`

**现象**：

自己写了 `ui_print()` 函数，安装界面什么都不显示。

**原因**：

```sh
. /data/adb/magisk/util_functions.sh
```

`source` 这一行时，官方 util_functions 会**自动定义** `ui_print`。如果你在 source 之后再定义一个，会把官方的覆盖掉，官方那个是能写 `$OUTFD` 的，你自己写的可能不能。

**解决**：

- source 前定义临时版本（环境检查用）
- source 后**不要再动** `ui_print`，直接用官方的

### 6.3 `settings` 命令在 action 上下文不可靠

**现象**：

`action.sh` 里执行 `settings get global window_animation_scale` 返回：

```
cmd: Failure calling service settings: Failed transaction(2147483646)
```

**原因**：

`action.sh` 运行在受限的进程上下文里，bind 不到 `settings` 服务。

**解决**：

优先读 XML 文件：

```sh
grep -o "name=\"$1\"[^/]*" /data/system/users/0/settings_global.xml | \
grep -o 'value="[^"]*"' | head -1 | sed 's/value="//;s/"$//'
```

XML 是 SettingsProvider 的落盘文件，一定能读到。

### 6.4 Android toybox 没有 awk

**现象**：

```
./action.sh[147]: awk: not found
```

**原因**：

Android 8.1 的 toybox 工具箱**移除了 `awk`**，只有 `sed`、`grep`、`cut` 等。

**解决**：

- 用 APatch / Magisk 自带的 **BusyBox**（它包含 awk）
- 或把浮点运算改为**纯 shell 整数运算**

```sh
# 原来
awk '{ printf "%.2f V", $1/1000000 }'

# 改后
volt=$((v / 1000000))
frac=$(((v % 1000000) / 10000))
printf "%d.%02d V" "$volt" "$frac"
```

### 6.5 `stat -c` 在 toybox 上不可用

**现象**：

检查文件权限时 `stat -c '%a'` 报错。

**原因**：

toybox 的 `stat` 是精简版，不支持 `-c` 自定义格式。

**解决**：

用 `ls -l` + `cut`：

```sh
ls -l "$f" | cut -c1-10    # 拿到权限字符串 "-rw-r--r--"
```

### 6.6 `persist.*` 属性改 build.prop 无效

**现象**：

改了 `build.prop` 里的 `persist.sys.5g=false`，重启后又是 `true`。

**原因**：

`persist.*` 属性首次启动后会保存到 `/data/property/persistent_properties`。之后系统**优先读这个文件**，不再读 `build.prop` 默认值。

**解决**：

用 `resetprop -n`：

```sh
resetprop -n persist.sys.5g false
```

`-n` 参数让 `resetprop` **直接改内存属性区**，绕过 property_service 的检查，能强制覆盖已存值。

### 6.7 `ro.*` 属性两次保险

**现象**：

`ro.*` 属性（只读）改了就生效，但某些组件（如 SystemUI）读到的是旧值。

**原因**：

`ro.*` 属性一旦设定就不能改。但**组件的缓存**可能还持有旧值。

**解决**：

两处都写：

1. `system.prop`（Magisk 早期注入）
2. `resetprop ro.xxx value`（**不带 `-n`**，让 property_service 感知变化）

### 6.8 Wear feature 误报

**现象**：

Wear 文件挂载了，但 `pm list features | grep wearable` 没输出。

**原因**：

`com.google.android.wearable.xml` 声明的是 **`<library>`** 而不是 `<feature>`。`pm list features` 只查 feature。

**解决**：

检测改成 feature + library 双查：

```sh
pm list libraries | grep -i wearable
```

### 6.9 完整性检查的时机

**问题**：什么时候做文件完整性检查？

**答案**：在 `customize.sh` **最开头**，`install_module` 之前。

**原因**：

- 检查太晚，系统已经写入部分文件，回滚困难
- 检查太早（`update-binary` 里），APatch 又不执行

`customize.sh` 是 APatch / Magisk / KernelSU **唯一都执行的入口**。

---

## 七、文件结构

```
SL8541E_Config_Fix/
├── module.prop                          # 模块元信息
├── system.prop                          # 属性注入（ro.* + persist.* 默认值）
├── post-fs-data.sh                      # 早期脚本（persist.* 覆盖、电池清理）
├── service.sh                           # 后期脚本（sysctl、动画、settings）
├── action.sh                            # 操作按钮（状态检测 + 电池信息）
├── customize.sh                         # 安装脚本（完整性检查、权限、中文提示）
├── system/                              # Wear OS 库
│   ├── etc/
│   │   └── permissions/
│   │       └── com.google.android.wearable.xml
│   └── framework/
│       ├── com.google.android.wearable.jar
│       └── wear-service.jar
└── META-INF/
    └── com/google/android/
        ├── update-binary                # Magisk 兼容（APatch 不读）
        └── updater-script               # 占位标记
```

### 脚本执行时机

| 脚本 | 时机 | 用途 |
|---|---|---|
| `customize.sh` | 安装时 | 完整性检查、权限设置、中文提示 |
| `post-fs-data.sh` | 启动最早期（阻塞） | `persist.*` 覆盖、电池清理 |
| `service.sh` | 启动完成后（非阻塞） | sysctl、settings、动画 |
| `action.sh` | 用户点击按钮 | 状态检测、电池信息 |

---

## 八、安装

### 前置条件

- 已 Root：**APatch / Magisk v20.4+ / KernelSU** 任一
- 已解锁 Bootloader
- 备份当前系统（重要）

### 步骤

1. 打包成 zip：

```bash
zip -r SL8541E_Config_Fix.zip SL8541E_Config_Fix/
```

2. 传到手表

3. 打开 Root 管理器 → 模块 → 从本地安装 → 选择 zip

4. 重启设备

5. 打开模块卡片，点「操作」按钮查看状态

### 注意事项

- **首次刷入**：安装界面会显示完整性检查结果 + 大肥鱼出厂信息
- **更新**：直接刷新版，管理器会识别为"更新"
- **卸载**：管理器里删除模块，重启

---

## 九、验证

### 9.1 属性层

```bash
su
getprop persist.sys.5g              # false
getprop persist.sys.cpu             # 4
getprop persist.sys.rom.fake        # 0
getprop dalvik.vm.dex2oat-cpu-set   # 0,1,2,3
getprop af.resampler.quality        # 4
```

### 9.2 内核层

```bash
cat /proc/sys/vm/swappiness                    # 10
cat /sys/block/mmcblk0/queue/scheduler         # noop [noop] 或 noop [cfq]
cat /proc/sys/net/core/rmem_max                # 8388608
cat /proc/sys/net/ipv4/tcp_congestion_control  # cubic
```

### 9.3 设置层

```bash
settings get global development_settings_enabled   # 1
settings get global window_animation_scale         # 0.75
```

### 9.4 文件层

```bash
ls -l /system/framework/com.google.android.wearable.jar
ls -l /system/etc/permissions/com.google.android.wearable.xml
pm list libraries | grep -i wearable
```

### 9.5 快捷方式

点模块卡片的「操作」按钮，一次性看全部状态。

---

## 十、常见问题

### Q1: 为什么装完显示内存只有 3GB，不是 8GB？

A: **3GB 是真的，8GB 是假的**。原厂虚标，模块把它纠正过来了。如果你真的想要假数据，改 `ram.set32g=8GB` 即可。

### Q2: 动画修复显示"未生效"？

A: 请检查 `service.sh` 是否执行。查看 `fix.log`：

```bash
cat /data/adb/modules/SL8541E_Config_Fix/fix.log
```

### Q3: action 按钮无反应？

A: 
1. 检查 `action.sh` 是否有执行权限：`ls -l /data/adb/modules/SL8541E_Config_Fix/action.sh`
2. 应有 `-rwxr-xr-x`
3. 没有则 `chmod 755`

### Q4: 装了 V4A 会冲突吗？

A: **不冲突**。本模块**完全不碰**：
- `/system/etc/audio_effects.conf`
- `/system/lib/soundfx/`
- `/vendor/lib/soundfx/`
- V4A 任何文件

只改了 `af.resampler.quality`（AOSP 通用属性）。

### Q5: 音频采样率能提到 96k/24bit 吗？

A: **不能**。硬件 HAL 锁死 44100/16bit。想要高清音频，用 **USB DAC**。

### Q6: 蓝牙版本能升级吗？

A: **不能**。蓝牙版本由芯片和协议栈写死。

### Q7: 屏幕密度被改了吗？

A: **没有**。虽然 `system/build.prop` 里是 194，`vendor/build.prop` 里是 320，实际以开机后 `getprop ro.sf.lcd_density` 为准。模块**不干预**这个值。

### Q8: 装了之后续航变差？

A: 本模块**不涉及 CPU 频率调节**，也不改 governor。理论上不影响续航。如果变差，可能是：
- 其他模块冲突
- 关掉省电模式后某些服务变活跃
- 清理电池校正后系统重新统计耗电

### Q9: 能刷回原版吗？

A: 可以。删除模块 + 重启即可。但要**清除 `persist.*` 覆盖**：

```bash
su
resetprop --delete persist.sys.5g
resetprop --delete persist.sys.cpu
# ... 或者直接恢复出厂
```

### Q10: 会不会变砖？

A: 本模块**只改属性、设置、sysctl、注入文件**，不改分区、不刷固件。理论上不会变砖。但：
- 如果属性设置不当，可能导致某个功能异常
- 如果有恢复手段（TWRP / 线刷包），可以随时还原
- **刷前请备份**

---

## 十一、免责声明

1. **本模块仅为学习研究使用**，作者不对任何因使用本模块导致的设备损坏、数据丢失、保修失效负责。
2. **刷机有风险**，请在充分了解风险后再操作。
3. **修改系统属性和设置可能违反设备保修条款**。
4. **本模块不含任何破解、盗版、绕过验证的内容**，仅对系统进行合法优化。
5. **转载/二次开发**请保留原作者信息。

---

## 致谢

- **B站白马曹** —— 项目发起者，硬件测试与验证
- **DeepSeek（大肥鱼）** —— 代码撰写、方案设计、踩坑记录

## 开源协议

MIT License
