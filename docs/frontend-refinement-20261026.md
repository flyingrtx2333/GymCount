# F + M2 前端精修 · 2026-10-26

沿用用户已选 F 和 M2，保留后来确定的顶部筛选。完成本轮已发现的记录、趋势、补记、详情、采集、帮助与 Watch 历史布局修正，未更改存储、模型、算法、协议或后端，未提交或发布。

## 实际变化

- 记录页首条从456pt上移到400.3pt，标准大屏完整行数由5增至6。日期—运动时间图保留，收起/展开直接可见并保留偏好；次数右对齐、运动图标保留共享资产并改善光学尺寸。
- 记录图从150pt缩至120pt，稀疏趋势图从205pt缩至148pt。大字体日期轴减少刻度，不再重叠；完整日期仍能通过点选读出。图表选中、清除、日期范围跳转保留。
- 补记改为有序组列表与细分隔线，去掉外围卡片；详情删除收进更多菜单，已知次数、重量和时长清晰呈现。
- 小屏英文键盘下保存与下一项可达。最大无障碍字号实看后又修正了Date被挤断、操作栏过高及运动时间标题截断；主要输入保留系统大字，原生日期控件和紧凑操作栏局部限制尺寸。
- 采集正常行浓缩成双行，异常仍可见；核对工具和真实上传进度弹窗更轻。此部分没有可用真实本地录像，已验证空列表导航，尚未做有数据的原生视觉与上传验收。
- 帮助使用普通正文与真实操作入口，设置中的高级工具、备份恢复、导出范围功能保留。
- Watch历史首条从257pt移到144pt，41mm首屏完整露一条。运动选项改原生选择页，统计直接展开趋势，累计次数和训练量含义明确；周切换及首页导航触控区扩为44pt。计数异常提高可见性，既有恢复、保存失败及A/M2成功提示保留。

## 实际页面

![记录、趋势、补记](</Volumes/江波龙/Allprojects/GymCount/evidence/ui-concepts/records-refinement-20261026/native-pages.png>)

图片来自真实SwiftUI运行页面。记录使用82条保留历史；补记的42.5公斤/8与6次为隔离预览内的手动输入流程，不是传感器准确率证据。三联预览仅统一缩至440×956pt，原始1320×2868截图全部保留。

[Watch历史首屏](</Volumes/江波龙/Allprojects/GymCount/evidence/ui-concepts/records-refinement-20261026/screens/refined-watch-history-first-record.png>) · [英文大字体](</Volumes/江波龙/Allprojects/GymCount/evidence/ui-concepts/records-refinement-20261026/screens/refined-trends-large-english.png>) · [小屏键盘](</Volumes/江波龙/Allprojects/GymCount/evidence/ui-concepts/records-refinement-20261026/screens/refined-compact-entry-keyboard.png>) · [实际操作录像](</Volumes/江波龙/Allprojects/GymCount/evidence/ui-concepts/records-refinement-20261026/native-interactions-compact.mp4>)

## 验证与边界

三个工程无签名模拟器构建通过，52个源码/资源输入与最终构建副本一致。大小屏、深浅色、英文大字、补记键盘与草稿、图表与详情、设置帮助、Watch历史及恢复变重量的最终结果组全部通过，没有相关运行时警告。包含发现视觉缺陷后的定点重验，不能把执行次数理解为不同功能的数量。原始结果包在 `/private/tmp/GymCount-VisualRefinement-20261026/`。

保留F原图、此前正式选择记录、本轮原生基线和变更范围。原F是三联概念，且本轮明确要求调整几何，因此没有声称达到旧概念的像素级复刻。前后比较器未调阈值：记录图MAE0.02605/相似度0.97395；大字趋势因轴与高度被主动修正，旧图比较MAE0.04167超过0.035，报告保留为几何变化记录，不以恢复重叠布局来追求相似度。逐区域文字、密度、控件、状态与几何审核见证据JSON。

最大字号内容自然滚动，不强求首屏露记录；有数据采集、真机健康/同步/上传、系统减弱动态开关、物理震动及人工VoiceOver仍需真机验收。没有覆盖用户真机安装或记录。

[完整验证结果](</Volumes/江波龙/Allprojects/GymCount/evidence/ui-concepts/records-refinement-20261026/verification.json>) · [几何测量](</Volumes/江波龙/Allprojects/GymCount/evidence/ui-concepts/records-refinement-20261026/layout-measurements.json>) · [内容密度审查](</Volumes/江波龙/Allprojects/GymCount/evidence/ui-concepts/records-refinement-20261026/content-density-review.json>)
