# TestFlight 1.1.5（46）

2026-10-27 发布，包含配套 iPhone 和 Apple Watch。

- 苹果：`BUILD-STATUS: VALID`、`INTERNAL_ONLY`、`IN_BETA_TESTING`。
- 内部组：`flyingrtx`；中英文测试说明已写入。
- Delivery UUID / ASC Build ID：`6e7e6ef9-5d0f-48a0-9c12-c3f4fa522181`。
- 本次仅发布 TestFlight，商店审核保留 45 版。

## 改动

Watch 统一白金配色，器械重量和体重改用共用的原生输入页，支持小数、快捷加减、顶部保存与返回取消。修复首次进入读取旧临时重量和小数显示精度问题；非法输入就地提示，取消不修改已保存值。

iPhone 沿用 45 版记录、趋势、传感器时间轴和训练备份功能。未改计数算法、训练记录格式或同步协议。

## 验证

双端 Aqua 签名归档、导出及正式安装包版本、签名、HealthKit 和配套关系通过。发布源码快照包含 438 个文件，逐文件 SHA-256 核验通过；发布内容包含工作区未提交的已授权改动，不代表 Git 干净。

233 个应用源码／资源文件与已有验收输入一致。iPhone 沿用 45 版真实 82 条历史的持久化、同步重放、修正与删除保留、重启和备份恢复证据；Watch 沿用中文原生重量输入 1 项、英文与设置 2 项、恢复回归 1 项通过的结果。恢复回归发生在最后的读屏值补充之前，其后计数和持久化代码未变。本次没有重复运行这些原生用例。

未新增真机键盘、手写、佩戴、WatchConnectivity、HealthKit 权限或人工 VoiceOver 验收。既有 HealthKit 弃用、采集闭包捕获与 AppIntents 编译警告保留；未将构建或页面操作当作计数准确率证据。

用户当前安装和资料未覆盖。本次未新增模拟器，Watch 只保留现有 41mm 一台。临时 Aqua 发布任务及本次独立编译缓存已移除。

## 产物

- IPA SHA-256：`8b5a45f2e98d8e3e45702d6f39854b5e44bc136be68de08a57706d5c1ac1c2a0`。
- [完整产物与苹果回执](/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/TestFlight-1.1.5-46/)。
- [最终发布核验](/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/TestFlight-1.1.5-46/final-release-verification.json)。
- [手表实际页面](/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/TestFlight-1.1.5-46/weight-input-preview.png)。
