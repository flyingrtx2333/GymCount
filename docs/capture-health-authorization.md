# 配套手表健康授权修复

## 证据与范围

用户反馈手机点同步按钮后手表响应，并明确提示需允许体能训练权限。这证明该次消息可达，当前阻塞是权限准备；此前手表按钮将 authorizing 与 requestingPhone 一并显示为“正在连接”，掩盖了两种状态。

iPhone 第 14 版的源项目及签名归档均缺少 HealthKit 能力、健康使用说明和 UIApplicationDelegate.applicationShouldRequestHealthAuthorization 回调。Apple 的 handleAuthorizationForExtension 文档要求宿主 App 实现这个回调，以承接扩展提出的健康授权请求。此缺项与等待授权但没有正常完成的现象一致；尚未取得真机系统日志证明全部症状的唯一原因。

## 变更

配套 iPhone 目标加入 HealthKit entitlement、中文读写用途说明，以及 SwiftUI UIApplicationDelegateAdaptor 接入的授权处理。仅承接手表的授权请求，不增加健康数据读取或新的计数算法。

手表采集页增加“允许体能训练”入口，权限未完成时禁用手机同步录像按钮，等待时明确显示“等待权限确认”。不在打开采集页时自动请求；回到前台刷新授权状态。保留已有触感、启动期限、取消及迟到回复保护。

## 验证

两项现有界面回归通过（超时/取消/迟到回复、导航/计数/保存），结果 `build/CaptureHealthAuthorization.xcresult`。双端签名归档及最终 IPA 均通过手机与手表 HealthKit entitlement、配置文件允许的权限和中文用途说明检查。已发布 TestFlight 1.1.3 (15)，Apple 状态 VALID，已在 flyingrtx 内部测试组。构建与验证记录为 build/TestFlight-1.1.3-15/。

真实系统授权弹窗、允许后手表状态变化和同步采集仍需在更新两端后验证，不把模拟器构建或配置校验当作真机授权成功。

参考：
- https://developer.apple.com/documentation/uikit/uiapplicationdelegate/applicationshouldrequesthealthauthorization(_:)
- https://developer.apple.com/documentation/healthkit/hkhealthstore/handleauthorizationforextension(completion:)
- https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data
