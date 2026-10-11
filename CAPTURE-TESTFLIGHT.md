## 2026-10-10：精简文案与记录上传状态，1.1.3 (26) 已发布

手机校时统一显示「正在准备采集…」，减少手机与手表的重复提示和说明小字。采集记录每行显示「未上传 / 仅采样已上传 / 已上传」，录像与采样都确认成功后才显示已上传。授权引导和必要错误提示保留。

- 双端编译与既有手机页面导航回归通过；最终 IPA 的双端版本、签名、HealthKit 和后台训练配置核验通过。
- Apple 状态：`BUILD-STATUS: VALID` / `IN_BETA_TESTING`，已在内部测试组 `flyingrtx`。
- Delivery UUID / ASC Build ID：`680d49b6-2589-4ba7-acab-e971ff8a7e66`。
- 构建目录：`/Users/xiangjunsheng/GymCount/build/TestFlight-1.1.3-26/`。
- [修改与验证范围](docs/capture-copy-cleanup.md)

## 2026-10-10：采样中断保护，1.1.3 (25) 已发布

手表独立采集与手机同步采集统一启动体能训练会话，等会话运行后才启动传感器。异常缺口首次振动提示，停止时保留有效采样及诊断；时长使用实际经过时间，云端 v6 可检测首尾未覆盖。

- 五份真实记录的十条采样流验证通过：四份中断全部检出，完整的 5 次录像记录无误报；云端 17 份真实重放、18 项后端回归及 10 项手表回归通过。
- Xcode 桌面归档上传成功，最终 IPA 的双端版本、签名、HealthKit 与 Watch 后台训练配置核验通过。
- Apple 状态：`BUILD-STATUS: VALID` / `IN_BETA_TESTING`，已在内部测试组 `flyingrtx`。
- 云端 v6 已上线，双 API 运行检查及公开健康检查通过；17 份记录已重算，原始采样、人工次数、修改历史和录像关联均保留，完整录像记录仍为 5 次。
- Delivery UUID / ASC Build ID：`ba46ef74-524d-42d7-8242-e288ab06a95b`。
- 构建目录：`/Users/xiangjunsheng/GymCount/build/TestFlight-1.1.3-25/`。
- 真机熄屏、抬腕后的连续采样需要新版本实际采集验证，历史缺失数据无法恢复。
- [修复与验证范围](docs/capture-continuity.md)

## 2026-10-10：私有 COS 录像上传，1.1.3 (24) 已发布

手机“上传录像与采样”同时提交采样和无音频录像，按同一 UUID 保存至现有私有 COS 并关联时间对齐与逐次参考标注。两部分完成才提示成功，失败保留本机文件并允许补传；网站查看页支持播放，删除记录同时删除已关联录像。已有记录无需重新采集即可补传；本地改过次数时提示在网站修改云端人工标签。

- 12 项后端、12 项页面回归及时间对齐校验通过；双端归档和最终 IPA 的版本、签名与 HealthKit 配置核验通过。
- Native Foundation 上传器实测已发布 API 和 COS，重复上传保持同一记录；私有访问、文件校验、授权 Range 播放、篡改拒绝及桌面/手机页面播放通过。验证记录及对象已删除，用户记录保留。未据此声称真机相机、Watch 同步或算法准确率已验证。
- Apple 状态：`BUILD-STATUS: VALID` / `IN_BETA_TESTING`，已在内部测试组 `flyingrtx`。
- Delivery UUID / ASC Build ID：`f2390e1e-2a5d-446d-b41a-5470958788df`。
- 构建目录：`/Users/xiangjunsheng/GymCount/build/TestFlight-1.1.3-24/`。
- [实现与验证范围](docs/capture-cos-video.md)

## 2026-10-09：健康权限路径引导，1.1.3 (22) 已发布

手表授权失败弹窗及设置帮助写明「在手表本机」操作，提供完整健康权限路径、体能训练写入开关、可能的 PowerReps 应用别名及返回采集页检查权限的步骤。iOS 设置新增手表健康权限帮助入口。长说明收进弹窗与帮助页，未增加采集页常驻文字。

- iOS 模拟器双端 Release 构建与帮助入口导航测试通过；40mm / 46mm 设置帮助和 40mm 原生失败弹窗隔离截图核验通过，副本已卸载。
- 双端签名归档、导出、最终 IPA 版本及健康权限配置核验通过。
- Apple 状态：`BUILD-STATUS: VALID` / `IN_BETA_TESTING`，确认在内部测试组 `flyingrtx`。
- Delivery UUID / ASC Build ID：`d288b054-8072-4370-b9d3-ddad98a85cba`。
- 构建目录：`/Users/xiangjunsheng/GymCount/build/TestFlight-1.1.3-22/`。
- [引导内容与验证范围](docs/capture-permission-guide.md)

## 2026-10-09：授权反馈与采集页精简，1.1.3 (21) 已发布

重复授权改为查询系统是否需要弹窗并检查实际体能训练写入状态；已作出允许或拒绝选择时不再错误提示等待系统弹窗。授权只从可见、前台的采集页请求；失败有明确弹窗与安全错误日志。权限改变自动刷新并清理旧授权提示，不覆盖上传结果。合并冗余授权按钮与说明，固定采集标题，滚动按钮避开系统时间。

- 9 项 Watch 回归通过；40mm / 46mm 首屏与底部滚动位置使用真实视图隔离副本截图核验，副本已卸载。
- 双端归档、导出、签名、HealthKit entitlement、中文用途说明及最终 IPA 版本核验通过。
- Apple 状态：`BUILD-STATUS: VALID` / `IN_BETA_TESTING`，确认在内部测试组 `flyingrtx`。
- Delivery UUID / ASC Build ID：`866cc5b2-945b-438e-a2bd-7d20167b2519`。
- 构建目录：`/Users/xiangjunsheng/GymCount/build/TestFlight-1.1.3-21/`。
- [问题依据、修复与验证限制](docs/capture-permission-feedback.md)

真机查询确认升级前手表为 20 版；未直接读取其 HealthKit 权限状态。手机全开与手表未授权之间的系统差异，及升级后完整同步采集，仍需真机验证。

## 2026-10-09：iOS 和 Watch 主要页面统一样式，1.1.3 (20) 已发布

手表首页、历史、设置、训练计数、重量编辑、采集及结果核对页面共用顶部布局、标题、字号、边距和按钮规范。长标题或顶部带操作按钮的页面避开系统时钟。重量编辑与帮助页纳入公共样式；中文重量单位及小尺寸设置标签避免换行。iOS 主次按钮统一字体与高度，列表、设置、采集和核对页面使用紧凑导航标题。沿用现有黑底、薄荷绿与深灰卡片。

- 已有本轮 4 项 Watch、2 项 iPhone 回归通过；40mm、46mm 共 18 张隔离页面截图和 iPhone 测试截图核验完成，副本已卸载。
- 双端归档、导出、上传与最终 IPA 版本、签名、HealthKit entitlement、中文用途说明及配置文件允许项核验通过。
- 归档执行器回传超时，但实际日志为 ARCHIVE SUCCEEDED，归档文件、签名核验及后续导出全部成功，未重复归档。
- Apple 状态：`BUILD-STATUS: VALID` / `IN_BETA_TESTING`，已在内部测试组 `flyingrtx`。
- Delivery UUID / ASC Build ID：`49ad314b-ac94-4612-a6d8-b378c1b93a50`。
- 构建目录：`/Users/xiangjunsheng/GymCount/build/TestFlight-1.1.3-20/`。
- [样式检查、范围与截图](docs/style-consistency-audit.md)

## 2026-10-09：采集标题与系统时间并排，1.1.3 (19) 已发布

上一版自定义标题仍占 44 点高度。采集页将标题布局槽位改为 28 点、顶部补偿由 24 点减至 12 点，待采集内容整体再上移 28 点。46mm 标题与系统时间并排，开始采集及手机同步录像按钮首屏完整显示；40mm 开始采集按钮完整显示，标题、时间和动作不重叠。

- 两种尺寸使用隔离副本真实根页面与 CollectionView 截图核验；模拟器 Release 构建通过，未启动权限、传感器或上传，副本已卸载。
- 双端归档、导出、上传、签名及最终 IPA 版本与健康权限配置核验通过。排版调整沿用 18 版流程回归结果，未重复运行相同流程测试。
- Apple 状态：`BUILD-STATUS: VALID` / `IN_BETA_TESTING`，已在内部测试组 `flyingrtx`。
- Delivery UUID / ASC Build ID：`6c4f07c2-b6b3-41e2-9d56-098555169dad`。
- 构建目录：`/Users/xiangjunsheng/GymCount/build/TestFlight-1.1.3-19/`。
- [排版调整与验证](docs/capture-compact-header.md)

## 2026-10-09：采集自动请求授权、缩小留白并移除速度选择，1.1.3 (18) 已发布

手表首次进入采集页自动发起体能训练写入授权；手机点击开始同步时先完成系统授权，再唤起手表、校时和录像。手表通信回复不等待用户关闭授权窗口；手机授权确认与连接期限分开，并保留取消、离开页面和迟到结果保护。移除动作速度选项及其弹窗，保持旧数据协议兼容。采集根页去掉多余导航容器，顶部留白缩小，系统时钟与标题不重叠。

- 测试：4 项 Watch 回归、2 项 iPhone 界面回归通过；40mm 和 46mm 隔离模拟器使用真实根页面及采集视图核验布局，未授权、启动传感器或上传，副本已卸载。
- 双端归档、导出、签名、HealthKit entitlement、用途说明、配置文件、最终 IPA 版本验证通过。
- Apple 状态：`BUILD-STATUS: VALID` / `IN_BETA_TESTING`，确认在内部测试组 `flyingrtx`。
- Delivery UUID / ASC Build ID：`eb4658cc-6ced-421d-b5c7-0de5f97c1625`。
- 构建目录：`/Users/xiangjunsheng/GymCount/build/TestFlight-1.1.3-18/`。
- 测试结果：`build/AutomaticPermissionWatch.xcresult`、`build/AutomaticPermissionPhone.xcresult`。
- [修复与验证说明](docs/capture-automatic-authorization.md)

真实系统授权弹窗和允许后的完整双端采集仍需更新两端后真机复测。

## 2026-10-09：手机指令自动切换手表采集页，1.1.3 (17) 已发布

收到手机 prepare 即切换 Watch 根页面到对应动作采集页，授权入口与准备失败原因直接显示；采样和页面展示分开，结束及上传后继续留在结果页。已有训练和未确认本地采集不被覆盖。手机手表不可达时使用 HealthKit 请求系统启动配套 Watch，委托回调打开采集页，传感器仍由随后的 start 指令启动；唤起有期限，并受原有超时、取消和迟到回复保护。

- 4 项 Watch 回归和 2 项 iPhone 回归通过；隔离副本使用真实 App 根视图注入卧推 prepare，截图确认自动进入卧推采集页，未启动传感器或上传，副本已卸载。
- 双端签名归档、导出、上传成功，最终 IPA 两端版本、HealthKit entitlement、配置文件与中文用途说明验证通过。
- Apple 状态：`VALID` / `IN_BETA_TESTING`，确认在内部测试组 `flyingrtx`。
- Delivery UUID / ASC Build ID：`7078e969-22be-4668-9213-3e14cf0d3e82`。
- 构建目录：`/Users/xiangjunsheng/GymCount/build/TestFlight-1.1.3-17/`。
- 测试结果：`build/CaptureRoutingWatch-final.xcresult`、`build/CaptureRoutingPhone.xcresult`。
- [修复说明及 Apple 唤起依据](docs/capture-phone-navigation.md)

真机后台启动、抬腕后实际显示与完整双端采集仍需更新两端后复测；不把模拟器页面或签名验证当作真机唤起成功。

## 2026-10-09：上传前核对次数与云端记录管理，1.1.3 (16) 已发布

手表统一当前操作提示，避免旧权限错误与上传成功同时出现；手机上传结果同时传递到手表。手机与手表上传前确认实际次数，上传过程中禁止重复提交与继续改数。手表失败后恢复本组核对界面，文件和填写次数保留，成功后才从本地队列移除。网络结果不确定或 409 内容冲突时明确引导在网站修改已有次数。

网站每行可修改次数、删除记录。修改保持原始采样和标注历史；删除先确认、仅站长可操作，失败保留记录。桌面与手机布局已用隔离示例数据核验保存、取消与删除成功。

- 测试：27 项后端、11 项网站、2 项 Watch 上传、2 项 iPhone 回归通过；双端签名、HealthKit 权限、用途说明、配置文件及最终 IPA 版本检查通过。
- Apple 状态：`VALID` / `IN_BETA_TESTING`，已确认在内部测试组 `flyingrtx`。
- Delivery UUID / ASC Build ID：`b566bad4-ec2f-4efc-b6de-4a513fcfe7a9`。
- 构建目录：`/Users/xiangjunsheng/GymCount/build/TestFlight-1.1.3-16/`，内含上传日志、Apple 状态、授权与网站资源凭证。
- 网站后端 revision：`83b73ad7032cfeba7b5094aaf404f716c2dc5d5c`；网站前端 revision：`b242da843bfbd82726dde778497fae4e4b36801b`，均已生产核验。
- [修复依据与限制](docs/capture-upload-recovery.md)

本次未改计数算法。真实手表网络波动和完整采集流程仍需更新后复测；模拟器及隔离页面验证不代表真机链路已全部验证。

## 2026-10-09：补齐配套手机健康授权，1.1.3 (15) 已发布

用户确认手机点击后手表响应并提示体能训练权限，当前阻塞从连接缩小为授权。第 14 版手机源配置及签名包均缺少 HealthKit capability、用途说明和承接扩展授权的 UIApplicationDelegate 回调。配套 iPhone 目标现补齐能力、中文读写说明，并通过 UIApplicationDelegateAdaptor 调用 handleAuthorizationForExtension。手表采集页增加“允许体能训练”入口，权限等待与连接等待分开显示，前台刷新权限状态。仅修复授权链路，未增加健康数据读取或改动计数算法。

2 项界面回归通过（超时/取消/迟到回复、原有导航/计数/保存），结果 `build/CaptureHealthAuthorization.xcresult`。双端签名归档、导出、上传通过。归档和最终 IPA 都确认两端为 1.1.3 (15)，手机与手表 HealthKit entitlement、描述与配置文件允许项完整；验证凭证为构建目录的 `authorization-verification.json` 和 `ipa-authorization-verification.json`。桌面导出工具回传超时，但实际导出日志成功、最终 IPA 检查和上传成功，未重复导出。

- 发布状态：`BUILD-STATUS: VALID`；`IN_BETA_TESTING`，确认在内部测试组 `flyingrtx`
- Delivery UUID / ASC Build ID：`abea8b75-2ee5-4735-beca-08e6dceda738`
- 构建目录：`/Users/xiangjunsheng/GymCount/build/TestFlight-1.1.3-15/`
- [授权修复与依据](docs/capture-health-authorization.md)

更新两端后，在手表采集页点“允许体能训练”，同时查看手机并完成系统授权，再回到手机开始同步。真实授权弹窗及允许后的双端采集仍需真机验证；不把配置校验或模拟器测试视为真机授权完成。

## 2026-10-09：同步启动恢复与手表触感反馈，1.1.3 (14) 已发布

手表准备回复不再等待 HealthKit 权限弹窗，权限在采集页完成，未授权时明确指引。手机启动全流程有 25 秒期限、分步提示及取消入口；超时/取消后的旧回复不继续启动。启动中离开页面或进入后台也撤销准备。手表开始识别、开始/结束采集、请求手机与上传增加点击触感，成功及失败使用相应触感；手机上传在手表可达时通知触感。

隔离界面回归通过（2 个测试、0 次失败）：覆盖准备回复晚于总期限、按钮恢复、取消后迟到回复不启动，以及原有导航、计数和保存；`build/CaptureStartFix-final.xcresult`、`build/CaptureStartFix-evidence/`。时间同步与录像关联校验通过。两端签名归档、导出、上传通过，均为 1.1.3 (14)。真机安装包确认不含模拟握手测试入口。桌面执行器导出结果回传超时，但导出日志成功、安装包生成且上传成功。苹果状态查询首次出现瞬时 500 后返回 VALID，ASC API 独立确认有效并在内部组。

- 发布状态：`BUILD-STATUS: VALID`；`IN_BETA_TESTING`，内部测试组 `flyingrtx`
- Delivery UUID / ASC Build ID：`4226de10-9047-4a7c-8075-e078cb4a6888`
- 构建目录：`/Users/xiangjunsheng/GymCount/build/TestFlight-1.1.3-14/`
- 凭证：`archive.log`、`export.log`、`upload.log`、`build-status.log`、`asc-state.json`
- [修复与验证说明](docs/capture-start-recovery.md)

真机具体卡住阶段尚缺少设备日志；本版修复已确认的等待机制。手表实际触感、健康权限交互及双端采集仍需更新两端后验证。

## 2026-10-09：iOS 与手表统一薄荷界面，1.1.3 (13) 已发布

两端采用黑底、薄荷绿操作与深灰卡片；iOS 覆盖训练、历史、设置、开发采集和录像核对页面，标题、操作及日期使用中文。手表首页、计数、采集、历史及设置同步更新。保留计数、采集、存储与上传流程。

iOS 现有隔离界面测试通过（1 个测试、0 次失败），覆盖导航、计数和保存历史，结果为 `build/PhoneMint/Navigation-verified.xcresult`。双端 Release 签名归档、导出与上传通过；归档两端版本均为 1.1.3 (13)，签名验证通过。手表原生布局截图已生成，严格概念像素比对未通过，完整交互核验尚未完成；录像与手表同步采集仍需真机验证。

- 发布状态：`BUILD-STATUS: VALID`；`IN_BETA_TESTING`，已确认构建在内部测试组 `flyingrtx` 中
- Delivery UUID / ASC Build ID：`3581b675-d983-4947-a5bc-b3f84144a5ec`
- 构建目录：`/Users/xiangjunsheng/GymCount/build/TestFlight-1.1.3-13/`
- 发布凭证：`archive.log`、`export.log`、`upload.log`、`build-status.log`、`asc-state.json`
- iOS 实际页面：`build/PhoneMint/native-overview.png`

## 2026-10-09：C 暖白陶土色 iPhone 界面，1.1.3 (12)

用户选择 C（第三套训练首页），在现有 SwiftUI 界面实现暖白背景、陶土色主按钮、动作选择、大字号重量和固定底部导航。训练中、历史和设置采用相同配色。保留已有动作人体线稿与手动计数；采集仍位于设置里的开发者工具，未改变采集协议、算法或本地训练数据结构。

iPhone 17 Pro 与较小的 iPhone 17e 导航、开发者工具往返、手动计次及保存历史 UI 测试通过。参考图 850×1850 规范化到 1206×2622，与实际截图比较 MAE 0.031349、像素相似度 0.968651、容差 24 内占比 0.944822，整体默认门槛通过。人体线稿、系统字体、状态栏与概念图有可见差异；没有使用整图背景冒充 UI。真机同步采集未在本次验证。

- 产品变更：`GymCount iOS/PhoneContentView.swift`
- 已选参考：`design/concepts/training-home/home-03-warm-studio.png`
- 截图与对比报告：`design/evidence/warm-studio/`
- UI 测试：`build/StudioUI-12d.xcresult`、`build/StudioUI-12-small.xcresult`
- 两端归档版本：1.1.3 (12)，归档与导出通过
- Delivery UUID：`f2059353-f53b-46df-9f2e-37c4968634f6`
- 发布状态：`BUILD-STATUS: VALID`；`IN_BETA_TESTING`，已确认在内部测试组 `flyingrtx` 中
- 构建目录：`/Users/xiangjunsheng/GymCount/build/TestFlight-1.1.3-12/`

## 2026-10-09：训练首页与开发采集入口分离，1.1.3 (11)

默认首页恢复普通训练，底部为训练、历史、设置。保留手动记次与保存训练记录；同步录像、原始采样及录像标注归入“设置 → 开发者工具”。相机仅在进入同步录像页后申请权限和启动；退出该页停止相机与当前采集。手表不能从普通首页发起手机录像。

导航 UI 测试通过，覆盖默认首页无采集入口和权限弹窗、开发者工具与采集页往返、手动完成一次并保存历史。结果包 `build/PhoneNavigation-10d.xcresult`，截图 `build/PhoneNavigation-final-evidence/`。版本号调整后签名归档、导出通过，两端均为 1.1.3 (11)。双端真机录像与无线采样尚未验证。本次没有训练新模型或改变计数算法。

首页视觉探索位于 `design/concepts/training-home/`，三套概念等待用户选择，尚未应用到产品 UI。

- Delivery UUID：`660fa574-24fa-405f-b111-21d6e582cd83`
- 状态：`BUILD-STATUS: VALID`；`IN_BETA_TESTING`，已确认在内部测试组 `flyingrtx` 中
- 构建目录：`/Users/xiangjunsheng/GymCount/build/TestFlight-1.1.3-11/`

## 2026-10-09：动作线条图标，iPhone 与 Watch 1.1.3 (10) 已发布

沿用配套采集项目 `GymCountSync.xcodeproj`，iOS 和 Watch 同时更新到 1.1.3 (10)。两端包含 43 个独立 SVG 资源（40 个训练动作、3 个采集类别），沿用已选定的人体线稿；Watch 列表图标调整为 32 × 32 pt。保留已有手机录像与手表采样功能，新增图标资源不代表新增计数算法或全部动作的采集入口。

配套 Release 模拟器构建及采集时间映射校验通过，43 个 SVG 完整性和轮廓一致性校验通过。签名归档、导出与上传成功；归档和 IPA 中两端版本均为 1.1.3 (10)，签名验证通过，两个 Assets.car 均确认包含 43 个动作资源。原生图标预览已核验；本次未进行双端真机采集验证。

- 发布状态：`BUILD-STATUS: VALID`；App Store Connect 为 `IN_BETA_TESTING`，确认新构建已在现有内部测试组 `flyingrtx` 中
- Delivery UUID / ASC Build ID：`0fb498e6-78a7-43bb-af58-354217ff4e50`
- 构建目录：`/Users/xiangjunsheng/GymCount/build/TestFlight-1.1.3-10/`
- 归档：构建目录内 `GymCount.xcarchive`；安装包：`export/GymCount.ipa`
- 发布凭证：`archive.log`、`export.log`、`upload.log`、`build-status.log`（状态摘录）、`asc-state.json`（包括内部测试组关系）

## 2026-10-09：iPhone 与 Watch 配套录像采集，1.1.3 (9) 已发布

新增配套项目 `GymCountSync.xcodeproj`（scheme `GymCount Capture`），沿用现有 GymCount bundle ID。手机后置 720p 录像，手表完整运动采样与实验计数，支持从手机或手表发起、任一端结束。Watch 使用力量训练 HKWorkoutSession 和 workout-processing 后台模式；采样连续性等待真机检验。

同一 UUID 关联视频和采样，5 次往返校时保存估计偏移与延迟；不能宣称逐帧精确同步。录像回看支持逐次完成标记、撤销和对齐修正，采样可补传、填写实际次数后上传；视频保留在手机，通过分享导出完整标注文件。此次未训练模型、未修复旧计数准确率。

Release 模拟器构建通过（包含 Watch 目标），iPhone 已安装启动并检查权限页。相机在模拟器不可用，不能代替双端真机验证。时间映射、处理延迟、缺失时间、标注保存及延迟拒绝校验通过，签名归档和导出通过。

- 构建目录：`/Users/xiangjunsheng/GymCount/build/TestFlight-1.1.3-9/`
- Delivery UUID / ASC Build ID：`8596aa1b-5dbe-4fc6-b6ab-e8bc31109efd`
- 发布状态：`BUILD-STATUS: VALID`；App Store Connect 为 `IN_BETA_TESTING`，已确认构建在现有内部组 `flyingrtx` 中，可通过 TestFlight 更新 iPhone 和 Watch
- 处理与组别凭证：构建目录内 `build-status.log`、`asc-state.json`
- 使用及验证说明：[iPhone 与 Watch 同步采集](docs/phone-watch-video-capture.md)

Apple 官方 TN3157 支持给现有 watch-only 增加 iOS companion。此前文档“不能增加配套应用”的结论需要更正；发布到正式 App Store 后不能再退回 watch-only。本次仅内部 TestFlight，没有提交正式 App Store 审核。

## 2026-10-09：弯举采集，1.1.3 (8) 已发布

新增“弯举”动作（bicep_curl），保留完整运动采样、速度、备注和人工实际次数。弯举不运行旧的三动作 Watch 计数器，对照次数为 0，算法标记 capture-only-20261009；上传后网站显示云端实验算法的次数，支持弯举筛选及人工次数修改。

网站前后端已发布 58a774daae06b121cddf2fd3a7b6441a29d7ed45，两台生产后端均通过 Swift 实际编码的弯举 v2 格式校验，线上筛选已实际核对。后端 14 项、前端 5 项测试及前端生产构建通过，真实采集目标 Release 模拟器构建成功。40mm 布局预览实际选择弯举、开始/结束采集并将人工次数从 10 改为 11，未向生产库写入模拟样本。签名归档包含弯举标识和完整运动采集字段。真实 Watch 弯举采样及算法准确率等待新数据验证。

- 上传版本：1.1.3 (8)，仅内部 TestFlight
- Delivery UUID / ASC Build ID：`d087004b-e3aa-440a-b6bb-687011da424d`
- 状态：`BUILD-STATUS: VALID`；App Store Connect 为 `IN_BETA_TESTING`，已在现有内部测试组 `flyingrtx` 中
- 归档：`/Users/xiangjunsheng/Library/Developer/Xcode/Archives/2026-10-09/GymCount Capture 2026-10-9, 10.37.xcarchive`
- 发布凭证：`/Users/xiangjunsheng/GymCount/build/TestFlight-1.1.3-8/`

安装后：设置 → 采集测试 → 选择动作 → 弯举。每组前后留静止片段，填写实际次数并上传；网站查看云端次数及误差。

## 2026-10-09：速度选择布局修复，1.1.3 (7)

修复滚动采集页中默认 Picker 被压成细线的问题。动作速度改为至少 44 pt 高的按钮，点击进入独立列表；选择后关闭列表并回填速度，保留正常、慢速、快速、混合四种值。

40mm 模拟器复现旧问题，修复后在 40mm / 46mm 屏幕验证按钮正常显示；40mm 实际点选慢速、滚动选择混合并回填成功。布局预览与真实采集目标 Release 模拟器构建均通过，签名归档确认包含新速度入口与完整运动采集。

- 上传版本：1.1.3 (7)，仅内部 TestFlight
- Delivery UUID：`2636250d-1869-4a92-8126-4c50771a4e74`
- 状态：`BUILD-STATUS: VALID`；App Store Connect 为 `IN_BETA_TESTING`，已在现有内部测试组 `flyingrtx` 中，可通过 TestFlight 更新
- 归档：`/Users/xiangjunsheng/Library/Developer/Xcode/Archives/2026-10-09/GymCount Capture 2026-10-9, 09.58.xcarchive`
- 构建、截图与发布凭证：`/Users/xiangjunsheng/GymCount/build/TestFlight-1.1.3-7/`

## 2026-10-09：完整运动采集，1.1.3 (6) 已发布

代码已扩展为协议 v2，多路运动信号与非训练样本。单组最多 3 分钟，保留失败上传的本地文件。详情见 [完整运动采集说明](docs/full-motion-capture.md)。
网站前后端已发布 `a547c55682042bcd0dace8513ee9350c92fd26c0`，两台生产后端均通过 Swift 实际编码的 v2 协议校验；管理页旧记录可正常查看。

Xcode 归档并上传成功，Apple 已确认 `BUILD-STATUS: VALID`，App Store Connect 为 `IN_BETA_TESTING`，构建已在现有内部组 `flyingrtx` 中。
- Delivery UUID / ASC Build ID：`899ba574-728d-4662-98a2-6ad7a55f2270`
- 归档：`/Users/xiangjunsheng/Library/Developer/Xcode/Archives/2026-10-09/GymCount Capture 2026-10-9, 09.38.xcarchive`
- 本地发布凭证目录：`/Users/xiangjunsheng/GymCount/build/TestFlight-1.1.3-6/`

本地采集 Release 模拟器构建通过，签名归档确认包含完整采集入口。真实 Watch 多传感器采样与上传仍需安装本包后验证；本次未修改计数算法。

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

执行 `scripts/archive-capture.sh`，或在 Xcode 打开专用 `GymCountCapture.xcodeproj` 后选择 Archive。
专用项目的 Watch Release 配置和脚本均启用 `GYMCOUNT_CAPTURE`，包含原始采集和次数标注。主项目普通 Release 不含该入口。

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
