# GymCount 工作约定

@/Users/xiangjunsheng/.codex/RTK.md

## Xcode 签名构建的执行会话

2026-10-18 已实测确认：同一份产物、同一张开发证书、相同 codesign 参数，在 Codex 原来的 Background 会话中返回 `errSecInternalComponent`，在 Aqua 桌面登录会话中签名成功。完整 iPhone、Watch 和 UI 测试目标的签名 `build-for-testing` 已通过，产物签名验证通过。

- 签名构建前检查 `launchctl managername`。若为 `Background`，不能据此会话的失败认定证书失效、钥匙串未解锁或私钥访问控制错误。
- 使用桌面登录用户的 Aqua 会话执行签名构建。可通过临时 LaunchAgent 在 `gui/$(id -u)` 中启动，执行前确认该用户已经桌面登录；任务结束后 bootout。不要安装常驻服务，也不要在输出中打印完整 launchctl 环境，避免泄露环境变量中的凭据。
- 不要在相同 Background 会话中反复重试签名，也不要仅凭 `errSecInternalComponent` 反复要求用户放宽私钥权限。先对照实际使用的证书、签名命令和执行会话。
- 不要为此导出私钥、索要或保存密码。确需用户本机授权时，说明具体证据。
- GUI 任务曾在以外置卷为工作目录时卡在读取当前目录。可将所需工程与源码复制到本机临时目录，逐文件校验内容一致后构建；保留原工作区及未提交改动。该目录访问停顿的底层原因尚未确认，不要直接认定为证书或 TCC 故障。
- 为核对完整签名证据，可将原始构建输出保存在本机日志中；查看时筛选错误、CodeSign 与最终结果，避免反复输出完整日志。

## 工程与验证边界

- `GymCountSync.xcodeproj` 是已有的手机与手表配套工程；`GymCount Capture` 用于配套版本，`GymCount Phone UI Tests` 用于手机界面测试。`GymCount.xcodeproj` 是独立 iPhone 工程。它们共用部分源码，修改后检查受影响工程。
- 无签名编译、签名构建、UI 测试实际执行、真机功能验收、TestFlight 发布分别报告。`build-for-testing` 成功只表示测试包已构建，不表示测试执行通过。
- 真机测试使用独立安装副本和隔离存储，保留设备当前应用及训练记录。未经相应发布指令，不把构建成功描述为已经发布。

详细证据见 [iPhone 多组训练完善记录](docs/phone-training-flow.md)。

## 最新 TestFlight 发布：2026-10-18

- 版本：1.1.3 (27)，手机与 Watch 一致。
- Delivery UUID / ASC Build ID：`ff39ea86-b9f3-40db-8fdc-979ca74d0b97`。
- 苹果状态：`BUILD-STATUS: VALID`；`IN_BETA_TESTING`，已核对属于内部测试组 `flyingrtx`。
- 构建目录：`build/TestFlight-1.1.3-27/`。包含归档、IPA、签名与权限核验、源码 SHA-256 清单、上传及苹果状态记录。
- 发布工程与 scheme：`GymCountSync.xcodeproj` / `GymCount Capture`；Team：`8BPSC5L74V`；手机 Bundle ID：`com.flyingrtx.GymCount`。
- ASC 凭据从本机 `~/.appstoreconnect/assettimemachine.env` 读取；只确认必需变量和密钥文件存在，不输出值或提交文件。沿用上一版导出设置，`manageAppVersionAndBuildNumber=false`、`method=app-store-connect`、`testFlightInternalTestingOnly=true`。
- 本轮真机 UI 测试已尝试，但手机为 unavailable，无法匹配测试目标；未执行交互验收。发布不代表休息通知、重启恢复等真机功能已验收。
