# iPhone 多组训练完善（2026-10-18）

## 当前行为

- 一场训练支持多个动作和多组重量、次数；完成一组后自动休息，可撤回上一组或跳过休息。
- 切换动作时，未完成组可保存、放弃或继续；结束训练时会保存当前组。
- 可沿用上次同动作、同组序号的数据。当前组已有次数时必须确认替换，取消保留原输入。
- 训练页和历史详情按动作独立编号；旧版导入次数单独标注，不占新组序号。
- 使用 `phone.training.v2` 一起保存活动训练、历史与休息设置。保留旧版存储键；旧版历史只展示原汇总，不补造组明细。
- 界面测试的训练记录、默认重量和通知标识使用隔离存储，不修改日常训练数据。

## 本轮验证

- `GymCountSync.xcodeproj` 的 `GymCount Phone UI Tests` 真机架构无签名 `build-for-testing` 通过，包含 iPhone、Watch 与 UI 测试目标；只证明编译，不代表测试已执行。
- 独立 iPhone 工程 `GymCount.xcodeproj` 的真机架构无签名构建通过。
- 已更新现有整场训练 UI 测试，覆盖沿用上次的取消、确认替换以及取消后重启恢复；动作切换按钮通过滚动定位。
- 用户提供的 Xcode 截图显示：`GymCount Capture` scheme、`Any iOS Device (arm64)` 目标在 11:13 构建成功，界面显示 4 条警告。该结果证明 Xcode 桌面构建通过，不代表真机交互测试已通过。
- 已连接真实 iPhone 16 Pro Max，安装中的版本为 1.1.3 (26)。已定位自动执行进程的签名失败原因，并在 Aqua 桌面登录会话中完成相同 scheme 的签名 `build-for-testing`，退出码 0、`TEST BUILD SUCCEEDED`。iPhone、Watch、UI 测试包与 Runner 均成功签名，App 和测试 Runner 的 `codesign --verify --deep --strict` 均通过。未安装或替换设备现有应用，UI 测试尚未运行。
- 编译仍有既有的 `PhoneCaptureStore.swift` 捕获引用警告和 AppIntents 元数据提示。

## 待真机验收

签名构建阻塞已解除。发布前已在独立安装副本中尝试整场训练测试，但 iPhone 16 Pro Max 为 unavailable，Xcode 无法匹配测试目标，测试未启动，也未覆盖设备当前应用。后续手机可用时运行整场训练用例，再检查锁屏休息通知和系统通知拒绝场景。签名构建或 TestFlight 发布成功不等于真机交互验收完成。

普通训练 Watch/iPhone 历史同步、手机自动识别、iPhone 健康数据写入仍未实现。本轮不改动动作识别算法。1.1.3 (27) 已发布至 TestFlight：`BUILD-STATUS: VALID` / `IN_BETA_TESTING`，已确认在内部组 `flyingrtx`，Delivery UUID 为 `ff39ea86-b9f3-40db-8fdc-979ca74d0b97`。发布凭证见 `build/TestFlight-1.1.3-27/`。

## 自动签名失败的根因与对照证据

此前误把后台进程的钥匙串访问失败当成用户未解锁钥匙串或私钥访问控制不正确，导致重复要求用户调整设置。私钥访问控制截图已显示允许所有应用，进一步放宽权限不能解决执行会话的差异。

实测对照：

| 条件 | Codex 原执行路径 | 修复后的执行路径 |
| --- | --- | --- |
| launchctl managername | Background | Aqua |
| 用户 | xiangjunsheng / UID 501 | 同一用户 |
| 登录钥匙串设置查询 | User interaction is not allowed | 正常读取，no-timeout |
| 开发证书 SHA-1 | 633577FF6135F08D839279C0EE1B5E94B68CF87C | 完全相同 |
| 对同一份 SessionSigningProbe.app 执行相同 codesign 参数 | 退出 1，errSecInternalComponent | 退出 0，签名验证通过 |
| 完整 UI 测试目标签名构建 | Watch CodeSign 失败 | TEST BUILD SUCCEEDED，退出 0 |

原 Codex 进程继承了远程 SSH 环境并处在 Background 会话中；Xcode 在桌面登录会话中。上述同文件、同证书、同参数的签名对照确认，决定性差异是执行会话中的钥匙串可访问性，而非项目源码、证书有效期或 Debug/Release 配置。

本次通过临时 LaunchAgent 在 `gui/501` 的 Aqua 会话执行构建，无需修改钥匙串权限、导出私钥或保存密码。桌面任务直接以外置卷为工作目录时还曾停在读取当前目录的系统调用；因此采用本机 `/tmp` 下的源码副本构建，227 个文件逐一 SHA-256 核对一致。此目录访问停顿的更底层原因未进一步确认，不据此认定是证书错误。

签名构建与对照记录：`/tmp/GymCount-signing-session-20261018/`；完整构建日志 `build.log`、源码校验 `source-sha256.json`、两种会话签名日志 `background-signing.log` / `aqua-signing.log`。构建产物位于 `/tmp/GymCount-training-20261018/Build/Products/`。这些临时文件可能随系统清理丢失；本节保留核心证据与结果。

后续自动执行签名构建须使用桌面登录会话；若当前会话为 Background，不应反复重试同一命令或继续要求用户调整证书权限。使用临时 GUI LaunchAgent 时应在任务结束后 bootout，不安装常驻服务。
