# 采集自动授权与紧凑页面

首次进入手表采集页自动发起 HealthKit 体能训练写入授权，无须查找授权按钮。手机点击开始同步时先请求同一权限；系统授权完成并检查实际写入权限后才唤起手表、校时和启动录像。授权期间取消或离开页面会撤销启动，迟到的授权结果不会启动录像。

手表 prepare 即时回复，权限未完成返回 authorizationPending，不阻塞通信回调。手机将用户确认授权与 25 秒连接期限分开，最多等待 60 次准备轮询；授权失败或取消保持可重试状态。手表首次自动请求每次应用运行仅触发一次，避免系统窗口结束后重新弹出。已经拒绝时仍显示明确失败与重试入口；系统是否再次显示窗口由系统决定，App 不声称能强制重置已经拒绝的权限。

移除动作速度选择、选项弹窗和临时状态。旧采集记录及服务端协议的 pace 字段保持兼容，新采集使用既有 normal 默认值，用户无需填写速度。去掉采集根页面多余的 NavigationStack；内容顶部保留 24 点空间，系统时钟与标题不重叠。

验证：4 项 Watch 回归、2 项手机界面回归通过。使用隔离副本的真实根页面和 CollectionView 在 40mm、46mm 模拟器截图核验；副本只打开卧推采集页，禁用授权及传感器，不上传任何记录。截图为布局证据，不是实际 HealthKit 授权成功证据。系统权限弹窗和双端采集仍需真机验证。

Apple API：[requestAuthorization](https://developer.apple.com/documentation/healthkit/hkhealthstore/requestauthorization(toshare:read:completion:))。
