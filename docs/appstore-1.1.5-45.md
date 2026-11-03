# PowerReps 1.1.5（45）

2026-10-27 提交正式版审核，状态 `WAITING_FOR_REVIEW`，审核通过自动发布（`AFTER_APPROVAL`）。当前公开版本仍为 1.1.4；内部 TestFlight 已可用。

- Delivery / Build：`01509c3d-5c7c-4734-89ae-a003611a6273`
- App Store Version：`54507e01-9396-4f32-a45a-57adc52a43dd`
- Review Submission：`08c4ca4f-425e-42ed-b20b-b3ee88494b2e`
- 苹果构建：`VALID` / `APP_STORE_ELIGIBLE`
- 内部测试：`IN_BETA_TESTING`，已确认 flyingrtx 组包含本构建。

## 版本内容

训练详情新增真实采样的传感器时间轴、动作打点及逐次查看。趋势默认全部动作，加入累计概览、训练日历、动作分布及重量统计；精简界面与中英文显示。包含此前记录、补记、同步恢复及 Watch 保存提示与计数反馈改进。计数算法未改。

## 商店页面

简体中文与英语的介绍、关键词、推广文本、更新说明及审核说明均已更新，保留审核联系人。补齐苹果新要求的社交功能分级答案，不含社交功能，其他答案保留。

每种语言 5 张 iPhone 白金截图：记录、趋势、动作分析、补记、设置；3 张 Watch 原生截图：首页、器械重量、保存结果。全部由当前原生界面获取，图片处理状态均为 COMPLETE，并核对顺序与校验和。

展示记录为独立、明确标注的营销示例，不含用户真实历史或传感器资料。Watch 示例通过原生加次操作录入。营销示例不作为算法或设备准确率验证。

## 验证

发布工作区冻结 434 个文件，摘要与归档输入一致。iPhone、Watch 签名归档及正式导出通过，版本、HealthKit、配套关系及 IPA 签名有效。109 个 iOS、124 个 Watch 源码／资源与原生展示副本一致。

发布源码对 82 条真实历史重新执行手机迁移、重复接收、手机修正保留、删除不复现、备份往返／冲突、损坏文件与保存失败保留检查，趋势统计及 Watch 兼容检查通过。历史来源保持不变，没有把汇总最大重量补成组明细。

中英文原生商店展示流程 iPhone 2 项、Watch 2 项通过，无运行时告警；此前时间轴、小屏与大字体验证按源码一致性沿用。没有新增真机同步、HealthKit、震动触感或人工 VoiceOver 验收；没有覆盖用户真机安装或资料。

临时 GUI 任务均已移除，复用的 46mm Watch 模拟器恢复原关机状态。

## 产物

[iPhone 商店截图总览](/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/AppStore-1.1.5-45/store-screenshots/contact-sheet.jpg)

[Watch 商店截图总览](/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/AppStore-1.1.5-45/store-watch/contact.png)

[苹果提交回执](/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/AppStore-1.1.5-45/appstore-verification.json)

完整产物：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/AppStore-1.1.5-45/`。

IPA SHA-256：`ce67e42133b6369773d584b9b0b02b9a9354d52ea3d742bc321489420425482b`。
