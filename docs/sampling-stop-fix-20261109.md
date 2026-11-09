# 卧推结束时的采样中断误报

2026-11-09。用户反馈卧推仅在结束／保存时出现“采样中断”。修复已提交并随双端 [TestFlight 1.1.8 (58)](testflight-1.1.8-58.md) 发布；57 版不包含此修复。下述实机验证边界保持不变。

## 机制与修复

`stopDetectionAsync()` 先停止 CoreMotion，再通过共享 `WorkoutFileIO` 等待采样队列排空并核算。原 `finalAnalysis()` 调用卧推检测器的 `finish()` 默认时间，即核算真正执行时的系统时间。检测器将该时间与最后一个传感器时间戳比较，超过 1 秒就标记中断。因此正常停止后排队或收尾耗时超过 1 秒，也会误报为运动期间断流。

- 同步、异步停止均先保存请求停止的单调时钟，再将它明确传给最终分析；文件和分析等待不延长采样质量的观察窗口。
- 两路 CoreMotion 回调都绑定启动时的代次；关闭阶段的 API 错误不再标记当前检测器中断，旧代次的回调不得修改新会话。
- 停止标记与代次通过锁读写，供主线程与串行采样队列共享。运动中的错误仍上报，实际样本缺口与停止前的尾部断流检查不变。
- `MotionLifecycle` 系统日志记录错误流、CoreMotion 错误域／代码及是否处于停止阶段，不增加产品解释文案。

没有改 V8 的动作识别门限、次数规则、完成反馈、文件保存与同步协议。只修正正常停止的边界及回调归属，不通过忽略所有 `insufficient_data` 来隐藏真实缺口。

## 实际验证

`scripts/verify-sampling-stop.swift` 直接使用生产 `BenchPressDetector` 和既有私人真实录制。仅平移时钟原点，保留传感器值、采样间隔及投递延迟；收尾等待采用实际经过的 1.15 秒，没有生成运动信号。

- #18、19、21、22、23、24 六条可核算记录均复现旧的迟收尾误报。按请求停止时刻结束后，最终次数仍为 2、5、5、4、6、5，周期和状态与等待前相同，结束未追加完成事件。
- #13、14 的真实内部缺口继续返回 `insufficient_data`；#15、16、17 保留 `needs_review`，未强制改成成功或零次。
- 另用原始 #19 流在停止请求前实际等待 1.15 秒且不再输入样本，仍被判定为尾部断流，未放宽 1 秒边界。
- 配套 iPhone／Watch Release 无签名构建通过。244 个应用文件的验证副本与工作区一致，3 个既有文件仅有 Git 换行归一化。原始录制文件摘要保持，未启动模拟器、操作正式安装或上传反馈。

```sh
rtk bypass xcrun swiftc -O 'GymCount Watch App/Detectors/BenchPressAnalysis.swift' \
  'GymCount Watch App/Detectors/BenchPress.swift' scripts/verify-sampling-stop.swift \
  -o /tmp/verify-sampling-stop
rtk bypass /tmp/verify-sampling-stop /path/to/private/records.json
```

此次只能连接 iPhone，读取到正式 App 为 1.1.8 (57)；Watch 未连接，尚未取得用户本次保存的系统日志，也没有实际触发硬件的停止回调。因此已证明并修复一条与症状吻合的误报机制，不能断言这是用户设备上唯一的原因。回放证明截止时间与检测器结果，不替代整条 CoreMotion 实机验收。

验证结果、源码前后副本与构建日志：

`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/SamplingStopFix-20261109/`
