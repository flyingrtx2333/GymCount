# Watch 普通训练历史同步（2026-10-19）

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

只读查询确认手表当前安装 **1.1.3 (27)**。第二次只读备份成功，取得 **82 条**原始历史；源 JSON SHA-256：`b7dee3418a815a72fc5a31000edc8f66b1eeabab92e98b0528baec2b0e29f6f3`。

2026-10-19 最新 4 条均为卧推，开始时间分别约 **20:03、20:06、20:17、20:25**，已保存计数为 **4、4、4、3**，最大重量均为 **70 公斤**。这些是手表保存的计数，不等同于视频核准的实际次数。

使用实际发布的 `Models.swift`、`WorkoutSync.swift`、`PhoneWorkoutStore.swift`，在独立本机存储回放这份原始备份：保留一条原始汇总作为已有记录，另 81 条按实际协议分批导入。字段保留、去重、重启恢复、原子文件恢复及删除后不恢复检查通过。未构造训练计数，也未向真实设备写入测试数据。

复现（私有备份不提交）：

```sh
rtk bypass xcrun swiftc -O 'GymCount Watch App/Models.swift' 'GymCount Watch App/WorkoutSync.swift' 'GymCount iOS/PhoneWorkoutStore.swift' scripts/verify-workout-history-import.swift -o /tmp/gymcount-verify-history
rtk bypass /tmp/gymcount-verify-history /path/to/private/watch-history-original.json
```

上述检查验证导入与保存，不代表真实双端传输验收。手机当时不可连接，未安装或替换设备上的现有应用；原始手表备份保留在忽略的发布目录中。完整同步需两端升级后实际确认。

Apple 接口依据：[后台传输](https://developer.apple.com/documentation/watchconnectivity/wcsession/transferuserinfo(_:))、[Watch 后台任务处理](https://developer.apple.com/documentation/watchkit/using-background-tasks)。
