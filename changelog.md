# 更新日志

## v1.6

- **动画实现还原成 v1.2 原样写法**：去掉 v1.5 加的"读回校验 + 重试 + 改 XML"，
  只保留「先写 1.0 → sleep 1 → 写目标值」两步法（用户实测反馈改复杂了反而不对）
- 新增开机**清理空文件夹**（只删空目录，用 `rmdir` 保证不会误删有内容的目录）
- 修好 **`service.sh` 漏调 `wait_boot()`** 的回归：动画必须在开机完成之后才写，
  否则会被 system_server 的初始化覆盖
- 动画段新增诊断日志（动手前/写完后的真实读值 + settings 原始输出），便于定位问题

## v1.5

- 修复 v1.3/v1.4 引入的**动画时序回归**：`service.sh` 漏调 `wait_boot()`，
  导致动画在开机完成前写入、随即被系统覆盖 —— 整段静默失效
- 动画写入加入读回校验与重试（**注：v1.6 已按用户反馈移除**）
- `lib/common.sh` 在 `set -u` 的调用环境里可安全 source

## v1.4

- **支持从 GitHub 自更新**：模块卡片上的「更新」按钮（读 `update.json`），
  或命令行 `lib/install.sh install`
- 更新器：检查走 `/releases/latest` 的 302 跳转（不消耗 API 配额）；
  下载后校验 zip 魔数与包内 `module.prop`/`customize.sh`；
  安装分四级（magisk → ksud → apd → APatch 目录级兜底）
- 两次点击保护：点一次检查，再点一次才安装

## v1.3

- **重构**：抽出 `lib/common.sh` 公共库与 `lib/prop.list` 属性清单，
  去掉三处重复代码（属性写三遍、充电块写两遍、电池格式化抄三份）
- 补上 v1.2 漏掉的强制覆盖：`ro.hsc.statistics` / `ro.hsc.iot` /
  `add.salesservices.register` / `ro.soter.support` / `persist.logd.*` / `af.resampler.quality`
- 健壮性：`resetprop` 缺失时退回 `setprop`；属性先读后写；
  节点数值统一解析；`service.sh` 防重入；DNS 守护改用 pidfile
- 文案全面重写（大肥鱼体）

## v1.2

- 新增 WebUI：状态页 / 排查 FAQ / 关于
- 新增 `sys.use_fifo_ui=1`（UI 实时优先级）
- 充电 3A 修正为 µA 单位、开机早期写入
- RRO `power_profile` 修正（可选组件）
- GitHub Hosts 动态守护

## v1.1

- 关 ZRAM、关日志、动态 DNS、充电加速
- Wear OS 库注入

## v1.0

- 首个正式版：剥离虚标（5G / CPU / RAM / ROM）、关闭云控（APR / IoT / 统计 / 心跳）、
  关闭指纹与人脸、开启双击后台 / 锁屏壁纸 / 开发者选项 / 相机重对焦、
  dex2oat 四核修正（`4,5,6,7` → `0,1,2,3`）、TCP 调优、动画修复
