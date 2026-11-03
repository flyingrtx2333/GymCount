# TestFlight 1.1.8 (54)

2026-11-03，iPhone 与配套 Watch 一起发布内部 TestFlight。

| 项目 | 结果 |
| --- | --- |
| 代码提交 | `82f02b30bcf84e4b739338399b395d0fedaef047` |
| 分支 | `codex/gymcount-cleanup-20261011`，已推送 |
| Delivery UUID / ASC Build ID | `7eeaccd6-e3dc-47a3-9095-34b7e9a15e26` |
| Apple 处理 | `BUILD-STATUS: VALID` / `INTERNAL_ONLY` |
| 内部测试 | `IN_BETA_TESTING`，`flyingrtx` 组列表确认包含本构建 |
| 测试说明 | `zh-Hans`、`en-US`，已写入并逐项回读一致 |
| IPA SHA-256 | `54bac783d72c747342caeaaac0f42bf07dd0cdac2cc595bd1c95ccfe202a4c3a` |

## 改动

- iPhone Duo 使用原生底栏和分栏导航，完善展开、折叠、边缘间距、阅读宽度和输入焦点处理。
- 完善记录详情、传感器与分组时间轴、趋势、补记，以及备份文件命名、系统保存面板和恢复确认布局。
- 统一 Watch 页面标题、控件和白金样式；实时次数与完成反馈共用新鲜完成事件，结束补算保持静默。
- Release 不编入开发者采集页面和采集唤起代理，不声明相机权限；正常训练、反馈、报告和传感器同步仍保留。
- 集中提交此前已授权、部分已随旧版本发布但未提交的改动，共 136 个文件；本次说明按最终发布内容整理。

## 验证

- 发布源码由上述 Git 提交直接导出，497 个文件 SHA-256 核验通过。7 个文件仅存在 Git 规定的 CRLF→LF 归一化，已分别记录；没有用预览工程替代生产工程。
- 242 个应用源码与资源在归一化前与最新原生验收副本逐字节一致，沿用相同源码的配套 iPhone／Watch、独立 iPhone Release 构建结果。
- 当前版本在 Aqua 会话重新完成双端签名归档与导出。IPA 中两个生产 Bundle ID、1.1.8 (54)、配套关系、严格签名、HealthKit 和 Watch Siri 签名／profile 权限通过；保留既有 HealthKit 弃用及元数据编译提示，未声称零警告。
- 对实际导出的二进制检查：开发者采集页面不存在；正常训练同步、传感器详情、Watch 反馈存储与触觉调用保留。相机权限声明不存在。
- 回读最新原生结果：Duo / iOS 27.1 与 SE / iOS 26.5 的真实 82 条历史备份保存、导入预览、合并恢复分别 1 项通过；41mm Watch 英文动作与重量标题 1 项通过，均无失败和运行时告警。两个隔离存储及保存的备份均保持 82 条原始汇总一致。
- 其他已完成的原生流程及其早期失败／最终复验边界见 [全页检查](full-ui-audit-20261103.md)、[Duo 适配](ios-duo-20261103.md) 和 [剩余问题完善](remaining-ui-refinement-20261103.md)，没有将含失败的历史结果包概括为全部通过。

本次没有新增真实佩戴计数、振动／声音、双端物理传输、HealthKit 或 Siri 口语验收；未覆盖用户安装与训练数据，未创建模拟器。正式商店 1.1.7 仍为 `READY_FOR_SALE`，未创建或提交正式商店 1.1.8。三个临时 Aqua 发布任务已移除。

## 产物

完整归档、IPA、源码快照、摘要、构建／上传日志、Apple 状态、测试说明回读和内部组凭证：

`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/TestFlight-1.1.8-54/`

本机隔离发布目录：`/private/tmp/GymCount-TestFlight-1.1.8-54-20261103/`。`build-release-verification.json` 汇总发布凭证，`git-delivery.json` 记录最终文档提交与远端一致性；私有训练原始数据和 API 凭据未放入仓库或发布证据副本。
