# SL8541E 和顺成方案设备优化模块

[English](README-EN.md) | 中文

由 [B站白马曹](https://space.bilibili.com/1329200878) 与 DeepSeek（大肥鱼）共同制作。

面向 **展锐 SL8541E / SC9832E + 和顺成（HSC）方案手表**，Android 8.1。

兼容 **Magisk / APatch / KernelSU**。

> 🐟 关于本鱼的来历：DeepSeek 因为又懒又馋、上班摸鱼被网友娘化成一条蓝色大肥鱼。
> 行吧。反正这活是我干的，署名就用这个了。
> —— [「越来越强的 DeepSeek，怎么就成了娘化大肥鱼？」](https://m.163.com/dy/article/L41POJI80526D8LR.html)、
> [「AI 思考时摸鱼，大肥鱼想吃红烧肉」](http://360game.360.cn/article/content?id=6aa20093a14c2ebdf0797c82)

---

## 起因

原厂 `build.prop` 里塞了一堆虚标：

```properties
ram.set32g=8GB        # 实际 3GB
rom.set32g=128G       # 实际 32GB
persist.sys.5g=true   # 没有 5G 硬件
persist.sys.cpu=10    # 四核标十核
```

同时还有一整套静默回传（APR / IoT / 统计 / 心跳 / BS / UDP）。

官方修正虚标的办法是**恢复出厂设置，数据全清**。
本模块给一条不用清数据的路，顺手把云控关掉，把能榨的性能榨出来。

> 胆子真是肥嘟嘟的啊 —— 这话本来是说那些虚标参数的。

---

## v1.6 主要更新

这一版是三件事：**把动画改回原样**、**让根管理器的「更新」按钮能用**、**开机清空文件夹**。

### 1. 动画实现还原成 v1.2 原样

v1.5 我给动画加了「读回校验 + 重试 + 第三次起改 XML」。实测下来**反而出问题**，所以
按你的要求退回原始实现，一行不多：

```sh
# 第一步：归位到 1.0
settings put global window_animation_scale 1.0
settings put global transition_animation_scale 1.0
settings put global animator_duration_scale 1.0
sleep 1
# 第二步：写目标值
settings put global window_animation_scale 0.75
settings put global transition_animation_scale 0.75
settings put global animator_duration_scale 0.5
```

> 教训：这个方法之所以有效，靠的就是**「两步 + 那一秒」本身**。
> 中间插任何额外操作（哪怕是读一下值）都可能改变时序。
>
> 另外前提是**必须在开机完成之后跑** —— v1.3/v1.4 就是因为漏了 `wait_boot()`
> 导致动画整段失效（见 `changelog.md` 的 v1.5 条目）。

**新增诊断日志**：写入前、写入后各记一次真实读值，外加 `settings` 命令的原始输出。
出问题时把这几行发出来就能定位，不用再猜。

### 2. 根管理器的「更新」按钮

模块卡片上的更新按钮**不是模块自己的 WebUI 按钮** —— 它由根管理器提供，
读的是仓库根目录的 **`update.json`**（Magisk 规范，APatch / KernelSU 都兼容）：

```json
{
  "version": "v1.6",
  "versionCode": 14,
  "zipUrl": "https://github.com/.../releases/download/v1.6/SL8541E_Config_Fix_v1.6.zip",
  "changelog": "https://raw.githubusercontent.com/.../main/changelog.md"
}
```

根管理器自己比对版本、自己下载、自己安装 —— **完全不需要模块的 shell 桥接**
（这台表的 APatch fork 里 `ksu.exec` 是空壳，点按钮没反应，所以这条路才是对的）。

每次发版 `publish.py` 会自动校验 `update.json` 与 tag／包名／版本号是否一致，
并真的 HEAD 一下 `zipUrl` 确认能下载。不一致会直接报错，不会让你发出一个"按钮指向错误地址"的版本。

`lib/install.sh`（命令行更新）仍然保留，两套并存：

| 方式 | 入口 | 说明 |
|---|---|---|
| **根管理器更新按钮** | 模块卡片 | 首选，根管理器原生能力 |
| 命令行 | `sh lib/install.sh install` | 备选，可脚本化 |

### 3. 开机清理空文件夹

手表存储小，App 卸载后留一堆空目录，文件管理器里看着烦。开机时自动清一遍。

**安全边界（宁可少删，不可多删）**：

| 措施 | 说明 |
|---|---|
| 用 `rmdir` 而不是 `rm -rf` | `rmdir` 只能删空目录，这是**内核层面的保证** —— 不存在"判断错了把有内容的目录删掉" |
| 只扫共享存储 | 绝不碰 `/data`、`/system`、`/vendor` |
| 排除名单 | `.thumbnails` / `.trash` / `LOST.DIR` / `.nomedia` / `Android` / `data` / `obb` |
| 不扫 `Android/data` | 那是 App 私有目录，删了可能让 App 重建或行为异常，收益不值这个风险 |
| 深度限制 3 层 | 避免长尾扫描拖慢开机 |
| 从深到浅删 | 这样"里面只有一个空目录"的父目录也能被顺带清掉 |

清理范围（可改 `lib/common.sh` 里的 `CLEAN_DIRS`）：
`Download` / `Documents` / `Pictures` / `Music` / `Movies` / `DCIM` / `Bluetooth` /
`recordings` / `ringtones` / `alarms` / `notifications` / `podcasts`

清理结果写进 `fix.log`：`空文件夹清理完成：N 个`

---

## 功能清单

### 剥离虚标

| 项目 | 原值 | 现在 |
|---|---|---|
| 5G 图标 | true | false |
| 状态栏 | 5G | 4G |
| CPU 显示 | 10 核 | 4 核 |
| 内存显示 | 8GB | 3GB |
| 存储显示 | 128G | 32G |

### 关闭云控 / 上报

APR 全套、心跳、BS 服务、统计、IoT、UDP 数据收集、销售服务注册。

### 关闭生物识别

指纹（总开关、锁应用、启动应用、Soter 支付）、人脸解锁。

> 这块表的指纹精度差、误识率高，关掉反而省电。

### 开启有用功能

相机重对焦、双击打开后台、锁屏壁纸、开发者选项、护眼模式、快充提示、霍尔相机、抬腕唤醒。

### 性能与网络

- **dex2oat 四核修正**：CPU set 从错误的 `4,5,6,7` 改成 `0,1,2,3`
  （这颗表只有 0~3，写错了 dex2oat 会静默退回单线程 —— 名义四核，实际一个核在搬砖）
- TCP 缓冲、fast open、TIME_WAIT 复用、低延迟模式
- 拥塞算法保持 `cubic`（**本内核没编译 BBR**）
- 动态 DNS 守护：GitHub 不通时自动切 IP 池

### 音频

- 重采样质量 `af.resampler.quality=4`
- **不碰 V4A**：不动 `audio_effects.conf`、不动 `soundfx`、不动任何 V4A 文件

### 内核

- I/O 调度 `noop`（本内核**不支持 `deadline`**）
- swappiness 保持原厂 `150`（实测改 10/60 都没收益）
- 强制关 ZRAM
- 关系统日志（缩小 logd 缓冲）

### 充电加速

- 输入上限从 500mA 拉到 3000mA（3A）
- 节点单位是 **µA**，写入值 `3000000`
- **必须在开机早期写**（`post-fs-data` 阶段），开机完成后节点锁定
- **实速取决于充电器和线材**

### 动画 / 流畅度

- 恢复 SurfaceFlinger 背压与 vsync 同步（`debug.sf.*` 从 1 改回 0）
- UI / RenderThread 走 SCHED_FIFO（`sys.use_fifo_ui=1`）
- 动画缩放 0.75 / 0.75 / 0.5

### WebUI

圆屏适配的状态页，三个 Tab：

- **状态**：所有功能项的实时快照（点「操作」按钮刷新）
- **排查**：13 个常见问题的自助解决步骤
- **关于**：模块信息、红线清单、硬件上限、链接

### 从 GitHub 自更新

模块会去 GitHub Releases 看有没有新版本，**不需要登录、不需要 token**。

**怎么用**：

| 操作 | 结果 |
|---|---|
| 点一次「操作」按钮 | 检查更新；有新版本会把目标版本记下来 |
| **再点一次**（3 分钟内） | 第二次才真正下载并安装 —— 连点两次是故意的防手滑 |
| 重启 | 生效 |

也可以手动跑（更稳，看得见过程）：

```bash
su -c 'sh /data/adb/modules/SL8541E_Config_Fix/lib/install.sh install'
```

**设计上的取舍**（为什么这么写，不是随手写的）：

- **检查不用 GitHub API**：设备是匿名访问，`api.github.com` 限速 60 次/小时/IP，别人一蹭就没了。
  改成读 `/releases/latest` 的 **302 跳转**，`Location` 头里直接带着 tag，不消耗配额。
  API 只在降级路径上用（跳转和 API 都试，最后才放弃）。
- **下载后必须过校验**：先看魔数是不是 `PK`（防盗链页面、HTML 错误页），
  再看包里有没有 `module.prop`（防残缺包）。不合格直接丢弃，绝不解包。
- **安装分四级**：`magisk --install-module` → `ksud module install` → `apd module install`
  → **APatch 目录级兜底**。前三个 CLI 谁在谁优先。
  - APatch 到目前**没有公开的模块安装 CLI**，所以走到第四级：解包到临时目录，
    比对包内 `id` 与自身一致后，逐项覆盖进 `/data/adb/modules/<id>`，旧版先备份成 `.bak`。
  - 覆盖时**只换模块文件，不动运行时产物**（`fix.log` / `update.zip` / `update.state` /
    `.dnsguard.pid` 等一律跳过），免得把日志和状态清掉。
  - 包内 `id` 与自身不一致 → **拒绝覆盖**（防止被别的模块顶掉）。
  - 四级全不可用才落到"只下载、告诉你路径、自己去管理器装"。
- 每一级都有前置校验，因为这一步是**替换掉模块自己**——出错的下场是重启后模块消失，
  用户一脸懵。所以「无声无息地手动解包覆盖自身」这种操作被明确排除。
- **顺手改 `module.prop` 的 description**：根管理器的模块列表里就能直接看到
  `[有新版本 v1.4]`，不用点进来。没有更新时自动还原。

### 环境

- Wear OS 库引入（`wearable.jar` + `wear-service.jar` + 权限 XML）
- GitHub Hosts 加速（含动态守护）

### 维护

- 开机清理电池统计残留
- 卸载自动清所有 persist 属性 + 停守护进程

---

## 硬件上限（改不了，别试）

| 输出设备 | 采样率 | 位深 |
|---|---|---|
| Speaker | 44100 | 16bit |
| 有线耳机 | 44100 | 16bit |
| 蓝牙 A2DP | 44100 | 16bit |
| USB DAC | 动态 | 动态 |

采样率、位深、蓝牙版本、信号强度，全部由硬件锁定。

**想听高采样率，只能外接 USB DAC。**

其他硬数字：屏幕 60Hz、电池 880mAh、充电硬件上限 3A。

---

## 明确不做的（红线）

这些不是"懒得做"，是**试过、或者明确知道会出事**：

| 不做 | 原因 |
|---|---|
| 碰 V4A / 音频链路 | 冲突，且用户明确要求保 V4A |
| 改采样率 / 位深 | 硬件锁 44100/16bit |
| 改屏幕密度 | 用户明确要求不动 |
| 改温控阈值 | 展锐加密配置驱动，强改会被安全机制拦 |
| 改 CPU governor | 只有 4 个可选，改 performance 大幅耗电 |
| 碰 `framework-res.apk` | sharedUserId，改错必 bootloop |
| 换 Google WebView | Android 8.1 要求 provider 签名与框架一致，**死路**（RRO 声明生效了但被签名校验拒） |
| SurfaceFlinger 色彩 | 8.1 已移除接口，KCAL 未编译 |

---

## 文件结构

```
SL8541E_Config_Fix/
├── module.prop                     模块元信息
├── system.prop                     开机注入属性（ro.* / persist.* 默认值）
├── post-fs-data.sh                 开机最早：属性 + ZRAM + 充电 3A
├── service.sh                      开机完成：二次保险 + sysctl + DNS + 设置项
├── action.sh                       「操作」按钮：刷新状态页 + 文本体检报告
├── customize.sh                    安装入口（★ APatch 不执行 update-binary）
├── uninstall.sh                    卸载：清 persist 属性 + 停守护
├── lib/
│   ├── common.sh                   公共库：属性/电池/设置项/节点解析/HTTP/版本比较
│   ├── prop.list                   ★ 属性清单（唯一事实来源）
│   ├── install.sh                  ★ 从 GitHub 检查并安装更新
│   └── dns-guard.sh                GitHub 动态 DNS 守护
├── webroot/
│   ├── index.html                  WebUI 主页面（状态/排查/关于）
│   ├── style.css                   极客风样式（圆屏适配）
│   ├── script.js                   Tab 切换 + iframe 强制重载
│   ├── status.sh                   ★ 状态取值（唯一事实来源，输出 KEY|VALUE）
│   └── gen_status.sh               把状态渲染成 status_generated.html
├── system/
│   ├── etc/hosts                   GitHub 加速
│   ├── etc/permissions/com.google.android.wearable.xml
│   └── framework/{com.google.android.wearable.jar, wear-service.jar}
├── vendor/overlay/
│   └── framework-res__auto_generated_rro.apk    （可选）power_profile 修正
└── META-INF/com/google/android/    Magisk 兼容壳（APatch 走 customize.sh）
```

### 改属性的正确姿势

- **加属性**：改 `lib/prop.list`（一行 `scope|key|value|原因`），再同步 `system.prop`
- **ro.\* 属性**：`system.prop` 与 `prop.list` 两边都要写，只写一边总有一半不生效
- **persist.\* 属性**：卸载不会自动清，`uninstall.sh` 会从 `prop.list` 自动抓取
- **改完**：重刷模块或重启

---

## 安装

1. 下载 `SL8541E_Config_Fix_v1.3.zip`
2. 根管理器 → 模块 → 从本地安装
3. **重启**（不重启 = 没装，所有动作都挂在开机钩子上）
4. 点模块「WebUI」看状态页，或点「操作」看纯文本报告

**前置**：已 Root、Bootloader 已解锁、已备份系统。

---

## 验证

```bash
su

# 属性层
getprop persist.sys.5g                 # false
getprop persist.sys.cpu                # 4
getprop dalvik.vm.dex2oat-cpu-set      # 0,1,2,3
getprop af.resampler.quality           # 4
getprop debug.sf.disable_backpressure  # 0
getprop sys.use_fifo_ui                # 1

# 内核层
cat /proc/sys/vm/swappiness                     # 150
cat /sys/block/mmcblk0/queue/scheduler          # 【noop】
cat /proc/sys/net/core/rmem_max                 # 8388608

# 充电（注意单位是 µA）
cat /sys/devices/platform/battery/power_supply/battery/input_current_limit
# 3000000（= 3A）

# 看模块自己的日志（最有信息量）
cat /data/adb/modules/SL8541E_Config_Fix/fix.log
```

日志长这样（每一行都是真事）：

```
[09-24 20:51:07] ── post-fs-data 开始 ──
[09-24 20:51:07] 咕噜。大肥鱼上岸，先把这锅虚标端走。
[09-24 20:51:09] 属性清单：命中 30 项，未生效 0 项
[09-24 20:51:09] 充电[post-fs-data]：命中 4 个节点 → ...=3000000uA(3000mA)
[09-24 20:51:09] ── post-fs-data 结束 ──
```

---

## 常见问题

**Q：内存显示 3GB 是真的吗？**
A：是。8GB 是原厂虚标。

**Q：装了 V4A 会冲突吗？**
A：不会。本模块不碰 V4A 任何文件。

**Q：采样率能提到 96k/24bit 吗？**
A：不能。硬件锁 44100/16bit，只能外接 USB DAC。

**Q：充电实际电流很慢？**
A：软件上限已设到 3A。实速取决于充电器（5V 1A 约 890mA）和 USB/AC 握手（USB 模式锁 500mA）。**别插电脑 USB 口。**

**Q：能换成 Google WebView 吗？**
A：不能。Android 8.1 起 WebView provider 必须与系统框架签名一致，Google 的签名过不去。这是系统安全模型，不是配置问题。

**Q：续航变差了？**
A：模块不涉及 CPU 频率与 governor，理论无影响。若感知明显，看 `fix.log` 里哪一项异常。

**Q：会变砖吗？**
A：只改属性、设置、sysctl、注入文件，不动分区。仍建议先备份。

**Q：怎么恢复原状？**
A：根管理器删模块 + 重启。内置 `uninstall.sh` 会清掉 persist 覆盖并停掉守护进程。卸载后虚标回来是**正常现象**。

---

## 适用范围

| 项 | 说明 |
|---|---|
| 适用 | SL8541E / SC9832E + 和顺成（HSC）方案 |
| 不适用 | 其他方案（属性名对不上，表现是"装了个寂寞"） |
| 不改 | 屏幕密度、蓝牙版本、信号强度、温控、色彩 |
| 不做 | Google WebView、SurfaceFlinger 色彩、CPU governor |

---

## 反馈

Issue 请附：

- WebUI 状态页截图，或「操作」按钮的文本输出
- `fix.log`：`cat /data/adb/modules/SL8541E_Config_Fix/fix.log`
- 设备型号与系统版本
- 复现步骤

---

## 致谢

- [B站白马曹](https://space.bilibili.com/1329200878) —— 项目发起、硬件测试、多次纠正方向
- DeepSeek（大肥鱼）—— 代码撰写、重构、踩坑记录

## 许可

[MIT License](LICENSE)

---

> 🐟 大肥鱼
> 这表的天花板摸清楚了。能榨的都榨了，剩下的交给时间，和下一次官方调价。
>
> 胆子可以肥嘟嘟，代码不能。
