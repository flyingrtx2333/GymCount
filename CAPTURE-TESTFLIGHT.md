## 2026-10-08：1.1.3 (5)

移除采集页空闲与采集中状态的冗余操作说明。09:48:26 上传成功，苹果正在处理。归档 `/tmp/GymCountCapture-NoHelper-1.1.3-5.xcarchive`，上传日志 `/tmp/gymcount-no-helper-upload.log`。本次通过 CURRENT_PROJECT_VERSION=5 构建参数指定版本，未改动打开中的 Xcode 项目配置。

# 采集测试版 TestFlight

## 2026-10-08：紧凑布局测试包

1.1.3 (4) 已成功上传，Apple 返回 `Uploaded package is processing` 和 `EXPORT SUCCEEDED`。
尚未确认处理完成或测试组分配，不等于已可安装。
正文及按钮 13 pt、辅助文字 11 pt、采集数字 22 pt；统一采集布局，修复小屏次数省略和按钮挤压。
归档：`/tmp/GymCountCapture-Layout-1.1.3-4.xcarchive`。
上传日志：`/tmp/gymcount-layout-upload.log`。
SSH 签名遇到 `errSecInternalComponent` 后，从桌面 Terminal 登录会话归档和上传成功。
两个项目构建号同步为 4；下次发布须使用新的构建号。


2026-10-07：1.1.3 测试包已上传成功，最后确认的 Apple 状态为 processing。
上传成功不等于已处理完毕，也不代表已分配给内部测试人员。
此包仅用于内部 TestFlight；未提交 App Store 正式审核。

## 打包

专用项目 `GymCountCapture.xcodeproj` 保持现有上架 App 的 watch-only 类型：
iOS 容器目标为 `com.apple.product-type.application.watchapp2-container`；手表 `WKWatchOnly=YES`。
不能直接把现有 watch-only App 改成可启动的 iPhone 配套 App。
专用项目从主项目结构生成，主项目配置变化后需同步；正式项目未改动发布类型。

执行 `scripts/archive-capture.sh`。脚本显式传入 `GYMCOUNT_CAPTURE`，
在 Release 包里启用原始采集和次数标注。普通 Release 不含该入口。
仅从 Xcode 点普通 Archive 不会自动启用采集标志。

归档：`/tmp/GymCountCapture-Companion-TestFlight.xcarchive`
出口合规：主项目、测试项目及最终 iOS 容器/watchOS Info.plist 均声明 `ITSAppUsesNonExemptEncryption=false`。当前仅使用系统 HTTPS/Keychain，无自带或第三方加密实现。
新增非豁免加密实现时需重新审视此声明；不添加虚假的合规证明编号。

导出配置：`/tmp/GymCountCaptureExportOptions.plist`
上传配置：`/tmp/GymCountCaptureUploadOptions.plist`
初始上传日志：`/tmp/GymCountCaptureUpload.log`
合规声明版 1.1.3 (2) 上传日志：`/tmp/GymCountCaptureComplianceUpload.log`
目录名中的 Companion 为早期尝试留下的名称；最终上传的是 watch-only 包。

## 使用

Apple 处理完成后，在 App Store Connect → GymCount → TestFlight 中，
把 1.1.3 构建分配给已有内部测试组。首次需接受内部测试邀请。
在与手表配对的 iPhone 上打开 TestFlight，选择 GymCount 后安装到手表。
手表 App → 设置 → 采集测试。
1.1.3 (3) 起无需上传密钥，确认实际次数后直接尝试上传；失败数据保留，可点击重试。
保持采集页在前台，采集完毕确认实际次数。
尚未收集真实运动数据；不代表计数准确率已提升。
