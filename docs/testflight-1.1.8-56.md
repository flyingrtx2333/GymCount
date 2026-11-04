# TestFlight 1.1.8 (56)

2026-11-04，发布手机同步状态跳变热修复，iPhone 与配套 Watch 构建号一致。

| 项目 | 结果 |
| --- | --- |
| 发布源码 | `110f9e20320297b372ab96cfa687f133d2f6bcf6`，已推送 `codex/gymcount-cleanup-20261011` |
| Delivery UUID / ASC Build ID | `04590ee6-ffc5-472e-9859-e846fccc1996` |
| Apple 处理 | `BUILD-STATUS: VALID` / `INTERNAL_ONLY` |
| 内部测试 | `IN_BETA_TESTING`，`flyingrtx` 组已回读确认包含本构建 |
| 测试说明 | `zh-Hans`、`en-US` 已写入并回读一致 |
| IPA SHA-256 | `2949df5e7b3e674aa393580ac1f4e188894c8abb4030dd6da49b8e0f7fe74b79` |

## 修复

- 接收超时只保留一个可取消任务，后续进展延长空闲截止时间，完成／失败时取消旧任务。
- 实时通道不可达不再覆盖后台接收状态；自动请求按单调时钟合并，手动重试保留。
- 手机右上角入口固定手表图标；详情不因其他时间轴更新反复强制请求缺失采样。

Watch 业务源码与 55 相同，仅随配套包递增构建号。本次未改后台、计数算法或记录持久化与回执协议。详细机制见 [同步状态修复](watch-sync-flicker-20261104.md)。

## 验证

- 506 个提交文件从 Git 直接生成发布快照并核验摘要，244 个应用文件与本次最终验证副本一致；3 个既有文件仅存在 Git 的换行归一化。
- 沿用相同应用源码的两个 iPhone 工程及配套 Watch Release 编译结果，以及真实时钟／Task 的截止时间续期、旧任务取消、一次空闲超时、完成取消、自动请求合并、手动重试与重连检查。
- 本次重新完成 Aqua 签名归档、导出、IPA 严格签名、双端 1.1.8 (56)、生产 Bundle ID、配套关系、HealthKit 与 Watch Siri 权限核验。实际 IPA 的 iPhone 二进制存在 `WorkoutSyncActivity`，编译日志确认编入该源文件；开发者采集运行时名称和相机权限继续排除，普通同步与六种动作保留。
- 苹果上传、处理、内部组和中英文说明回读完成。签名与构建保留已有 HealthKit 弃用、弱引用捕获和 AppIntents 提取提示，不声称零编译警告。
- 手机与 Watch 当前均显示不可连接，尚未完成本次真机同步复验；没有用本地计时器检查冒充 WatchConnectivity 实机验证。用户现有安装和记录保留，没有创建模拟器。
- 3 个临时桌面发布任务已移除；正式商店 1.1.7 仍为 `READY_FOR_SALE`，未创建或提交正式商店 1.1.8。

## 产物

归档、IPA、提交源码压缩包与摘要、构建／上传日志、Apple 状态、内部组与测试说明回读、针对性验证结果：

`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/TestFlight-1.1.8-56/`

本机隔离发布目录：`/private/tmp/GymCount-TestFlight-1.1.8-56-20261104/`。凭据及私人训练原始文件未放入仓库或发布证据。
