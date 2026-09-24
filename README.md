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

## v1.4 主要更新

这一版没有加新功能，**全是重构**。功能一个没少，重复代码清掉了一半。

### 1. 抽出公共库（最大的改动）

v1.2 的结构问题：同一段属性在 `post-fs-data.sh` 和 `service.sh` 里各写了一遍、
充电块写了两遍、`status.sh` / `gen_status.sh` / `action.sh` 里电池读取和格式化抄了三份、
`chkv()` 抄了三份。改一个值要改四个文件，漏一个就变成"我这儿明明改了怎么没生效"。

现在：

```
lib/common.sh     属性写入 / 电池读取与格式化 / settings 兜底 / 节点数值解析
lib/prop.list     属性清单（纯文本表，唯一事实来源）
lib/dns-guard.sh  GitHub 动态 DNS 守护（从 service.sh 的嵌套引号字符串里独立出来）
```

改动量：

| | v1.2 | v1.3 |
|---|---|---|
| 属性定义位置 | 3 处（两个脚本 + system.prop） | 1 处（`lib/prop.list`）+ system.prop |
| 充电写入块 | 2 份 | 1 个函数 `charge_boost` |
| 电池格式化函数 | 3 份 | 1 份 |
| 电池 sysfs 路径探测 | 3 份 | 1 份 |
| `chkv` 判定 | 3 份 | 1 份 |
| 脚本总行数 | 约 1070 | 约 800（功能更多、注释更多的情况下） |

### 2. 健壮性修复（都是会真实咬人的）

| 问题 | v1.2 | v1.3 |
|---|---|---|
| `resetprop` 不存在时 | 整段属性静默失败 | 退回 `setprop`，并记日志说明 |
| 属性写入 | 每次开机无脑刷 40+ 条 | **先读后写**，值对了就不写（`persist.*` 每次写入都落盘，开机路径上是白送 I/O） |
| 充电节点读回 `node_int` | 直接 `$((RAW/1000))`，读到空串会在部分 shell 报错 | 统一 `node_int()`，非数字返回空、调用方判空 |
| 电池 `temp` 为负 / 为空 | `$((TMP/10)).$((TMP%10))` 可能出 `3.-5` | 单独处理符号 |
| `charge_boost ... \| read` | — | 明确避开子 shell 吞变量（写进注释，防止后来人踩回去） |
| `service.sh` 重复执行 | 设置项写两遍、DNS 守护起两个 | 加 `.run.lock` 防重入 |
| DNS 守护存活判断 | `pgrep -f "ping -c 1 -w 2 github"`（ping 一结束就误判成没起） | 写 pid 文件 + 查 `/proc/<pid>` |
| DNS 守护进程 | 塞在 `nohup sh -c '...'` 单引号字符串里，改一行要数引号 | 独立成 `lib/dns-guard.sh` |
| 卸载残留 | 只清属性，DNS 守护变孤儿进程继续跑 | 一并 kill 守护、清 pid 文件与状态页 |
| 状态页空值 | 显示空行（用户以为没生效） | 统一显示 `—` |
| 状态页 iframe | 浏览器会吃缓存 | 切回「状态」Tab 时加时间戳强制重载 |
| 版本号 | 硬编码在 5 个文件里 | `customize.sh` 从 `module.prop` 读 |

### 3. 补上一处 v1.2 遗留的漏洞

云控那三条 `ro.*`（`ro.hsc.statistics` / `ro.hsc.iot` / `add.salesservices.register`）
以及 `ro.soter.support`、`persist.logd.*`、`af.resampler.quality`，
v1.2 只写在 `system.prop` 里 **没有走 `resetprop`** —— 系统改回去就没人再管。
现在全部纳入 `lib/prop.list`，和别的属性一起被强制写一遍。

> 这是本次唯一的行为变化，方向是"更彻底地关掉上报"，不是新增功能。

### 4. 文案重写

安装横幅、操作报告、WebUI 三个 Tab、FAQ、失败提示，全部重写。
加了本鱼自己的梗（`~$` 提示符、鱼形 ASCII、`胆子可以肥嘟嘟，代码不能`），
技术信息一条没删 —— **踩过的坑全部保留在文档里**，因为那些坑还会再咬人。

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
