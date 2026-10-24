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
- 检查临时 LaunchAgent 状态时，只在内存中过滤 `state`、`pid`、`last exit code` 等必要字段；禁止整体输出 `launchctl print`，其中会包含无关服务继承的凭据。

## 工程与验证边界

- `GymCountSync.xcodeproj` 是已有的手机与手表配套工程；`GymCount Capture` 用于配套版本，`GymCount Phone UI Tests` 用于手机界面测试。`GymCount.xcodeproj` 是独立 iPhone 工程。它们共用部分源码，修改后检查受影响工程。
- 无签名编译、签名构建、UI 测试实际执行、真机功能验收、TestFlight 发布分别报告。`build-for-testing` 成功只表示测试包已构建，不表示测试执行通过。
- 真机测试使用独立安装副本和隔离存储，保留设备当前应用及训练记录。未经相应发布指令，不把构建成功描述为已经发布。

详细证据见 [iPhone 多组训练完善记录](docs/phone-training-flow.md)。

## 最新 TestFlight 发布：2026-10-24（38）

- 版本：1.1.4 (38)，iPhone 与 Watch 一致；源码以 37 版为基线，使用当前工作区逐文件核验的快照，421 个文件 SHA-256 已保存。
- Delivery UUID / ASC Build ID：`9bfdfd35-51f1-4a28-9bac-708d5a286306`。
- 苹果状态：`BUILD-STATUS: VALID` / `IN_BETA_TESTING` / `INTERNAL_ONLY`；已确认内部测试组 `flyingrtx` 包含本构建，中英文测试说明已更新。
- iPhone 正式整合 F 布局与 M2 动效：紧凑记录、底部筛选及操作、趋势和多组补记布局；使用随键盘移动的原生安全区控件修复布局警告。记录、详情、趋势、补记及采集入口使用与 Watch 相同的运动图标，最终 IPA 已核对三种运动资源。
- Watch 功能源代码与 37 版一致，配套构建号升至 38；保留保存成功提示与震动、失败重试及计数反馈。没有新增计数算法修改。
- 双端 Aqua 签名归档、导出、IPA 签名/版本/HealthKit/配套关系核验通过。5 个 iOS 改动文件与此前原生验证的摘要一致；三个工程构建通过，原生记录/趋势与多组补记/键盘两项检查各 1 项通过、0 失败、无运行时布局警告。证据随发布保存。
- 真机同步、文件导出恢复、VoiceOver/减弱动态效果、Watch 震动及反馈上传仍待补验；用户现有安装和数据未覆盖。沿用既有编译警告。本次仅发布 TestFlight，未提交正式版审核。
- IPA SHA-256：`639985a44840d14ff5df25c65482b822de7b13229d4857cd4e217a4f61c512f9`。
- 完整产物：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/TestFlight-1.1.4-38/`；隔离构建源码：`/private/tmp/GymCount-TestFlight-1.1.4-38-20261024/source`。无关设计和原工作区改动保留。

## 历史 TestFlight 发布：2026-10-23（37）

- 版本：1.1.4 (37)，iPhone 与 Watch 一致；发布应用源码：`be102aff09af4015c00de55dc58dd0c74ed1d39c`，功能提交 `a7b3f52`。
- Delivery UUID / ASC Build ID：`15c3f407-f46c-47cb-b064-c7eeb801fa6a`。
- 苹果状态：`BUILD-STATUS: VALID` / `IN_BETA_TESTING` / `INTERNAL_ONLY`；已确认内部测试组 `flyingrtx` 包含本构建，中英文测试说明已更新。
- iPhone 白金记录界面：记录、趋势、设置，多组补记与编辑、日期及动作筛选、草稿、备份合并恢复、CSV 导出。手机修正和删除标记在重复同步后保留。
- Watch 保存成功后返回首页、绿色提示与一次成功震动；保存失败保留训练并重试。支持核对真实次数后主动上传本次采样反馈，保留原自动计数与训练记录。
- 双端 Aqua 签名归档、导出、IPA 版本/签名/HealthKit/配套关系通过。420 个构建源码文件摘要通过；其中 4 个与 Git 提交仅 CRLF/LF 规范化不同，明细保存在预上传核验中。
- 发布源码复查 82 条真实历史的迁移、重复同步、修正/删除保留、重启、备份冲突及写入失败通过。此前原生 iPhone/Watch 界面、文件导出恢复、保存失败重试检查与两个 iPhone 工程构建通过，证据随发布保存。
- 真机双端同步、文件导出恢复、VoiceOver/减弱动态效果、完成震动及反馈上传仍待补验；用户现有安装和数据未覆盖。沿用既有 HealthKit、捕获引用及 AppIntents 编译警告。
- IPA SHA-256：`785b6277c37523aa6f3abb9fb7810d9798514bcc6afa33cfce92b22f7e306ba2`。
- 完整产物：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/TestFlight-1.1.4-37/`。隔离发布源码位于 `/tmp/GymCount-TestFlight-1.1.4-37-20261023/source`，原工作区及无关设计改动保留。
- 最初 1.1.3 (37) 上传被苹果拒绝（90062/90186）：1.1.3 已获批准并关闭追加构建。只升营销版本到 1.1.4 后重新归档上传成功，失败证据保留在 `TestFlight-1.1.3-37/`。本次没有提交正式版审核或修改已上架版本。

## 最新 App Store 提交：2026-10-24（40）

- 版本：1.1.4 (40)，iPhone 与 Watch 一致；归档源码提交 `b15e0e2f63cf9c0c593a6b1621a360b859370344`，422 个源码文件 SHA-256 已核验。
- Delivery UUID / ASC Build ID：`d293db2c-6be2-47d9-b164-4976bf49011c`；苹果 `BUILD-STATUS: VALID` / `APP_STORE_ELIGIBLE`。
- App Store Version ID：`2ad53749-061c-4fd6-8cc8-055aa01d57aa`；Review Submission ID：`f02d30e2-5696-4f32-9cd5-064d59841525`。提交后版本及审核状态均为 `WAITING_FOR_REVIEW`，发布方式 `AFTER_APPROVAL`；尚未称为已上架，当前公开版本仍为 1.1.3。
- 简体中文商店副标题改为“手表自动计数，手机专注记录”，更新介绍、关键词、推广文本及更新说明，覆盖记录、趋势、多组补记、草稿、备份恢复和 CSV 导出；保留既有审核联系人并更新操作说明。
- iPhone 替换为 4 张白金风格截图，分别展示记录、趋势、补记与备份设置；5 张 Watch 截图保留。所有图片均为 `COMPLETE`，iPhone 图片顺序与来源校验和通过。截图来自当前生产界面和独立、明确标注的展示示例，不含用户真实训练资料。补记 PNG 处理停滞后换用 JPEG，最终已处理完成，原图保留。
- 包含顶部筛选和右上角补记入口；修复退出补记后系统底栏重新出现、遮挡自定义导航的问题。39 版未提交审核，40 版包含此修复。没有新增 Watch 算法改动，沿用保存成功提示、震动及计数反馈。
- 双端 Aqua 签名归档、导出、IPA 签名/版本/HealthKit/配套关系验证通过；两个独立 iPhone 工程 Release 构建通过。真实82条历史的记录/趋势检查、多组录入/键盘/草稿/重启检查共2项通过，最终截图及取消编辑后导航检查1项通过，均无运行时布局告警。生产源码与归档、原生预览逐文件匹配；截图脚本后续只修正了预填重量的录入方式，未改动生产源码。
- IPA SHA-256：`54b0cd831f337baf3908fb23b3f8316f54ebcab0b6b63e2b68d2576a6f6b9168`。
- 完整产物：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/AppStore-1.1.4-40/`。用户真机安装和记录未覆盖；实际佩戴、双端同步、真机文件导出恢复及人工 VoiceOver 仍待补验。临时发布 LaunchAgent 已移除。

## 当前已上架 App Store 正式版：1.1.3（36）

- 版本：1.1.3 (36)，iPhone 与 Watch 一致；发布应用源码：`aaf117b3bc3dd82b0d640a591d633fec361f7e0a`。
- Delivery UUID / ASC Build ID：`4fb1984d-82c3-4772-8736-dbcb6ee08d35`。
- 双端 Aqua 签名归档和导出、签名/版本/HealthKit/配套关系核验通过，407 个源码文件 SHA-256 与发布提交一致。正式导出 `testFlightInternalTestingOnly=false`，苹果 `BUILD-STATUS: VALID` / `APP_STORE_ELIGIBLE`。
- App Store Version ID：`839975af-cc43-4c17-9ee9-92b3274df5c4`；Review Submission ID：`fa1b1ee9-ef5b-4cf7-8e42-c4dbb37b9e07`。
- 2026-10-22 提交时为 `WAITING_FOR_REVIEW` / `AFTER_APPROVAL`；2026-10-23 发布 37 版前已通过 ASC 核实版本状态为 `READY_FOR_SALE`（已上架）。
- 功能源码沿用 35 版卧推反馈与深蹲算法，仅增加构建号。已更新简体中文商店介绍、更新说明及审核操作说明；保留既有审核联系人。iPhone 新增一张从本构建源码生成的 1320×2868 训练首页截图，无模拟训练记录；继承 5 张 Watch 截图。截图处理为 COMPLETE。
- IPA SHA-256：`e96c6c58ac4ef5ff57a78984eea4248030c74f83d4ceeb7f70cba55e77b55f60`。
- 完整产物：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/AppStore-1.1.3-36/`，包含归档、IPA、源码快照/哈希、苹果处理和审核提交凭证；排除可重建 DerivedData。
- 用户设备应用和数据未覆盖安装。算法真实记录回放边界沿用 35 版；尚未执行新的实际佩戴验收。应用无需登录，运动自动计数须配对 Watch；既有 HealthKit、AppIntents 等编译警告保留。

## 历史 TestFlight 发布：2026-10-21（35）

- 版本：1.1.3 (35)，iPhone 与 Watch 一致；发布应用源码：`cecce23`。
- Delivery UUID / ASC Build ID：`489fe992-7ec8-41ca-b384-9b74b67653b4`。
- 苹果状态：`BUILD-STATUS: VALID` / `IN_BETA_TESTING`，已确认内部测试组 `flyingrtx` 包含本构建，中英文测试说明已更新。
- 卧推仅在确认推起顶部后请求震动；准备动作、迟到数据和结束补算不补震。杠铃深蹲训练与采集统一使用融合运动的下降、上升及站立确认规则。
- 新采集保存震动请求时间；后台及看板已上线次数差、逐次时间差、平均/最大绝对时间差。后台代码 `7c7dbab4e69e9e3cdcc52b2ac0281206cc920cdb`；前端线上 `1e4e48f5d0743e0286a69b61eb52804a4a5d8286` 包含该提交。健康版本和登录后的列表/详情已验收。
- 4 条视频深蹲已仅重算 cloud_analysis，结果 8/8/8/9，33/33 次匹配、32/33 在 ±0.5 秒内；原采样、视频、标注、人工次数及其他元数据保持。卧推 5 条视频反馈回放 25/25，19/25 在 ±0.5 秒内，超差保留。历史震动时间没有伪造。
- 双端 Aqua 签名归档、导出和 IPA 版本/签名/HealthKit/配套关系通过；独立 iPhone Release 编译通过。407 个跟踪源码文件 SHA-256 与发布提交一致。未纳入其他未提交的时长、模型、历史和手机训练流程修改。
- IPA SHA-256：`be4bbd153d427564f7ebc7a4954261c25d8d93c4f189e2e4afbd2e933fabd881`。
- 完整产物：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/TestFlight-1.1.3-35/`。外置卷已满，发布使用本机隔离副本；原工作区和未提交工作保留。
- 未覆盖安装用户当前应用，未执行新的佩戴验收。请同时更新手机和 Watch 至 35 版；回放结果不能替代实际训练确认，其他姿态及旧无视频深蹲仍待验证。沿用既有编译警告。

## 历史 TestFlight 发布：2026-10-21（34）

- 版本：1.1.3 (34)，iPhone 与 Watch 一致；发布应用源码：`7740691`。
- Delivery UUID / ASC Build ID：`99e52d73-a0de-4519-8ff4-7a63764d4787`。
- 苹果状态：`BUILD-STATUS: VALID` / `IN_BETA_TESTING`，内部测试组 `flyingrtx` 可用，中英文测试说明已更新。
- 录像核对页调整为录像、次数与标注卡片、可展开的采样对齐控件；分享移至右上角，上传固定底部。辅助按钮改用紧凑样式，移除重复说明、来源与无明细文字。
- 只发布本次布局和文案清理；PhoneContentView 仅选取文案改动，其他未提交训练时长、模型和手机训练流程修改保留，未纳入安装包。没有改变采集、计数、上传协议或数据存储。
- 双端 Aqua 签名归档、导出及 IPA 版本、签名、HealthKit、配套关系核验通过；独立 iPhone 工程无签名编译通过。403 个源码文件与发布提交 SHA-256 一致。
- IPA SHA-256：`d4e425c42dd33df723f886b06438ad359d9aa3004384d5145d3ee07407464e3c`。
- 完整产物：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/TestFlight-1.1.3-34/`。
- 未覆盖安装用户当前应用，新布局尚未真机界面验收；既有录像、采样、标注和训练数据保留。沿用既有 HealthKit、捕获引用及 AppIntents 警告。请同时更新手机与 Watch 至 34 版。

## 历史 TestFlight 发布：2026-10-21（33）

- 版本：1.1.3 (33)，iPhone 与 Watch 一致；发布应用源码：`9955721`。
- Delivery UUID / ASC Build ID：`6772d378-cdbe-4da4-b2c4-c0666428c407`。
- 苹果状态：`BUILD-STATUS: VALID` / `IN_BETA_TESTING`，内部测试组 `flyingrtx` 已确认可用，中英文测试说明已更新。
- 采集列表增加动作、次数与录像时长；优先显示实际次数，未核对时明确显示手表计数与待核对状态，时长缺失时不伪造数值。删除改为居中确认弹窗，带本组动作及采集时间，保留取消与删除失败提示。
- 只包含这次列表、弹窗及对应本地化修改；其他未提交的训练时长、训练历史等工作保留，未纳入安装包。既有录像、采样、标注、训练记录与云端数据未改写。
- 双端 Aqua 签名归档、导出及 IPA 版本、签名、HealthKit、配套关系核验通过；独立 iPhone 工程无签名编译通过。403 个源码文件与发布提交逐文件 SHA-256 一致。
- IPA SHA-256：`b2ac2fd32f93935380370b776a19132ac9d7697df280dec79c27a04dccdd708e`。
- 完整发布产物：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/TestFlight-1.1.3-33/`。
- 新列表排版及居中弹窗尚未完成真机界面验收；没有覆盖安装或删除用户真实记录来测试。沿用既有 HealthKit、捕获引用及 AppIntents 警告。请同时更新手机与 Watch 至 33 版。

## 历史 TestFlight 发布：2026-10-20（32）

- 版本：1.1.3 (32)，iPhone 与 Watch 一致；发布应用源码：`8b5db5c`。
- Delivery UUID / ASC Build ID：`67d0f2c9-dc1d-4dbf-bf65-8b831162f7a1`。
- 苹果状态：`BUILD-STATUS: VALID` / `IN_BETA_TESTING`，内部测试组 `flyingrtx` 已确认包含本构建，中英文测试说明已更新。
- 同步采集结束后手机自动进入本组录像核对页，手表弹窗说明在手机调整实际次数并确认上传。上传增加阶段弹窗、录像真实传输百分比、云端确认与失败重试；采集记录支持左滑删除及删除前确认，已上传云端记录保留。
- 只发布采集相关改动，未提交的动作时长、训练历史界面等其他修改保留，未纳入本包。沿用 31 版白金图标，计数算法未改。
- 双端 Aqua 签名归档、导出及 IPA 版本、签名、HealthKit、配套关系核验通过；独立 iPhone 工程无签名编译通过。403 个源码文件与发布提交逐文件 SHA-256 一致。
- IPA SHA-256：`f0717eebbaaf36934506d8fe5e93d03d0cf6c8f906d640533957866fec583446`。
- 完整发布产物：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/TestFlight-1.1.3-32/`。仅清理旧临时目录中可重建的编译缓存以释放空间，旧发布归档、IPA、源码及用户训练资料均保留。
- 发布前只读核对真机：两端实际安装 30 版；今天 6 条深蹲的录像和采样均已保存在手机，3 条已有 8 处标注，云端无对应记录，6 条均通过生产格式校验。未改写、删除或代上传这些用户记录。
- 未安装覆盖用户当前应用，未执行 32 版真机采集、上传或删除交互验收；保留既有 HealthKit 弃用、捕获引用及 AppIntents 警告。请同时更新手机和手表至 32 版。

## 历史 TestFlight 发布：2026-10-20（31）

- 版本：1.1.3 (31)，iPhone 与 Watch 一致；发布源码：`07a3c8c`。
- Delivery UUID / ASC Build ID：`b84755dc-7bdb-470f-a558-7482b6c88323`。
- 苹果状态：`BUILD-STATUS: VALID` / `IN_BETA_TESTING`，已核对内部测试组 `flyingrtx` 可用，中英文测试说明已更新。
- 用户选择白金组第一款作为 A（原设计标号 W「流动金线」），已更新两端 AppIcon。使用已提交的 30 版应用源码加两张图标、两个工程构建号打包，工作区未提交的训练逻辑与其他设计文件未混入安装包。
- 双端 Aqua 签名归档、导出、IPA 版本/签名/HealthKit/配套关系核验通过；403 个源码快照文件 SHA-256 核对一致。手机实际打包图标与所选图标的资源编译结果解码后像素完全一致；Watch 图标 rendition 摘要一致。
- 源图 SHA-256：`29d267252ee3f59ac7b51556fe357009b322890e4be0e4e40c4870cf98ec8e5d`；IPA SHA-256：`cb218716dc8d8738053b217c5e308328386982e3023255cfff0e10f13cbad4f0`。
- 外置卷空间不足，完整发布产物保存在本机：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/TestFlight-1.1.3-31/`，含归档、IPA、源码归档、范围/签名/图标核验、上传和苹果状态记录。旧发布产物及用户训练记录保留。
- 两端真机均为 unavailable，未执行 31 版桌面或 Watch App 列表图标显示验收；本次仅图标与构建号更新，训练与同步行为沿用 30 版。保留既有 HealthKit 弃用、捕获引用及 AppIntents 警告。

## 历史 TestFlight 发布：2026-10-19（30）

- 版本：1.1.3 (30)，手机与 Watch 一致；发布应用源码：`e696632`，含空历史页开始/继续训练入口 `fe31a44`。
- Delivery UUID / ASC Build ID：`caa47e53-b166-4cd8-8561-a01065f92317`。
- 苹果状态：`BUILD-STATUS: VALID` / `IN_BETA_TESTING`，已核对内部测试组 `flyingrtx` 可用，中英文测试说明已更新。
- iPhone 与 Watch 的简体中文名称统一为“健身计数器”，英文与默认名称统一为 PowerReps。手机名称与权限说明新增本地化，主要训练、历史、设置、同步、休息、采集文案与无障碍标签补齐英文；手机记录日期不再固定中文。
- 两个有效工程均编译通过。双端 Aqua 签名归档、导出及 IPA 版本、签名、HealthKit、配套关系核验通过。403 个跟踪文件复制并核对 SHA-256，未包含未提交的图标设计。
- 用编译器提取的文案与最终安装包运行原生 Bundle 检查：手机 200 项、Watch 136 项中文界面键在两种语言中均可解析，名称及格式占位符核验通过。Release 优化可能改变提取键的源文件归属，校验器按编译 target 归属区分双端，不能按共享源码路径归属判断。
- 手机仍不可连接，未执行 30 版桌面名称、页面排版、Siri 或双端实际同步验收。不能将资源查找与编译通过描述为真机交互通过。用户应将两端更新到 30 版后检查；已有历史与计数算法未在本轮改动。
- 构建目录：`build/TestFlight-1.1.3-30/`，含归档、IPA、源码 SHA-256、签名、原生本地化校验、苹果状态、内部组归属及发布说明证据。
- [本地化实现与验证](docs/localization.md)。工程、签名会话与 ASC 配置沿用此前已验证流程。

## 历史 TestFlight 发布：2026-10-19（29）

- 版本：1.1.3 (29)，手机与 Watch 一致；发布源码：`de9c1a0`。
- Delivery UUID / ASC Build ID：`e05a7736-5b4f-4881-943a-1554114eca7b`。
- 苹果状态：`BUILD-STATUS: VALID` / `IN_BETA_TESTING`，已核对内部测试组 `flyingrtx` 可用，中文测试说明已更新。
- 构建目录：`build/TestFlight-1.1.3-29/`，含归档、IPA、249 个源码文件 SHA-256、签名/权限/版本核验、原始上传及苹果状态记录。
- 普通 Watch 训练结束后自动补传历史到手机。复用现有 WCSession delegate，使用独立消息类型及后台队列；手机原子保存后才回执，按原始 UUID 去重，手机删除标记阻止重复导入。已有录像采集通道保留。
- 只读查询发现手表仍为 27 版，并成功备份 82 条真实历史。用发布代码在隔离存储中检查字段保留、去重、重启、原子文件恢复、删除后不恢复，结果通过。完整备份属于私有资料，保存在忽略目录中，不提交。
- 双端签名归档/导出与 IPA 签名核验通过，独立手机工程无签名编译通过。真实手机当前不可连接，未完成 29 版双端传输验收；不能把隔离存储导入验证写成已经在用户手机恢复成功。
- 用户需同时更新手机和手表至 29 版并打开两端应用。手机“训练记录”页可手动同步；后续排查先检查双端实际安装构建号，避免手机更新而手表仍停留旧版。
- 工程、Team、凭据位置、导出与 Aqua 签名流程沿用已验证配置。详细说明见 [普通训练同步](docs/watch-workout-sync.md)。

## 历史 TestFlight 发布：2026-10-18（28）

- 版本：1.1.3 (28)，手机与 Watch 一致。
- Delivery UUID / ASC Build ID：`8c40044f-e86c-463f-a20b-12587460553a`。
- 苹果状态：`BUILD-STATUS: VALID`；`IN_BETA_TESTING`，已确认内部测试组 `flyingrtx` 可用，中文测试说明已更新。
- 发布源码提交：`978d728`。构建目录：`build/TestFlight-1.1.3-28/`；包含归档、IPA、签名/权限核验、247 个源码文件 SHA-256、上传及苹果状态记录。
- Watch 普通训练及采集改用融合运动数据和传感器时间，前两次一起确认，运行中为延迟估计，结束先核准再保存。iPhone 采集详情使用同一模块做本机复核，保留原始计数与标注。
- 11 条真实卧推回放与云端可计数/需核对结论一致，5 条视频记录总次数全部一致；完成点仍有 4/25 处与视频偏差超过半秒。无视频旧记录的人工次数不改。
- 双端签名归档、导出及签名/权限/版本核验通过，独立 iPhone 工程无签名编译通过。手机与手表离线，未执行新的佩戴或真机交互验收；没有把回放当成独立准确率验证。
- 工程、Team、凭据位置和导出设置沿用下方 27 版已验证流程。详细说明见 [Watch / iPhone 卧推 v8](docs/bench-watch-ios-v8.md)。

## 历史 TestFlight 发布：2026-10-18（27）

- 版本：1.1.3 (27)，手机与 Watch 一致。
- Delivery UUID / ASC Build ID：`ff39ea86-b9f3-40db-8fdc-979ca74d0b97`。
- 苹果状态：`BUILD-STATUS: VALID`；`IN_BETA_TESTING`，已核对属于内部测试组 `flyingrtx`。
- 构建目录：`build/TestFlight-1.1.3-27/`。包含归档、IPA、签名与权限核验、源码 SHA-256 清单、上传及苹果状态记录。
- 发布工程与 scheme：`GymCountSync.xcodeproj` / `GymCount Capture`；Team：`8BPSC5L74V`；手机 Bundle ID：`com.flyingrtx.GymCount`。
- ASC 凭据从本机 `~/.appstoreconnect/assettimemachine.env` 读取；只确认必需变量和密钥文件存在，不输出值或提交文件。沿用上一版导出设置，`manageAppVersionAndBuildNumber=false`、`method=app-store-connect`、`testFlightInternalTestingOnly=true`。
- 本轮真机 UI 测试已尝试，但手机为 unavailable，无法匹配测试目标；未执行交互验收。发布不代表休息通知、重启恢复等真机功能已验收。
