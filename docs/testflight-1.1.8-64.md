# TestFlight 1.1.8 (64)

2026-11-17 发布 iPhone 与配套 Watch。源码提交 `065fb245f94e89465e1e97fce6db6457ccb0406e`，发布快照 535 文件 SHA-256 一致。

## 范围

新增 [Watch 保存分步诊断](workout-save-diagnostics-20261117.md)，覆盖文件排队、采样收尾、时间轴处理、草稿、历史及 HealthKit 保存。记录有界、独立写入，不等待日志落盘，不记录训练数值或个人标识。此前授权删除的 iOS 图表“有时长”提示随包发布，统计保持。

计数算法、模型、分组、文件队列、保存顺序、等待、超时、重试及保存状态 UI 不改。此次用于定位问题，不表示漏计或慢保存已经修复。

## 验证

- 固定 41mm Watch 模拟器使用隔离 App 标识，4 项原生测试全部通过。覆盖排队／执行耗时、返回值与错误保持、日志轮换及不可写目录、整场保存与文件读取、停止采样不等待无关文件队列；读取器另通过末行截断检查。
- 7 份相关源码与原生测试输入一致。9 份检测器／模型／时间计算源码与 63 版一致；三个保存相关文件的异步调用及次序保持。
- 独立 iPhone Release 构建、配套双端 Aqua 签名归档／导出通过。包内双端均为 1.1.8 (64)，严格签名、HealthKit、Watch Siri、配套关系和中英文资源通过；Release 未包含相机权限。
- 沿用既有 HealthKit 弃用、捕获引用及 AppIntents 编译提示。未覆盖用户安装或资料；模拟器整场保存关闭实际健康写入，不代替真机佩戴、HealthKit 等待或同步验收。

## 苹果凭证

- Delivery UUID／ASC Build ID：`4ac4e95a-7828-42f5-8bba-a77ad574b30a`。
- `BUILD-STATUS: VALID`，`INTERNAL_ONLY`，`IN_BETA_TESTING`；内部组 `flyingrtx` 已包含构建，中英文说明回读一致。
- 正式商店各版本状态及选中构建保持，没有提交正式审核。
- IPA SHA-256：`6be99e1c019db197354129e74ebcf69abb3841112cc41f3e41c023b282ac9dfd`。

完整归档、IPA、源码压缩包、分步诊断示例、原生结果及苹果回执：

`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/TestFlight-1.1.8-64/`
