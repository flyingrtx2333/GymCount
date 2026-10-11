# 手机采集指令与手表页面切换

原实现把采集页 sheet 绑定到 remoteSession，只有收到 start 并成功创建训练会话、启动传感器后才显示。手机 prepare 阶段与授权失败未导航，结束时 remoteSession=false 又会关闭结果页。

页面展示与采样生命周期现分开：prepare 验证没有进行中的训练或未确认采集后，立即在 Watch 根视图切换到 CollectionView，采用手机传来的动作；无需经过设置入口。未授权时显示同一页内的授权入口和原因。start 后显示采样中，stop 后保持页面展示传输和上传结果。根页面切换也覆盖首次启动和此前的设置/历史页面，避免多个 sheet 竞争。采集中或等待确认时不提供返回入口，已有本地记录不会被新 prepare 覆盖。

手机不可达时，通过 HealthKit startWatchApp(with:completion:) 请求系统启动配套 Watch 应用；Watch 的 WKApplicationDelegate.handle(_:) 回调打开采集页，传感器仍由随后成功确认的 start 指令启动。唤起请求有 10 秒期限，连接等待最多 5 秒，并继续受原有 25 秒总期限、取消及代际检查约束，迟到回复不会启动采样。后台唤起行为受系统和真实配对状态影响，不能用模拟器截图证明真机唤起成功。

验证：4 项 Watch 测试通过，覆盖 prepare 在未启动传感器前打开正确动作页、未确认记录保留，以及原有上传失败/超时恢复；2 项 iPhone 回归通过，覆盖启动超时、取消、迟到回复和原有导航/保存。隔离模拟器副本保留真实 App 根视图和 CollectionView，仅注入一条卧推 prepare 指令并关闭首次权限请求，自动进入卧推采集页的截图为 build/TestFlight-1.1.3-17/phone-request-watch-page.png；没有启动传感器或上传，副本已卸载。

测试结果：build/CaptureRoutingWatch-final.xcresult、build/CaptureRoutingPhone.xcresult。配套发布版本 1.1.3 (17)。

Apple 文档：
- https://developer.apple.com/documentation/healthkit/hkhealthstore/startwatchapp(with:completion:)
- https://developer.apple.com/documentation/watchkit/wkapplicationdelegate/handle(_:)-1pfoc
