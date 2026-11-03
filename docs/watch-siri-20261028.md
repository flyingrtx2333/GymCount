# Apple Watch Siri 入口

2026-10-28。用户确认仅需手表语音启动，手机功能保持记录端；本轮没有提交、推送或发布。

## 使用方式

- “开始健身计数”：由 Siri 询问动作，支持卧推、深蹲、硬拉，再进入手表原有计数流程。
- “用健身计数开始卧推”：直接带入动作。
- 也可使用正式应用名“健身计数器”。英语支持 “Start PowerReps” 及 “Start Bench Press with PowerReps”。

未指定重量时沿用手表已设置的器械重量；明确提供的合法重量保留。已有训练、训练恢复未完成、正在保存或采集未完成时，不覆盖当前状态。只有启动草稿实际持久化且会话已建立，才回应开始成功。没有自动添加次数或更改算法。

## 实现

复用 `StartWorkoutIntent`、`ExerciseTypeEntity` 和现有参数标识，保留已配置快捷指令的兼容性。去掉默认深蹲及可选重量的 0 默认值，补充动作询问和启动失败反馈。`openAppWhenRun` 保持开启，运行后展示原生计数页。

App Shortcuts 新增简短启动及带动作的短语，使用中英文独立的 `AppShortcuts.strings`；保留原先两种启动说法。两个 Watch Info.plist 添加应用别名，经 `InfoPlist.strings` 本地化为“健身计数”／“Power Reps”。仅登记应用名别名，没有将整条命令登记成应用名称。

Apple 的要求是短语包含应用名，也可以采用应用别名：[Design App Shortcuts](https://developer.apple.com/videos/play/wwdc2022/10169/)、[Implement App Shortcuts](https://developer.apple.com/videos/play/wwdc2022/10170/)。帮助页给出两句实际入口说明，原过期 SiriKit 指南已更新为当前 App Intents 实现。

## 验证与边界

- Watch Release 原生测试构建、配套 iPhone／Watch Release 构建通过。Swift 编译提取出的 App Intents 元数据确认动作必填、重量可选且没有 0 默认值、打开 Watch App、保留现有 Intent 标识。
- 安装包中两种语言的所有短语键、参数占位符和应用别名齐全；中文主短语结合登记别名解析为“开始健身计数”。这是包内容与配置核验，不是 Siri 语音识别结果。
- 复用现有 41mm Watch 设备，在独立预览副本执行真实 `StartWorkoutIntent.perform()`；4 项原生测试通过，覆盖未指定动作不默认深蹲、实际启动及设置重量、重复请求不覆盖训练、非法重量、草稿写入失败不宣布成功。
- 输入为已有 82 条真实历史副本；启动检查没有伪造动作或次数，没有保存训练历史。真实源文件及原有记录保留。
- 复用原生设置／帮助流程，检查新增 Siri 说明可滚动到达；保存实际页面和操作证据。
- 新增说明的首次滚动检查因全屏滑动越过目标而失败；对照实际操作录像改为短距离拖动后通过，产品页面未因此改动。失败结果保留。

原生测试使用未签名的隔离安装，日志包含系统 HealthKit entitlement 提示，不视为健康权限、运动圆环、佩戴传感器或实际口语识别验收。未注入 Siri 识别文本，也没有把直接执行 Intent 当成真人对 Siri 说话。真表的唤醒、口语识别、动作追问与打开计数页，需安装新版后实测。

Codex 后台进程本轮无法直接读取外置卷；使用已有 Aqua 桌面会话复制工程并逐文件校验，测试在本机隔离目录进行。回写仅限本轮变化文件，原文件 SHA-256 不一致时拒绝覆盖。原工作区其他未提交改动保留。

证据目录：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/watch-siri-20261028/`。原始源码、构建、原生结果：`/private/tmp/GymCount-Siri-20261028/`。未新建模拟器、未覆盖真机安装。
