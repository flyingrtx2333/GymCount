# App Store 1.1.7 (53)

2026-10-31，按用户选定的白金精简海报更新商店。1.1.6 (52) 已核实上架，本次新建 1.1.7 并提交审核，发布方式为审核通过后自动上线。

## 提交结果

- Delivery UUID / ASC Build ID：`ac85b5a8-1144-4600-8b31-afa3c3bb3b5d`。
- Apple：`BUILD-STATUS: VALID`；ASC：`VALID / APP_STORE_ELIGIBLE`。
- TestFlight：`IN_BETA_TESTING`，内部组 `flyingrtx` 包含 53，中英文测试说明已写入并独立回读确认。
- App Store Version ID：`4ca2c31b-c641-4233-b5ec-b824d96de594`。
- Review Submission ID：`8457f91d-3b57-432e-bdd5-b6ec7fc65d80`。
- 提交后版本与审核均为 `WAITING_FOR_REVIEW`；`AFTER_APPROVAL`。提交不代表已公开替换。

## 素材

中英文各 5 张 iPhone 海报，均为 1320 × 2868 PNG，按顺序展示手表计数、整场报告、分组与传感器时间轴、训练趋势、记录与补记。删去品牌装饰、编号、分类标题、功能小字和页脚，仅保留主标题与原生界面。10 张全部 `COMPLETE`，上传源校验和与顺序回读通过。

Watch 各 3 张已审核截图继承自 52，文件名、校验和及顺序一致。商店名称、介绍、关键词、推广文案、支持链接和审核联系人保持；更新说明准确描述本次商店展示更新。

原生界面使用隔离营销示例，摄影和硬件画面为生成素材并嵌入原生界面。传感器波形不作为真实测量或准确率依据。审核说明已披露示例与生成摄影来源。

## 构建范围与验证

从已上线 52 的精确发布副本归档，仅两个有效工程的营销版本和构建号改为 1.1.7 (53)，480 文件范围核验、还原版本文本后逐字一致。应用代码、资源、权限、算法和数据格式未改变；保留独立测试目标原有营销版本。

Aqua 正式签名归档和导出通过；iPhone/Watch 版本、配套关系、严格签名、HealthKit、Watch Siri/profile 与 Intent 资源核验通过。IPA SHA-256：`81d4776030b429a40b8bd8ca1a90c3a0e6fe2c478e96fff76f446fec02cba4e4`。

两个工作区工程文件经原 52 摘要保护后同步至上传源码。未提交 Git 或推送，未覆盖用户设备安装或数据；本轮没有新增真机功能验证。

## 产物与凭证

- 正式构建产物：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/AppStore-1.1.7-53/`。
- 海报、原图包与商店 API 回执：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/store-posters-platinum-v3-20261029/`，其中 `store-update-20261031/appstore-verification.json` 记录提交结果。

