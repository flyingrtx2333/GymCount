# App Store 1.1.6 (52) 与商店素材更新

2026-10-29，手机与配套 Watch 商店页面更新，应用功能沿用 TestFlight 1.1.6 (51)。

## 商店页面

- 简体中文与英语各 5 张 iPhone 截图：整场报告、分组与传感器、记录、趋势、多组补记。
- 两种语言各 3 张 Watch 截图：首页、保存报告、重量输入；统一白金风格。
- iPhone 1320×2868 JPEG；Watch 416×496 PNG，无透明通道。Watch 原生 41mm 截图等比适配商店尺寸，未拉伸或重画界面。
- 更新副标题、介绍、关键词、推广文本、版本更新说明及审核操作说明；保留中英文名称、联系人、隐私地址和原有分级。
- 全部 16 张素材经 Apple 处理为 COMPLETE，上传源 MD5、顺序与最终关联均已回读。

## 来源与验证边界

页面来自同一版实际原生 App。隔离展示副本用非个人示例记录呈现功能；传感器波形为示意数据，非实际测量和算法准确率证据。手机截图外框标注展示示例，审核说明明确来源。生产代码和正式安装数据没有改写。

手机中英文 2 项原生流程通过，12 张原生图片中选取 10 张；Watch 中英文 2 项通过，18 张原生图片中选取 6 张。242 个手机与 129 个 Watch 源文件／资源摘要与生产源码一致。复用现有一台大屏手机及唯一 Watch 模拟器，未新增设备。手机专用副本已移除，避免示例通知残留。

素材审查曾发现 Chrome 改变输出尺寸后的中文 Watch 残影；改用固定尺寸的新页面后重新渲染并逐张复核，最终素材无此问题。

## 发布核验

- 双端版本：1.1.6 (52)，生产 Bundle ID 与配套关系通过。
- Delivery UUID / Build ID：`066492c3-4229-4793-b468-23e997d23220`。
- Apple：BUILD-STATUS: VALID / APP_STORE_ELIGIBLE。
- 内部 TestFlight：IN_BETA_TESTING，flyingrtx 组和中英文说明已回读。
- App Store Version ID：`35cb7342-bd78-4d54-a0e4-f9b48c988c59`。
- Review Submission ID：`5c26b8b6-2b6c-41b9-abc0-90dad8675eb1`。
- 提交时版本状态：`WAITING_FOR_REVIEW`；审核状态：`WAITING_FOR_REVIEW`。
- 发布方式：AFTER_APPROVAL。当前公开版仍为 1.1.5；新版审核通过前不宣称公开页已替换。
- 配套工程 Aqua 签名归档、正式导出、严格签名、HealthKit 与 Watch Siri 权限通过；479 个发布源文件校验。
- IPA SHA-256：`1a913031c1ad5a5676bc45f2f1565960a0375e82ecb0d1818cb06c4305520cf9`。

本轮应用代码与 51 版一致，未重复进行实际训练、真机 Siri、健康采样或手机手表同步验收。没有提交 Git 或推送，也没有覆盖用户现有 App 与训练数据。

## 产物

完整归档、IPA、发布源码快照、原生截图、营销排版、元数据、上传及审核回执：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/AppStore-1.1.6-52/`。

![手机商店截图](/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/AppStore-1.1.6-52/store/phone-preview-zh-Hans.jpg)

![手表商店截图](/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/AppStore-1.1.6-52/store/watch-preview-zh-Hans.png)
