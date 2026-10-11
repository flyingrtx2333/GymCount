# 页面样式检查与统一

2026-10-09。本轮修改已随 iOS 和 Watch 配套 1.1.3 (20) 发布到 TestFlight；Apple 状态 VALID / IN_BETA_TESTING，已在内部测试组 flyingrtx。Delivery UUID：49ad314b-ac94-4612-a6d8-b378c1b93a50。构建与凭证：[TestFlight-1.1.3-20](/Users/xiangjunsheng/GymCount/build/TestFlight-1.1.3-20)。

此前共用黑底、薄荷绿和深灰表面色，但手表页面分别使用 -6、-8 等顶部补偿，标题占用高度也不一致；iOS 主按钮与次按钮使用不同字号，列表和采集页未统一导航标题显示模式。

| 规范 | Watch | iOS |
| --- | --- | --- |
| 页面与字体入口 | GymStyle、gymPageContent、gymPage、GymHeader | Studio、原生导航标题 |
| 正文 / 主次按钮 | 14 / 14 半粗 | 17 / 17 半粗 |
| 辅助文字 | 11；行内数值 12 | 14；系统列表保留原生文字层级 |
| 主次按钮最小高度 | 44 | 48 |
| 页面横向边距 | 10 | 自定义内容 22；系统列表保留原生边距 |
| 常规内容间距 | 6 | 自定义采集内容 16 |
| 标题顶部布局 | 短标题与时间并排；长标题或带操作的整行标题避开时间 | 列表、设置、采集、核对页使用紧凑导航标题 |

计数、重量等数值按其作用保留独立的大号字体；启动页保留居中品牌布局。正常用户入口未使用的旧 CounterDebugView 保持原状。

已调整手表首页、训练计数、历史、设置、器械重量调节、训练中重量编辑、采集、结果核对、备注及动作选择弹窗和帮助页。重量编辑保持原来的四档增减和保存逻辑；设置保存继续位于顶部。40mm 设置行用单行标签和辅助数值字号，避免中文单位把标签挤成两行。

手机调整主次按钮字体与高度、训练开始及加次数按钮、列表和采集页面标题，以及采集页边距。首页的品牌标题、系统导航标题和数据数字按各自角色保留不同字号。

验证：Watch Release 模拟器构建通过；4 项 Watch 回归、2 项 iOS 界面回归通过。9 个 Watch 页面状态在 40mm、46mm 共 18 张隔离截图核验，未启动采集或上传；iPhone 界面测试截图覆盖首页、设置、开发者工具、采集页、训练中及保存后的历史。采集的超时和取消仍有测试覆盖。iPhone 的相机不可用提示来自模拟器，不代表真实设备失败。最后一次修改仅为设置重量行的字体和单行布局，已重新构建及双尺寸截图核验。隔离手表副本已卸载。

测试结果：build/StyleConsistencyWatch.xcresult、build/StyleConsistencyPhone-final.xcresult。

截图与构建证据：[StyleAudit-20261009](/Users/xiangjunsheng/GymCount/build/StyleAudit-20261009)。

![Watch 首页](/Users/xiangjunsheng/GymCount/build/StyleAudit-20261009/watch-46-home.png)

![Watch 设置，小尺寸](/Users/xiangjunsheng/GymCount/build/StyleAudit-20261009/watch-40-settings.png)

![Watch 历史](/Users/xiangjunsheng/GymCount/build/StyleAudit-20261009/watch-46-history.png)

![Watch 训练计数](/Users/xiangjunsheng/GymCount/build/StyleAudit-20261009/watch-46-counter.png)

![Watch 重量编辑](/Users/xiangjunsheng/GymCount/build/StyleAudit-20261009/watch-46-weightinput.png)
