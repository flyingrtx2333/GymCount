# 动作完成事件与反馈整理

2026-10-31，未发布。

- 卧推、深蹲、硬拉统一使用 `DetectedRepetition` 和 `MotionDetector.onRepDetected`，保留各动作的周期数据。
- 合并运行状态、会话代号、新鲜度和重复事件检查；结束时的补算显式标为非实时事件。
- 普通／整场训练、数据采集共用 `RepCompletionFeedback`。动作完成的 WatchKit 振动调用由 5 处收为 1 处；硬拉检测器去掉 WatchKit 依赖，改为上报完成事件和原始采样时间。迟到数据不请求动作完成反馈。
- 三个旧回调 `onBenchCompletion`、`onSquatCompletion`、`onSquatCycle` 及重复的事件分发代码移除。手动按钮、保存成功和错误反馈保留。
- 动作判定门限、V8 最终分析、深蹲算法、同步格式未变；硬拉仅传递采样时间并移走触觉调用，不修改判定规则。

六条真实卧推记录回放通过，25 个新鲜完成事件与此前修复一致；卧推检测器与此前修复后的文件一致，深蹲检测器与已发布 53 版逐字一致。配套 iPhone／Watch Release 无签名构建通过，构建源码与工作区改动核对一致。没有模拟器新增、真机安装覆盖或新的真实佩戴反馈验收。

前后源码、差异、回放和构建凭证：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/RepFeedbackRefactor-20261031/`。
