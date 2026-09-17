# SL8541E 和顺成方案设备优化模块

[English](README-EN.md) | 中文

由 [B站白马曹](https://space.bilibili.com/1329200878) 与 DeepSeek（大肥鱼）共同制作的系统优化模块。

适用于 **展锐 SL8541E / SC9832E + 和顺成（HSC）方案手表**，Android 8.1。

兼容 **Magisk / APatch / KernelSU**。

## 起因

原厂 `build.prop` 存在大量虚标：

```properties
ram.set32g=8GB        # 实际 3GB
rom.set32g=128G       # 实际 32GB
persist.sys.5g=true   # 无 5G 硬件
persist.sys.cpu=10    # 4 核标 10 核
```

同时有 APR、IoT、统计等后台回传。

官方修正虚标需要恢复出厂设置，本模块提供不恢复出厂的替代方案，并关闭云控。

功能

虚标剥离

项目 原值 现值
5G 图标 true false
CPU 显示 10 4
内存显示 8GB 3GB
存储显示 128G 32G

云控关闭

APR 全系、心跳、BS 服务、统计、IoT、UDP 数据收集、销售服务注册。

生物识别关闭

指纹（总开关、锁应用、启动应用、Soter 支付）、人脸解锁。

功能开启

相机重对焦、双击最近任务、锁屏壁纸、开发者选项、护眼模式、快充提示、霍尔相机、抬腕唤醒。

性能与网络

· dex2oat 4 核修正（CPU set 4,5,6,7 → 0,1,2,3）
· TCP 缓冲区、fast open、TIME_WAIT 复用、低延迟模式
· 拥塞算法保持 cubic（本内核无 BBR）

音频

· 重采样质量 af.resampler.quality=4
· 不碰 V4A：不动 audio_effects.conf、soundfx 目录、V4A 任何文件

内核

· I/O 调度 noop（本内核不支持 deadline）
· swappiness 保持原厂 150

环境

· Wear OS 库引入（wearable.jar + wear-service.jar + 权限 XML）
· GitHub Hosts 加速

维护

· 开机清理电池校正文件
· 动画两步修复（窗口 0.75 / 过渡 0.75 / 时长 0.5）

硬件上限

输出设备 采样率 位深
Speaker 44100 16bit
有线耳机 44100 16bit
蓝牙 A2DP 44100 16bit
USB DAC 动态 动态

采样率/位深由硬件决定，只能通过 USB DAC 提升。蓝牙版本、信号强度同理，改不了。

文件结构

```
SL8541E_Config_Fix/
├── module.prop
├── system.prop
├── post-fs-data.sh
├── service.sh
├── action.sh
├── customize.sh
├── system/
│   ├── etc/
│   │   ├── hosts
│   │   └── permissions/com.google.android.wearable.xml
│   └── framework/
│       ├── com.google.android.wearable.jar
│       └── wear-service.jar
└── META-INF/com/google/android/
    ├── update-binary
    └── updater-script
```

安装

1. 下载 SL8541E_Config_Fix_v1.0.zip
2. Root 管理器 → 模块 → 从本地安装
3. 重启
4. 点模块卡片「操作」按钮验证

前置：已 Root、Bootloader 已解锁、已备份系统。

验证

```bash
su

# 属性层
getprop persist.sys.5g              # false
getprop persist.sys.cpu             # 4
getprop dalvik.vm.dex2oat-cpu-set   # 0,1,2,3
getprop af.resampler.quality        # 4

# 内核层
cat /proc/sys/vm/swappiness         # 150
cat /sys/block/mmcblk0/queue/scheduler  # 【noop】
cat /proc/sys/net/core/rmem_max     # 8388608

# 设置层
settings get global window_animation_scale  # 0.75
```

或直接点「操作」按钮一次性查看。

常见问题

Q: 内存显示 3GB 是真的吗？
A: 是。8GB 是原厂虚标。

Q: 装了 V4A 会冲突吗？
A: 不会。模块不碰 V4A 任何文件。

Q: 采样率能提到 96k/24bit 吗？
A: 不能。硬件锁 44100/16bit，只能 USB DAC。

Q: 续航变差？
A: 模块不涉及 CPU 频率与 governor，理论无影响。

Q: 会变砖吗？
A: 只改属性、设置、sysctl、注入文件，不改分区。但仍建议备份。

Q: 怎么恢复原状？
A: 删除模块 + 重启。如需清除 persist 覆盖：resetprop --delete persist.sys.5g 等。

适用与限制

项 说明
适用 SL8541E / SC9832E + 和顺成方案
不适用 其他方案
不改 屏幕密度、蓝牙版本、信号强度
不做 zram（实测不需要）

反馈

Issue 请附：操作按钮完整输出、fix.log、设备型号与系统版本、复现步骤。

致谢

· B站白马曹 —— 项目发起、硬件测试
· DeepSeek（大肥鱼） —— 代码撰写、方案设计

许可

MIT License

---

🐟 大肥鱼
这块表的天花板摸清楚了，能做的都做了。

```
