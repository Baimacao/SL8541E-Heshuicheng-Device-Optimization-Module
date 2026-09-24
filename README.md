# SL8541E 和顺成方案设备优化模块

[English](README-EN.md) | 中文

由 [B站白马曹](https://space.bilibili.com/1329200878) 与 DeepSeek（大肥鱼）共同制作。

面向 **展锐 SL8541E / SC9832E + 和顺成（HSC）方案手表**，Android 8.1。

兼容 **Magisk / APatch / KernelSU**。

## 起因

原厂 `build.prop` 里塞了一堆虚标：

```properties
ram.set32g=8GB        # 实际 3GB
rom.set32g=128G       # 实际 32GB
persist.sys.5g=true   # 没有 5G 硬件
persist.sys.cpu=10    # 四核标十核
```

同时还有一整套静默回传（APR / IoT / 统计 / 心跳）。

官方修正虚标的方式是恢复出厂设置，所有数据全清。本模块提供不恢复出厂的替代方案，顺手把云控也关了。

## v1.2 主要更新

- **UI 实时优先级**：`sys.use_fifo_ui=1`，让 UI / RenderThread 用 SCHED_FIFO 防掉帧
- **WebUI**：模块卡片点开即可查看状态、排查常见问题、看模块信息
- **充电 3A**：修正了之前充电节点的单位问题（µA 而非 mA）
- **RRO 修正**（可选）：power_profile.xml 修正，让耗电排行数据准确

## 功能清单

### 虚标剥离

| 项目 | 原值 | 现值 |
|---|---|---|
| 5G 图标 | true | false |
| CPU 显示 | 10 | 4 |
| 内存显示 | 8GB | 3GB |
| 存储显示 | 128G | 32G |

### 云控关闭

APR 全系、心跳、BS 服务、统计、IoT、UDP 数据收集、销售服务注册。

### 生物识别关闭

指纹（总开关、锁应用、启动应用、Soter 支付）、人脸解锁。

### 功能开启

相机重对焦、双击最近任务、锁屏壁纸、开发者选项、护眼模式、快充提示、霍尔相机、抬腕唤醒。

### 性能与网络

- **dex2oat 4 核修正**：CPU set 从错误的 `4,5,6,7` 改为 `0,1,2,3`
- TCP 缓冲区、fast open、TIME_WAIT 复用、低延迟模式
- 拥塞算法 `cubic`（本内核无 BBR）
- 动态 DNS 守护：GitHub 不通时自动切换 IP

### 音频

- 重采样质量 `af.resampler.quality=4`
- **不碰 V4A**：不动 `audio_effects.conf`、`soundfx` 目录、V4A 任何文件

### 内核

- I/O 调度 `noop`（本内核不支持 `deadline`）
- swappiness 保持原厂 `150`
- 强制关闭 ZRAM
- 关闭系统日志（缩小 logd 缓冲区）

### 充电加速

- 输入限制从 500mA 提升到 3000mA（3A）
- 节点单位是 **µA**，写入值为 `3000000`
- 必须在 boot 早期写入（`post-fs-data` 阶段），否则节点锁定写不进去
- **实际充电速度取决于充电器和线材**

### 动画修复

- 恢复 SurfaceFlinger 背压与 vsync 同步（`debug.sf.*` 从 1 改回 0）
- 修复原厂为省电导致的动画跳帧
- 动画缩放 0.75 / 0.75 / 0.5

### WebUI

圆屏适配的状态页面，三个 Tab：

- **状态**：所有功能项的实时状态
- **排查**：11 个常见问题的自助解决步骤
- **关于**：模块信息、作者、链接

**注意**：状态是开机快照。点模块卡片的「操作」按钮可刷新。

### 环境

- Wear OS 库引入（`wearable.jar` + `wear-service.jar` + 权限 XML）
- GitHub Hosts 加速（含动态守护）

### 维护

- 开机清理电池校正文件
- 卸载时自动清除所有 persist 属性

## 硬件上限

| 输出设备 | 采样率 | 位深 |
|---|---|---|
| Speaker | 44100 | 16bit |
| 有线耳机 | 44100 | 16bit |
| 蓝牙 A2DP | 44100 | 16bit |
| USB DAC | 动态 | 动态 |

采样率 / 位深 / 蓝牙版本 / 信号强度，全部由硬件锁定，**改不了**。

想听高采样率，**只能外接 USB DAC**。

## 文件结构
