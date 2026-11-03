# 记录与趋势分工合并 · 2026-10-26

沿用已选 F 白金布局与 M2 动效。本轮按用户对两页重复的反馈继续整合，不另开概念选择，不发布。

记录页保留动作/日期筛选、日历、补记、日期分组日志、编辑与删除。累计次数及整块时间分析移入趋势，首页首条记录从400.3pt上移至216.3pt，标准大屏完整记录由6条增至8条；行高68pt。

趋势统一为一个指标入口、一个图表、一份日期汇总。训练总用时、次数、最高重量、动作时长共用范围和汇总方式，移除重复的三项统计组件。默认大数字表示所选范围累计或最高值，只有明确点选图表后才显示日期桶；清除选择恢复范围汇总。

趋势支持全部动作。进入某日/周/月的原记录时显式应用动作筛选，包括清除首页原有动作限制；钻取先与当前日期范围求交集，保留返回原范围。日期列表只呈现当前指标，避免再次复制完整记录页。

时长沿用真实记录字段，未知不补零，真实零秒保留。多动作记录的时长仍是整条记录时长，不推算分动作时间。旧趋势重量/次数偏好兼容；仅在没有趋势偏好时接续原时间图的指标、汇总及折叠选择。记录快照、来源、手机修正、删除标记、同步与算法均未修改。

![实际原生页面](</Volumes/江波龙/Allprojects/GymCount/evidence/ui-concepts/records-trends-separation-20261026/native-pages.png>)

使用隔离副本中的82条真实历史记录检查：累计323次、最高70公斤、已知总用时40分34秒；历史无动作时长时显示空值及空图状态。从全部动作趋势进入最新月6条记录并返回原78条卧推筛选、跨重启保留指标/周汇总/折叠均通过。深色、375pt小屏、最大无障碍字号英文与键盘操作通过。4个原生UI方法全部通过，无结果包运行时警告。三个iPhone工程最终无签名模拟器构建通过，52个构建输入与当前源码一致，7个底层源文件与本轮前基线一致。

截图来自实际SwiftUI运行页面，仅统一缩放拼版；原图与AX保留。[完整验证](</Volumes/江波龙/Allprojects/GymCount/evidence/ui-concepts/records-trends-separation-20261026/verification.json>)、[几何记录](</Volumes/江波龙/Allprojects/GymCount/evidence/ui-concepts/records-trends-separation-20261026/layout-measurements.json>)及[原生操作录像](</Volumes/江波龙/Allprojects/GymCount/evidence/ui-concepts/records-trends-separation-20261026/native-interactions-compact.mp4>)已保存。原生结果包位于`/private/tmp/GymCount-VisualRefinement-20261026/PhoneSeparation*.xcresult`。

本轮没有真机复验、签名归档或发布；人工VoiceOver、物理系统减弱动态及同步仍保留原验收边界。现有用户安装和记录未操作。此前前端精修文档中的首页时间图和三项趋势指标描述为上一阶段状态，已由本轮分工合并替代。
