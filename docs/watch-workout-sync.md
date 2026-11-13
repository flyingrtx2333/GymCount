# Watch 训练历史同步

## 接收积压与图表高度修复（2026-11-13，尚未发布）

只读核对手机和手表均为 1.1.8 (61)。手机有 122 条、手表有 127 条记录；缺少今天 4 条和昨晚 1 条。手机 `IncomingWorkouts` 已收到这 5 条，但 1500 个待处理文件只对应 15 份不同报告。数据内容有效，重复重发造成接收积压；具体真机停顿调用仍待新版日志／同步复验确认，不能把隔离恢复当作用户手机已恢复。

用户随后确认同步页显示“正在接收记录”。再次只读回查，待处理文件从 1500 降至 1075，手机仍为 122 条、仍缺 5 条：旧队列确实在处理，并非完全断连，但大量重复旧报告拖延了新记录入库。

- `WorkoutMessageInbox` 按接收端、消息类型和排序后的记录内容生成文件标识，新重试原子覆盖同一文件。读取旧 UUID 文件时合并语义相同的 JSON，较新的记录先处理；不同内容、损坏文件保留重试。
- 记录持久化成功后立即排队接收回执，再异步处理传感器时间轴；不再等待时间轴收件完成。只有成功保存的报告才移除其重复待收文件。手动同步同时重试本地收件箱。
- 扫描与合并在已有文件队列执行，每批保留的不同文件限 16 MiB；单文件保留协议原有上限。
- 趋势图固定绘图区高度，普通 iPhone 为 156 点，宽屏为 190 点；无障碍字号额外预留 44 点。同一筛选范围使用全范围纵轴，不随横向窗口重新缩放。

验证结果：

- `scripts/verify-workout-inbox.swift` 使用真实手机快照、7 份已有时间轴和 1500 份真实待收文件，在隔离存储合并为 127 条。去重、最新优先、保存后清理、重启恢复、手机修正／删除保留、错误文件隔离和保存失败保留均通过；原文件未改动。
- 原生 `testStableChartHeightWithRealSyncedHistory` 已执行，1 项／0 失败；真实 127 条副本切换日／周／月、卧推／深蹲／全部以及横向滑动，图表高度均为 156 点（AX 像素取整为 156.3）。
- 两个 iPhone 工程与配套 Watch 的 Release 无签名构建通过。用户设备仍为 61 版、手机仍有 122 条；本轮未覆盖用户安装、未改写设备记录、未发布 TestFlight。双端实际补齐仍需修复版真机复验。

原生截图、AX 和汇总验证凭证：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/Sync-Chart-Repair-20261113/`。私有设备文件保存在 `/private/tmp/GymCount-SyncAudit-20261113/private/`，不提交原始记录和待收载荷。

复现收件回归（私有输入只读，末项可选，用于保存隔离合并结果）：

```sh
rtk bypass xcrun swiftc -O 'GymCount Watch App/Models.swift' 'GymCount Watch App/WorkoutReport.swift' 'GymCount Watch App/WorkoutSync.swift' 'GymCount Watch App/ActionTiming.swift' 'GymCount Watch App/Detectors/BenchPressAnalysis.swift' 'GymCount Watch App/Detectors/SquatAnalysis.swift' 'GymCount Watch App/TrainingActivity.swift' 'GymCount iOS/PhoneTrainingReminder.swift' 'GymCount iOS/PhoneWorkoutStore.swift' 'GymCount iOS/WorkoutMessageInbox.swift' scripts/verify-workout-inbox.swift -o /tmp/gymcount-verify-inbox
rtk bypass /tmp/gymcount-verify-inbox /path/to/private/records-v3.json /path/to/private/IncomingWorkouts /path/to/private/merged-records.json
```

## 首次同步实现（2026-10-19）

## 问题与修复

28 版及之前，普通训练结束后只将 `WorkoutHistory` 保存到手表的 `workout_history`，手机记录页读取独立的 `phone.training.v2`。已有 WatchConnectivity 只处理录像采集，普通训练没有发送、接收或历史导入入口。

本次补上手表到手机的单向历史同步：

- 手表保存训练后、应用进入前台、连接恢复时尝试发送未确认的历史；手机启动和进入前台时请求补传，记录页可手动重试。
- 复用两端现有 WCSession delegate，按 `kind` 路由普通训练消息。历史通过 `transferUserInfo` 排队，当前可连接时同时直接发送；不替换录像采集使用的 application context。
- 每批最多 40 条、载荷最多 48 KiB，同时最多 3 个历史后台传输。手机写入独立原子历史文件并更新记录后才回执；传输完成本身不视为保存成功。重发按原始 UUID 去重，未确认的记录保留在手表。
- 手机安装身份变化时补传旧历史。普通训练同步不依赖相机或 HealthKit 授权；SwiftUI Watch Connectivity 后台任务等待 session 激活并处理完待收数据后结束。
- 导入保留原始 UUID、开始时间、动作、次数、最大重量和时长。手表当前只有汇总，不生成各组明细或训练量。手机原有记录、活动训练和偏好继续保存。
- 手机删除已导入记录时保存删除标记，重连与重发不会将其恢复。此操作不删除手表副本；删除手表记录也不级联删除手机记录。
- 手机显示来源 `Apple Watch` 和同步状态。对端仍为旧版时提示更新手表，避免一直显示正在接收。

## 本次真实数据证据

只读查询确认手表当前安装 **1.1.3 (27)**。只读备份取得 **82 条**原始历史，确认刚保存的训练仍在。完整原始备份和校验凭证保存在本机受保护目录；手表保存的计数不等同于视频核准的实际次数。

使用实际发布的 `Models.swift`、`WorkoutSync.swift`、`PhoneWorkoutStore.swift`，在独立本机存储回放这份原始备份：保留一条原始汇总作为已有记录，另 81 条按实际协议分批导入。字段保留、去重、重启恢复、原子文件恢复及删除后不恢复检查通过。未构造训练计数，也未向真实设备写入测试数据。

复现（私有备份不提交）：

```sh
rtk bypass xcrun swiftc -O 'GymCount Watch App/Models.swift' 'GymCount Watch App/WorkoutSync.swift' 'GymCount iOS/PhoneWorkoutStore.swift' scripts/verify-workout-history-import.swift -o /tmp/gymcount-verify-history
rtk bypass /tmp/gymcount-verify-history /path/to/private/watch-history-original.json
```

上述检查验证导入与保存，不代表真实双端传输验收。手机当时不可连接，未安装或替换设备上的现有应用；原始手表备份保留在忽略的发布目录中。完整同步需两端升级后实际确认。

Apple 接口依据：[后台传输](https://developer.apple.com/documentation/watchconnectivity/wcsession/transferuserinfo(_:))、[Watch 后台任务处理](https://developer.apple.com/documentation/watchkit/using-background-tasks)。
