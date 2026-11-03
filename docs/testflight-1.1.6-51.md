# TestFlight 1.1.6 (51)

2026-10-29 发布，iPhone 与配套 Watch 同为 1.1.6 (51)。

## 本次内容

- Watch 训练页的手动分组移入更多菜单，保留暂停和结束主操作。
- iPhone 整场报告与传感器时间轴显示淡金分组区域、首末完成点竖虚线和组名。
- 手机拆分／合并组后，时间轴按有效分组显示；单次组不虚构时长，缺少可靠时间起点不伪造对齐。

计数算法、自动分组规则及 WatchConnectivity 格式保持。

## 发布核验

- Delivery UUID / ASC Build ID：`8702bb6b-ebd2-4e03-a7ec-4d3bc2afb025`。
- Apple：`BUILD-STATUS: VALID`、`INTERNAL_ONLY`、`IN_BETA_TESTING`。
- 内部组：`flyingrtx`，已核对包含本构建；`zh-Hans`、`en-US` 测试说明写入并回读。
- 正式商店版本及构建关联保持不变，本次仅发内部 TestFlight。
- 配套工程 Aqua 签名归档与导出通过；IPA 双端版本、生产 Bundle ID、严格签名、HealthKit 权限及配套关系通过；Watch Siri 权限和 Intent 元数据通过。
- 478 个发布源文件摘要核验；243 个应用源码／资源／权限文件与已验收副本一致。两个有效工程共 18 处构建号同步至 51。
- IPA SHA-256：`d50c3c5abb05a20ae6c52b68956893186ed64a27ec6f6c90312643fe63f29213`。

## 页面验证与边界

沿用相同应用源码的两个 iPhone 工程及 Watch 构建、大屏 iPhone 2 项、小屏 iPhone 1 项、Watch 1 项实际原生页面检查。隔离存储中的 82 条真实 Watch 历史保持一致，草稿已清理；没有新增模拟器。

原生时间轴检查使用真实采样，并通过手机拆分功能核对单次组与两组区域；不将人为拆分后的记录描述为原始采样天然分组或自动分组精度验证。没有新增真机佩戴、震动、Siri 口语、健康采集或真实双端传输验收。

沿用既有 HealthKit 弃用、采集闭包引用及 iPhone AppIntents 提示，无新增编译警告。用户安装及训练资料保留；本次未提交 Git 或推送。

## 产物与证据

- 完整归档、IPA、源文件快照、SHA-256、上传与 Apple 状态、内部组和本地化回读：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/TestFlight-1.1.6-51/`。
- 原生页面证据：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/set-regions-20261029/`。
- 实现说明：[分组入口与时间轴](set-regions-20261029.md)。
