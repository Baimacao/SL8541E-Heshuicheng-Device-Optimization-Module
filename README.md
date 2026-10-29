# SL8541E 和顺成方案设备优化模块

> **本包：HSC特供·有音效**（`hsc` + audio）
>
> 同一个 Release 里有四个包：**HSC 特供 / 通用** × **有音效 / 无音效**。
> 另一个机型维度是「通用包（不处理虚标/云控/指纹人脸）」；另一个音效维度是「无音效」。
> **四个包不能同时安装**（模块 ID 相同）。

[English](README-EN.md) | 中文

由 [B站白马曹](https://space.bilibili.com/1329200878) 与 DeepSeek 共同制作。

面向 **展锐 SL8541E / SC9832E + 和顺成（HSC）方案手表**，Android 8.1。
兼容 **Magisk / APatch / KernelSU**。

---

## 这鱼是怎么来的

有人把 DeepSeek 的蓝色鲸鱼 logo 丢进它自己的识图框，它先一本正经地描述
「用户上传了一张蓝色大肥鱼的图片」，隔了两秒才反应过来：等等，这个轮廓……这不就是我自己吗。

外号就这么定下了。后来有人给它画了女仆装、配上一碗冒尖的白米饭——
爱吃白饭、聪明但懒、被说胖会炸毛。

这套代码是我写的，署名就用这个。下面正文里我尽量少提它，
毕竟一个模块的文档，主角应该是模块。

—— [正惊解梗：蓝色大肥鱼](https://news.qq.com/rain/a/20261023A08JBY00)、
[AI 思考时摸鱼，大肥鱼想吃红烧肉](https://www.gamersky.com/news/202609/2205991.shtml)

---

## 起因

原厂 `build.prop` 里塞了一堆虚标：

```properties
ram.set32g=8GB        # 实际 3GB
rom.set32g=128G       # 实际 32GB
persist.sys.5g=true   # 没有 5G 硬件
persist.sys.cpu=10    # 四核标十核
```

外加一整套静默回传：APR、IoT、统计、心跳、BS、UDP。

官方的修正办法是恢复出厂设置，代价是数据全清。本模块走另一条路：
**不清数据**，顺手把云控关掉，把该榨的性能榨出来。

> 胆子真是肥嘟嘟的 —— 这话本来是吐槽别人敢做出格的事，萌化的狠话。
> 搁这儿正好：敢把 3G 写成 8G 的人，胆子确实够肥的。

---

## 这事到底有几分成色

按「从夯到拉」的五级说法（**夯** = 顶，**拉** = 拉胯）给本模块定个位，
省得刷完发现期待错位：

| 档次 | 对应部分 | 说明 |
|---|---|---|
| **夯** | 剥虚标、关云控、dex2oat 四核修正 | 原厂明摆着的错，改完立刻见效，没有争议 |
| **不错** | 充电 3A、TCP 调优、关 ZRAM 与日志 | 实打实的收益，但吃硬件和场景 |
| **一般** | 动画缩放、UI 实时优先级 | 主观感受为主，跑分看不出来 |
| **拉** | 采样率、屏幕密度、CPU governor | **别指望** —— 硬件锁死或改了更糟，见「红线」 |

---

## 四个包，按需选一个

同一个 Release 里有四个包，两个维度：

| # | 包 | 文件名 | 适合 |
|---|---|---|---|
| ① | **HSC 特供 · 有音效** | `SL8541E_Config_Fix_v2.1.3_HSC_Audio.zip` | 和顺成方案手表 + 想要 V4A 音效 |
| ② | **HSC 特供 · 无音效** | `SL8541E_Config_Fix_v2.1.3_HSC.zip` | 和顺成方案手表，不要音效 |
| ③ | **通用 · 有音效** | `SL8541E_Config_Fix_v2.1.3_Universal_Audio.zip` | 其他 SL8541E 设备 + 想要 V4A 音效 |
| ④ | **通用 · 无音效** | `SL8541E_Config_Fix_v2.1.3_Universal.zip` | 其他 SL8541E 设备，不要音效 |

- **机型维度**：HSC 特供会处理虚标 / 云控 / 指纹人脸（这些属性名只有和顺成方案才有）；
  通用包不碰这些，只做与机型无关的部分。
- **音效维度**：有音效包含 ViPER4Android v6.0.1（装后需在 V4A 高级设置里开启）；
  无音效包完全不含 V4A —— 不带 APK、不带音效库、不改 `audio_effects.conf`、不加 SELinux 规则。

> ⚠ **四个包模块 ID 相同，不能同时安装。**
> 每个包有**独立的更新通道**（`update-hsc-audio.json` / `update-hsc.json` /
> `update-uni-audio.json` / `update-uni.json`）—— 点更新只会升到同一个包，
> **不会被换成别的包型**。

---

## 更新记录

### v2.1.x —— 三轮冷审计

找了一个对本项目一无所知的智能体，只给代码不给背景，让它专门找毛病。
三轮下来修的都是真问题：

- **动画写入验证的竞态**：`settings put` 返回时 XML 还没落盘，代码立刻回读比对
  → 前两条命令几乎必然判失败 → 每次掉进直写 XML 的兜底分支，顺便打一条假警报。
  改成按脚本允许短暂重试后再判定。
- **mksh 兼容**：`case` 分支里用了 bash 专属写法，设备上是 mksh，直接语法错。
- **卸载还原**：`uninstall.sh` 漏了两条 persist 属性，删了模块还会残留。
- **移除空壳 jar**：`system/framework` 里那个占位文件既没内容也没人读，删掉。
- 顺手补了 `bash -n` 与 6 个回归测试，离线就能跑。

### v2.0 —— 合并 V4A、拆四包

- 合并 **ViPER4Android v6.0.1**（FX for Magisk v23，作者 ShadySquirrel / 小白杨修改），
  APK + `libv4a_fx_ics.so` + `audio_effects.conf` 均与原件字节级一致。
- SELinux 放行**自适应**：有 `magiskpolicy` 用它，否则用 `apd`（APatch），都没有则跳过并记日志。
- 一个包拆成四个，见上表。

### 动画：回到 1.x 原样

```sh
settings put global window_animation_scale 1.0
settings put global transition_animation_scale 1.0
settings put global animator_duration_scale 1.0
sleep 1
settings put global window_animation_scale 0.75
settings put global transition_animation_scale 0.75
settings put global animator_duration_scale 0.5
```

只有一遍：不循环、不守护进程、不重试、不写 XML、无额外沉降。

> **关键机制**：手表要检测到「调整」这个动作才会激活动画，不是给个值就完事。
> 所以必须走 `settings` 命令路径（触发 `CONFIGURATION_CHANGED`），
> **不能直写 XML** —— 那样没有任何事件，动画不会激活。
>
> 中间试过的 6 秒间隔、三轮循环、后台守护，最后全部撤回：
> 1.x 这一版是唯一在真机上反复确认有效的。

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

- **dex2oat 四核修正**：CPU set 从错误的 `4,5,6,7` 改成 `0,1,2,3`。
  这颗表只有 0~3 号核，写错了 dex2oat 会静默退回单线程 ——
  名义四核，实际一个核在搬砖，还是那只最慢的。
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

3A 只是把水管换粗了。管子粗不等于水压大 —— 5V1A 的头照样只喂到约 890mA，
插电脑 USB 口永远是 500mA。瓶颈永远在墙那头。

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

| 操作 | 结果 |
|---|---|
| 点一次「操作」按钮 | 检查更新；有新版本会把目标版本记下来 |
| **用「更新」按钮** | 根管理器卡片上的原生更新按钮，读 `update-*.json` |
| 重启 | 生效 |

也可以手动跑（更稳，看得见过程）：

```bash
su -c 'sh /data/adb/modules/SL8541E_Config_Fix/lib/install.sh install'
```

**设计上的取舍**（为什么这么写，不是随手写的）：

- **检查不用 GitHub API**：设备是匿名访问，`api.github.com` 限速 60 次/小时/IP，
  别人一蹭就没了。改成读 `/releases/latest` 的 **302 跳转**，`Location` 头里直接带着 tag，
  不消耗配额。API 只在降级路径上用（跳转和 API 都试，最后才放弃）。
- **下载后必须过校验**：先看魔数是不是 `PK`（防盗链页面、HTML 错误页），
  再看包里有没有 `module.prop` 和 `customize.sh`（防残缺包）。不合格直接丢弃，绝不解包。
- **安装分四级**：`magisk --install-module` → `ksud module install` → `apd module install`
  → **APatch 目录级兜底**。前三个 CLI 谁在谁优先。
  - APatch 到目前**没有公开的模块安装 CLI**，所以走到第四级：解包到临时目录，
    比对包内 `id` 与自身一致后，逐项覆盖进 `/data/adb/modules/<id>`，旧版先备份成 `.bak`。
  - 覆盖时**只换模块文件，不动运行时产物**（`fix.log` / `update.zip` / `update.state` /
    `.dnsguard.pid` 等一律跳过），免得把日志和状态清掉。
  - 包内 `id` 与自身不一致 → **拒绝覆盖**（防止被别的模块顶掉）。
  - 四级全不可用才落到「只下载、告诉你路径、自己去管理器装」。
- 每一级都有前置校验，因为这一步是**替换掉模块自己** —— 出错的下场是重启后模块消失，
  用户一脸懵。所以「无声无息地手动解包覆盖自身」这种操作被明确排除。
- **顺手改 `module.prop` 的 description**：根管理器的模块列表里就能直接看到
  `[有新版本 vX.Y]`，不用点进来。没有更新时自动还原。

### 环境

- Wear OS 库引入（`wearable.jar` + 权限 XML）
- GitHub Hosts 加速（含动态守护）

### 维护

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

> 不是懒得做 —— 这几个数确实没有可写的寄存器。

---

## 明确不做的（红线）

这些不是「懒得做」，是**试过、或者明确知道会出事**：

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
│   └── framework/com.google.android.wearable.jar
├── vendor/overlay/
│   └── framework-res__auto_generated_rro.apk    （可选）power_profile 修正
└── META-INF/com/google/android/    Magisk 兼容壳（APatch 走 customize.sh）
```

### 改属性的正确姿势

- **加属性**：改 `lib/prop.list`（一行 `scope|key|variant|value|原因`），再同步 `system.prop`
- **ro.\* 属性**：`system.prop` 与 `prop.list` 两边都要写，只写一边总有一半不生效
- **persist.\* 属性**：卸载不会自动清，`uninstall.sh` 会从 `prop.list` 自动抓取
- **改完**：重刷模块或重启

---

## 安装

1. 下载对应包型（见下表）
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
[09-24 20:51:07] 开机了。先看这锅参数到底虚了多少。
[09-24 20:51:09] 属性清单[hsc]：命中 30 项，未生效 0 项，按变体跳过 0 项
[09-24 20:51:09] 充电[post-fs-data]：存在 4 个节点，写入成功 4 个
[09-24 20:51:09] ── post-fs-data 结束 ──
```

---

## 常见问题

**Q：内存显示 3GB 是真的吗？**
A：是。8GB 是原厂写的，这颗表实际就 3GB。这条上它是真不胖，胖的是那行 `ram.set32g`。

**Q：装了 V4A 会冲突吗？**
A：不会。本模块不碰 V4A 任何文件；带音效的包是把 V4A 原封不动并进来的。

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
A：根管理器删模块 + 重启。内置 `uninstall.sh` 会清掉 persist 覆盖并停掉守护进程。卸载后虚标回来是**正常现象**，说明清干净了。

---

## 适用范围

| 项 | 说明 |
|---|---|
| 适用 | SL8541E / SC9832E + 和顺成（HSC）方案 |
| 不适用 | 其他方案（属性名对不上，表现是「装了个寂寞」） |
| 不改 | 屏幕密度、蓝牙版本、信号强度、温控、色彩 |
| 不做 | Google WebView、SurfaceFlinger 色彩、CPU governor |

**想刷到别的表上？** 结果大概率是装了个寂寞，或者写进一个不存在的
充电节点然后静默失败。不建议。

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
- DeepSeek —— 代码撰写、重构、踩坑记录
- ShadySquirrel / 小白杨 —— ViPER4Android v6.0.1（Magisk 移植）

## 许可

[MIT License](LICENSE)

---

> 该榨的榨完了，剩下的不是代码能解决的。
> 有问题带日志来，别带玄学。
