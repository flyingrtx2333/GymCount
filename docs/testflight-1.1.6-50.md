# TestFlight 1.1.6 (50) · 2026-10-28

## 结果

- iPhone / Apple Watch：1.1.6 (50)。
- Delivery UUID / ASC Build ID：`a8ae6848-98fc-4208-8d90-134d6f9a75e9`。
- Apple：`BUILD-STATUS: VALID`；内部状态 `IN_BETA_TESTING`，构建为 `INTERNAL_ONLY`，内部组 `flyingrtx` 已确认包含该构建。
- 简体中文与英文测试说明已写入并回读，正式商店版本与构建关联未改。
- IPA SHA-256：`95de34aef448459988ee30257ea55d7a3b36e3a6fb79279419720c605b9f6aa0`。

## 范围

包含当前已授权的整场训练与报告、组操作与时间轴、分段原始传感器同步和训练记录备份、报告布局、Watch Siri、连续训练日数及每日提醒。手机与手表需要同时更新。

发布采用当前工作区快照，没有将未提交代码描述为已提交。归档前 476 个源文件逐文件校验，247 个应用源码／资源与最终验证副本一致；本轮仅递增版本号、构建号和记录发布凭证，没有修改应用行为。

原计划上传 1.1.5 (50)，Apple 返回验证错误 90062：1.1.5 已获批，`CFBundleShortVersionString` 必须更高。故改为 1.1.6 (50) 重新签名归档和上传。第一次归档、IPA、拒收日志及原版本工程文件保留在 `rejected-1.1.5/`。

## 验证边界

配套工程 `GymCountSync / GymCount Capture` 在 Aqua 会话完成正式签名归档和导出。实际 IPA 内两端版本一致，严格签名、Team、HealthKit、配套 Bundle ID、Watch Siri entitlement 与 profile 许可、后台训练模式、用途说明及 Intent 元数据均通过。

应用源码与此前验证一致，沿用双 iPhone 工程 Release 构建、5 项原生传感器／分组页面操作，以及真实深蹲采样的接收、原始精度、修正保留、删除优先、重启和备份恢复结果。详见 [报告传感器](report-sensors-20261028.md)；整场训练、Siri 与提醒的既有验证分别保留在对应实现记录。

本轮未新增真表 Siri 口语、健康授权与采集、佩戴计数、真实 WatchConnectivity、提醒实际送达或人工 VoiceOver 验收。未覆盖用户现有 App。保留编译警告详情，没有宣称零警告构建。

## 产物

`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/TestFlight-1.1.6-50/`

包含正式归档与 IPA、源码快照及摘要、签名／权限校验、Apple 上传与处理结果、内部组确认、更新说明回读、商店关联前后记录、原验证证据指针和安全回写凭证。源码暂存位置为 `/private/tmp/GymCount-TestFlight-20261028-50/source`。

本轮未执行 Git 提交或推送。
