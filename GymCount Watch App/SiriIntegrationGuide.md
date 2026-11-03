# Apple Watch Siri 计数

使用手表本机的 App Intents / App Shortcuts，手机保持记录功能。

## 语音入口

- “开始健身计数”：询问卧推、深蹲或硬拉，再打开整场训练页。
- “用健身计数开始卧推”：直接带入动作。也支持当前正式应用名“健身计数器”。
- “结束健身计数”或“用健身计数结束训练”：结束整场训练，保存成功后读出最终累计次数并打开报告。
- 英语：“Start PowerReps” / “Start Bench Press with PowerReps” / “Finish PowerReps”。

省略重量时使用手表已设置的器械重量。已有训练、未完成恢复、保存中或采集未完成时拒绝创建另一条训练。草稿实际保存成功后才回应开始成功；不自动添加次数或制造训练历史。

一场训练中可在手表切动作、重量和暂停，Siri 结束会等待最终计数核准与持久化结果。没有正在进行的训练时结束请求报错，不创建空报告。旧的单组恢复会话仍可通过同一结束 Intent 保存。完整数据与验证边界见 [整场训练报告](../docs/whole-workout-20261028.md)。

## 配置

`Managers/ShortCutsManager.swift` 保留现有 Intent 和参数标识，`ExerciseTypeQuery` 不再默认返回深蹲；`StartWorkoutIntent` 的动作必填，未指定时由系统询问。`StartWorkoutIntent` 调用整场训练启动入口，`StopWorkoutIntent` 根据当前会话选择整场结束或兼容的单组保存；两者只在实际完成相应操作后回应成功。`GymCountShortcutsProvider` 在 Watch App 初始化时注册开始和结束入口。

语音短语使用两种语言的 `AppShortcuts.strings`，保留 `${applicationName}` 和 `${exerciseType}` 占位符。两个 Watch Info.plist 的 `INAlternativeAppNames` 注册应用别名，`InfoPlist.strings` 将别名本地化为“健身计数”／“Power Reps”。不把整条命令伪装成应用名称。

Apple 要求 App Shortcut 短语包含应用名，可以采用已登记的应用别名：[Design App Shortcuts](https://developer.apple.com/videos/play/wwdc2022/10169/)。手表必须安装本版本并启用 Siri；安装和短语注册成功不等同于已验证某台手表的实际口语识别。
