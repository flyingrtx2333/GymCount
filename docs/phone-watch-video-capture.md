# iPhone 与 Watch 同步采集

配套项目：`GymCountSync.xcodeproj`，共享 scheme `GymCount Capture`。iPhone iOS 17+、Watch watchOS 11.2+，沿用 `com.flyingrtx.GymCount` 与 `com.flyingrtx.GymCount.watchkitapp`。原来的 `GymCountCapture.xcodeproj` 是旧 Watch-only 打包项目，不用于此次配套发布。

Apple TN3157 明确支持从 watch-only 增加 iOS companion；发布到 App Store 后不能退回 watch-only。此版本先通过内部 TestFlight 验证，没有提交正式 App Store 审核。

## 使用

1. 在配对 iPhone 和 Watch 上安装同一个新构建。
2. 手机进入“设置 → 开发者工具 → 同步录像与采样”，允许相机权限，固定手机，让全身和器械入镜。录像使用后置相机、720p、竖屏，无音频。
3. 打开手表 GymCount → 设置 → 采集测试。可在手机开始，也可在手表选择动作后点“同步手机录像”。首次需要在手表允许体能训练权限。
4. 同步启动后按正常习惯拿取器械、训练、放回器械。在任一端结束。单组最长约 3 分钟，保留完整首尾过程，不要求用户报告时间。
5. 手机“查看录像与采样记录”查看视频、填写实际次数、重试接收采样。只有收到采样且标注实际次数后才能上传运动数据。
6. 开发标注时可暂停视频，在每次动作完成处点“标记当前画面完成一次”，并撤销最后一次标记。普通训练不要求逐次点按钮。
7. “上传录像与采样”先上传采样，再直传录像到私有 COS；服务端校验文件大小和 MD5 后按同一 UUID 关联录像、逐次标注和时间对齐信息。两部分完成才提示成功，失败保留手机文件，可重新点击上传补传。网站“健身采集 → 查看”播放录像；删除记录同时删除录像。已有记录也可补传，无须重新采集。
8. “分享录像与采样文件”仍可导出 `video.mov`、`motion.json`、`manifest.json`。

普通首页为训练，提供手动记次、历史和设置。采集仅供开发验证；首页不会启动相机，也不会接受手表远程录像开始。离开采集页会停止相机和当前采集。

## 同步与完整性

- WatchConnectivity 实时指令采用应答和超时，不把延迟后台消息当作可靠开始指令。必须先打开两端应用。
- 准备握手确认手表无未保存采集并取得 HealthKit 训练权限；5 次时钟往返测量选取最低延迟，超过 1 秒拒绝启动。
- iPhone 先开始录像，收到录像开始回调后启动 Watch；因此录像包含采样开始前的短前缀，不承诺同一毫秒开始。
- Watch 原始 CoreMotion 时间与固定 wall-clock/uptime 锚点关联；`manifest.json` 保存双端时钟偏移、网络 RTT、视频起点估计、采样起点、实际标注及人工对齐修正。
- 视频锚点使用录像回调时间减 `recordedDuration` 估计。网络 RTT 不等于全部对齐误差；精确逐帧对齐仍需真机测量和人工核对。标注记录允许 0.1 秒步长修正对齐。
- 用同一个 UUID 关联视频与采样，拒收 ID 不匹配的文件。视频独立原子保存清单；收到传感器文件后更新关联，不覆盖别组数据。
- 停止时等待 Watch 应答再停止手机录像。相机中断、手机后台、开始超时都会触发 Watch 停止请求；不能确认结束时显示错误并保留录像与补传入口。
- Watch 使用实际力量训练 `HKWorkoutSession` 与 `workout-processing` 后台模式维持运行，不保存虚构的健康训练记录。屏幕变暗时的真实采样连续性仍需真机检验。
- Watch 保存采样与时间文件后排队 `transferFile`；传输失败保留文件，重新启动 Watch 后仍可按组 UUID 补传。收到的临时文件在 delegate 返回前读入，避免系统删除临时文件导致丢失。
- 运动上传保留现有云端 v2 协议，不把参考标注冒充 Watch 检测事件。云端实际次数仍是人工标签。

## 计数边界

手机展示 Watch 现有规则的实验计数；弯举及非训练动作仍为采集用途。此次没有训练新模型，也没有实现视频自动计数。录像、逐次标注和原始运动数据用于以后独立验证模型。手表旧算法准确率及云端候选计数问题不能因新增录像功能而宣称解决。

## 验证

`swiftc 'GymCount iOS/VideoCaptureManifest.swift' scripts/verify-capture-sync.swift -o build/verify-capture-sync` 后执行该程序，验证时钟偏移、处理延迟、采样与视频时间映射、缺失时间、标注持久化与延迟拒绝。

配套 Release iOS Simulator 构建包含 Watch 目标；签名归档需检查两端 Info.plist 的 ID、版本、WKCompanionAppBundleIdentifier、WKWatchOnly=false 与 workout-processing。模拟器不能证明真实相机录像、无线通信与传感器准确率。

实机验收：准备/拿杠/深蹲/放回的完整录像；手机或 Watch 启动和结束；屏幕变暗时连续采样；短暂断线后采样补传；按视频核对逐次标注与传感器事件。未通过前不宣称准确计数或逐帧同步。
