# GymCount 工作约定

@/Users/xiangjunsheng/.codex/RTK.md

## 模拟器复用与内置盘空间

- 内置盘空间有限。日常开发与界面验证固定复用现有模拟器，不为每轮修改、截图、语言、主题或字号检查新建设备；隔离测试通过独立 App 标识和存储目录实现。
- 默认复用大屏 iPhone `GymCount Records Large`（`CD183797-B641-447D-A898-1CB5DEDD99DA`）、小屏 iPhone `GymCount Records Compact`（`B77E5BAE-AD6A-4EC0-82F3-FCAD00DD5C3D`）及 Watch `PowerReps Saved Motion 41`（`F5D4F639-C91D-409A-BD9D-F0AC291A6D31`）；使用前先核对设备仍存在。测试关闭并行执行，避免无谓的模拟器克隆。
- Watch 日常只保留并复用上述 41mm 一台；中英文、配色、字号及不同页面验证均使用同一设备，不额外创建、克隆或启动其他 Watch 模拟器。只有用户明确要求额外 Watch 设备时才例外；无法覆盖的尺寸验收如实注明，不自行增建设备。
- iPhone 仅在现有设备无法覆盖必要的系统版本、尺寸或配对条件时新增，新增前说明原因并检查空间；临时设备验证后及时清理，不积累按版本或设计方案命名的副本。
- 清理前核对设备状态、使用情况及数据。保留正在使用的设备、其他项目设备、真实训练资料和验证证据；有需要保留的测试数据先备份到外置卷并核验，再删除冗余设备。不得为腾空间重置或删除用户真机 App 数据。
- 2026-10-27 已清理 7 台关机且无进程使用的旧 PowerReps 验收模拟器；应用数据及设备信息先备份并逐文件校验，备份和清理凭证位于 `/Volumes/江波龙/PowerReps-Simulator-Backups/20261027/`。上述三台复用设备及其他项目设备保留。
- 同日按用户“Watch 只用一个”的要求，再删除 5 台关机且无打开文件的 Watch 设备，仅保留上述 41mm；删除目录实际分配约 1.28 GB。完整设备目录先备份并校验文件内容、目录及符号链接，备份及凭证位于 `/Volumes/江波龙/PowerReps-Simulator-Backups/20261027/watch-single-device/`；保留 Watch 的训练历史校验一致，其余模拟器清单和配对关系未变。

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

- 开发者录像／原始采集只允许 `DEBUG`：iOS 开发者工具、采集记录和标注页面，Watch 高级采集页面及远程采集指令均不得进入 Release／TestFlight／App Store 的用户流程。Release 不声明相机权限。`GYMCOUNT_CAPTURE` 目前还承载配套 Watch 的普通训练同步，不能直接移除该标记而停掉记录、报告和传感器传输；采集 UI 与远程指令独立受 `DEBUG` 约束。保留历史采集文件，不因隐藏入口删除资料；正常训练的传感器时间轴与计数反馈继续提供。

- iOS 视觉以 [统一规范](docs/ios-design-system.md) 和 `GymCount iOS/RecordStyle.swift` 为准：同级字体、16 点正文边线、44 点触控高度、指标数字／单位、分区、按钮、局部空状态及按压反馈均复用共享入口。新增或修改页面不得另设相同角色的独立规格；系统导航、文件面板及具有任务依据的实时大计数保留明确的原生／功能例外。

- `GymCountSync.xcodeproj` 是已有的手机与手表配套工程；`GymCount Capture` 用于配套版本，`GymCount Phone UI Tests` 用于手机界面测试。`GymCount.xcodeproj` 是独立 iPhone 工程。它们共用部分源码，修改后检查受影响工程。
- 无签名编译、签名构建、UI 测试实际执行、真机功能验收、TestFlight 发布分别报告。`build-for-testing` 成功只表示测试包已构建，不表示测试执行通过。
- 真机测试使用独立安装副本和隔离存储，保留设备当前应用及训练记录。未经相应发布指令，不把构建成功描述为已经发布。
- 记录页使用自定义底栏时，底栏应实际占据布局空间；不要叠加隐藏的系统 TabView 容器。趋势明细的展开按钮与子行分开命中，验收必须滚到最后一行并实际打开对应记录，不能只检查截图可见。2026-10-27 修复及真实原生证据见 [详情与趋势修复](docs/detail-trends-repair-20261027.md)。

详细证据见 [iPhone 多组训练完善记录](docs/phone-training-flow.md)。

## Watch 紧凑布局：2026-11-04（TestFlight 57）

- 非交互页头的正文预留 32 点，交互返回区仍为 44 点；共享正文不另加顶部 padding，底部 6 点。不要恢复所有页面统一预留 44 点而造成首页重复留白。
- 历史页动作与周范围同一行，下方直接接记录；不要添加整块筛选卡片、主列表汇总行、悬空大指标或独立图表开关。完整指标与图表放进“周统计”，同页承载前／后周和本周；未知训练量不显示占位数字。
- 记录视觉上只保留日期时间、次数和箭头，数字与小单位对齐同一基线；报告／反馈类型保留在无障碍提示中，合并无障碍元素后仍须保留按钮角色。
- 首页间距见 [首页与历史收紧](docs/watch-compact-home-history-20261104.md)，历史页迭代见 [历史页进一步整理](docs/watch-history-ledger-20261104.md)，最新布局及验证见 [历史页去卡片](docs/watch-history-plain-20261104.md)。最终代码已纳入 57；中间卡片方案未发布，不将旧轮次截图用作最新页面。

## Watch 其他页面统一：2026-11-04（TestFlight 57）

- 设置采用紧凑分区与平直重量行；只有修改后显示固定底部保存。移除行背景时必须保留 `.contentShape(Rectangle())`，不能让行中空白失去点击响应。健康同步视觉标签简短，完整名称保留给无障碍。
- 重量使用原生输入框与独立单位，避免叠加两层背景或将单位覆盖在输入内容上。帮助为主题列表，进入后才显示对应说明；反馈的数据头与历史使用同一边线。
- 训练的组号／累计数归入动作／重量，主计数 40 点；暂停、结束、更多在固定底部真实占位。不得恢复单独撑高一行的“更多”按钮。必要错误继续显示，英文错误文本保持简短、能滚动完整读取。
- 恢复页使用正常字号的次数单位，继续为主操作，保存与放弃并排；共享按钮不能忽略破坏性角色的红色。刚保存与历史报告标题、返回动作分别处理。
- 实际页面、已执行流程及未完成的真机／历史整场报告验证边界见 [Watch 整体复查](docs/watch-ui-review-20261104.md)。已随双端 1.1.8 (57) 发布，不将原生模拟器操作当作佩戴、传感器精度或健康指标验收。

## 新增三个动作：2026-11-04（TestFlight 55）

- 新增肩上推举 `overhead_press`、杠铃划船 `barbell_row`、哑铃弯举 `bicep_curl`，共用既有线条图标、中英文本地化、手表首页／整场切换／Siri 和手机记录、补记、筛选、趋势及备份格式。
- 自动计数使用独立的 `UpperBodyDetector`，不借用卧推／深蹲／硬拉检测器；只有合格完成事件进入统一 `RepCompletionFeedback`，停止后的核对保持静默。算法和反馈版本共用 `ExerciseType.countingAlgorithmVersion`／`completionFeedbackVersion`，正常训练与 Debug 采样一致。
- 三个动作目前只有初版物理规则，尚无可用的对应实测标注来校准精度。旧文档中的两份弯举记录已不在当前云端；本轮读取的现存 9 条记录仅有卧推和深蹲。其他动作回放只能验证坐标／时间保护，不能当作这三个动作的准确率。
- 手机同步请求新增 `supported_exercises`；未声明时仅发送旧三项。新动作及含新动作的整场报告保留在 Watch，待兼容手机接收，不混入旧批次阻塞其他历史；接收后仍按原有落盘与回执顺序处理。
- `FlyingrtxFast` 已补齐推举／划船反馈输入和看板标签，提交 `bc294b567` 已上线；公网 API、运行容器源码摘要、前端版本凭证与实际页面资源已核验。推举／划船没有云端计数模型，返回待核对与空次数，不能用通用旧模型冒充已验证结果。
- 开发采样支持六种动作，但仍仅 `DEBUG` 显示；正式版继续隐藏采集页面和远程入口。详细实现、原生验证与精度边界见 [新增动作](docs/additional-exercises-20261104.md)。用户随后授权提交、推送、TestFlight 与相关后台上线；已纳入双端 1.1.8 (55)。

## 手表同步状态跳变：2026-11-04（TestFlight 56）

- 55 版收到记录列表图标与同步页“等待／接收”反复切换的报告。接收超时改为唯一可取消的空闲计时任务，每次进展续期；实时消息不可达不覆盖后台接收状态，自动请求在 20 秒窗口合并，手动重试保留。右上角入口固定手表图标，详情不因其他时间轴 revision 反复强制请求。
- 真实时钟／Task 针对性验证和两个 iPhone 工程及配套 Watch Release 编译通过；设备不可连接，未完成用户真机同步复验。已随 1.1.8 (56) 发布；55 版不包含此修复。详见 [同步状态修复](docs/watch-sync-flicker-20261104.md)。

## 保存时采样中断误报：2026-11-09（TestFlight 58）

- MotionDetector 同步／异步停止均在入口捕获单调时钟，最终卧推分析使用这个截止时间；不得在文件队列等待后用执行分析的当前时间判断尾部断流。
- CoreMotion 两路回调绑定启动代次，停止阶段的关闭错误不得污染检测器；真实运动中错误与实际采样缺口继续保留。共享代次与停止标记通过锁读写，诊断分类使用 `MotionLifecycle`。
- 11 条真实卧推录制回放与配套 Release 构建通过；6 条迟收尾误报、2 条真实内部缺口及停止前尾部缺口分别验证。未取得用户本次 Watch 日志，不把检测器回放当作 CoreMotion 实机验收。见 [停止边界修复](docs/sampling-stop-fix-20261109.md)。已随双端 1.1.8 (58) 发布，57 版不包含本修复。

## 最新 TestFlight：2026-11-12（61）

- iPhone 与 Watch：1.1.8 (61)，发布源码 `9213147c137de567712bbc3db44b1a3c0794cb95` 已推送。记录、详情、整场报告、趋势、概览和 CSV 统一显示“训练时长”，采用动作时长数据；移除总用时选项，缺失值保持未知，手动补记沿用用户填写的时长。
- Delivery UUID / ASC Build ID：`cced0ed3-eadf-4ddd-8af6-1fa2f4f26f05`。Apple `BUILD-STATUS: VALID`、`INTERNAL_ONLY`、`IN_BETA_TESTING`；内部组 `flyingrtx` 与中英文说明已回读确认。
- 82 条真实历史及 19 份采样的数据口径、CSV、持久化和兼容回归通过；两个 iPhone 工程与配套 Watch Release 构建通过。双端签名归档／导出、严格签名、版本／配套关系、HealthKit／Watch Siri 权限和实际资源本地化核验通过。
- 519 个提交文件生成源码快照，244 个应用文件与验证副本对应，其中 3 个仅为 Git 的 CRLF/LF 规范化。IPA SHA-256：`f8dfdf8cb616baa33ea5a4dd6264c90f7fa0e8ddb87ffbe753022dbf0c8fec0a`。本轮没有新增原生 UI 执行或真机界面复验。
- 产物：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/TestFlight-1.1.8-61/`；详见 [61 版发布记录](docs/testflight-1.1.8-61.md)。

## 历史 TestFlight：2026-11-11（60）

- iPhone 与 Watch：1.1.8 (60)，发布源码 `95159c44edf0f6d4a735ac389720bc147ea87bc5` 已推送。移除结束训练后重复读取整段心率的查询，沿用实时采集点与 HealthKit 统计；采样收尾移出共享文件队列，保留停止时刻与代次保护。新增 `WorkoutSave` 分步耗时诊断。
- Delivery UUID / ASC Build ID：`13700bc9-4945-4f91-89c4-962a6befad4d`。Apple `BUILD-STATUS: VALID`、`INTERNAL_ONLY`、`IN_BETA_TESTING`；内部组 `flyingrtx` 和中英文说明已回读确认。
- 3 项隔离原生检查通过，包含文件队列阻塞回归及自动结束流程；配套 Release 构建、双端签名归档／导出与严格签名、权限、版本核验通过，独立 iPhone 60 Release 构建通过。518 个提交文件生成源码快照，244 个应用文件与验证副本对应，其中 3 个仅为 Git 的 CRLF/LF 规范化。
- IPA SHA-256：`86124ba5b818a17057ec6420b1617f426b8682a868856efefe49700150d51faf`。真表连接读取仍超时，总保存耗时与实际健康写入待复验。用户安装与训练数据保留。
- 产物：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/TestFlight-1.1.8-60/`；详见 [60 版发布记录](docs/testflight-1.1.8-60.md)。

## 历史 TestFlight：2026-11-11（59）

- iPhone 与 Watch：1.1.8 (59)，发布源码 `e1f2377aeb217cb099c707f7ee5ba78daa928168` 已推送。整场训练 5 分钟无新次数提醒、10 分钟自动保存，继续训练重新计时，手动暂停不触发；保留已完成组、裁掉末段空等及对应尾部采样，空训练不入历史。
- Delivery UUID / ASC Build ID：`650f59f8-d7d2-4310-9903-8aa918413da0`。Apple `BUILD-STATUS: VALID`、`INTERNAL_ONLY`、`IN_BETA_TESTING`；内部组 `flyingrtx` 与中英文测试说明已回读确认。
- 两项隔离原生生命周期测试通过，配套双端归档／导出、严格签名、版本／配套关系、HealthKit 与 Watch Siri 权限核验通过，独立 iPhone 59 Release 构建通过。516 个提交文件生成快照；244 个应用文件与验证源码对应，其中 3 个仅为 Git 的 CRLF/LF 规范化。
- IPA SHA-256：`ed060d9398cf800a5cba8c1d69af2a3a65d2845e30554e68873a0be0f75cb774`。实际佩戴、熄屏超时与 HealthKit 写入仍待真表确认；此次未覆盖用户正式安装。
- 产物：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/TestFlight-1.1.8-59/`；详见 [59 版发布记录](docs/testflight-1.1.8-59.md)。

## 历史 TestFlight：2026-11-09（58）

- iPhone 与 Watch：1.1.8 (58)，发布源码 `5cf428004f3ca45589050280453010890bec5388` 已推送 `codex/gymcount-cleanup-20261011`。修复正常停止后收尾等待被误算成断流，以及关闭／旧代次回调污染当前采样状态的问题；动作识别门限、存储与同步协议及后台不变。
- Delivery UUID / ASC Build ID：`25c24341-3504-442c-90e8-434d6819b921`。Apple `BUILD-STATUS: VALID`、`INTERNAL_ONLY`、`IN_BETA_TESTING`；内部组 `flyingrtx` 和中英文说明均已回读确认。
- 514 个提交文件生成发布快照，244 个应用文件与刚完成的真实回放和配套构建副本逐文件一致。双端签名归档／导出、严格签名、版本／配套关系、HealthKit 与 Watch Siri 权限通过；实际手表包存在 `MotionLifecycle` 诊断代码，开发者采集 UI 与相机权限继续排除。独立 iPhone 58 Release 构建通过。
- IPA SHA-256：`017df7d0dabb13ac0e0f471dcedc1a077235b3df84aba88e6c22f26f1b3ba6e3`。沿用 11 条真实录制回放与实际等待验证结果；未做 CoreMotion 实机停止回调验收，没有注入运动信号、上传反馈或操作用户正式安装。3 个临时桌面发布任务已移除，正式商店不作更新。
- 产物：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/TestFlight-1.1.8-58/`；详见 [58 版发布记录](docs/testflight-1.1.8-58.md)。

## 历史 TestFlight：2026-11-04（57）

- iPhone 与 Watch：1.1.8 (57)，发布源码 `eef466cc52084808603a61d5e3104439f2e5a2f2` 已推送 `codex/gymcount-cleanup-20261011`。包含 iOS 六种动作圆环配色，以及 Watch 首页／历史／设置／帮助、重量输入、训练／恢复／报告和反馈布局整理；没有改计数算法、存储格式、通信协议或后台。
- Delivery UUID / ASC Build ID：`06ea38b8-f862-4190-8403-a754629787cc`。Apple `BUILD-STATUS: VALID`、`INTERNAL_ONLY`、`IN_BETA_TESTING`；内部组 `flyingrtx` 与中英文测试说明均已写入并回读确认。
- 511 个提交文件生成发布快照并核验，244 个应用文件与最终验证一致（3 个既有文件仅有 Git 换行归一化）。57 版独立 iPhone Release 构建、配套双端签名归档、导出、严格签名、版本／配套关系、HealthKit 与 Watch Siri 权限通过；正式包继续排除采集 UI 与相机权限，56 版同步修复保留。
- IPA SHA-256：`90891b351d396ea6aa64797fb6b320a119b852e8973d4f159a0eecbb4145f40b`。沿用同源码的 8 类原生流程通过证据，保留早期失败记录及历史整场报告、真实上传与真机验证边界；82 条原始历史及预览资料保留，未操作用户正式安装。3 个临时桌面发布任务已移除，正式商店不作更新。
- 产物：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/TestFlight-1.1.8-57/`；详见 [57 版发布记录](docs/testflight-1.1.8-57.md)。

## 历史 TestFlight：2026-11-04（56）

- iPhone 与 Watch：1.1.8 (56)，发布源码 `110f9e20320297b372ab96cfa687f133d2f6bcf6` 已推送 `codex/gymcount-cleanup-20261011`。同步状态跳变热修复，Watch 业务源码与 55 相同，仅随包更新构建号；本次不需要后台变更。
- Delivery UUID / ASC Build ID：`04590ee6-ffc5-472e-9859-e846fccc1996`。Apple `BUILD-STATUS: VALID`、`INTERNAL_ONLY`、`IN_BETA_TESTING`；内部组 `flyingrtx` 与中英文测试说明均已写入并回读确认。
- 506 个提交源文件摘要核验，244 个应用文件与刚完成的针对性验证副本一致；双端签名归档、导出、严格签名、版本／配套关系、HealthKit 与 Watch Siri 权限通过。实际 IPA 中存在同步修复模块，开发者采集 UI 与相机权限继续排除。
- IPA SHA-256：`2949df5e7b3e674aa393580ac1f4e188894c8abb4030dd6da49b8e0f7fe74b79`。手机与手表当前不可连接，未完成本次真机同步复验；没有把时钟／Task 检查描述为真实双端传输。用户安装与训练数据保留，3 个临时发布任务已移除，正式商店保持 1.1.7。
- 产物：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/TestFlight-1.1.8-56/`；详见 [56 版发布记录](docs/testflight-1.1.8-56.md)。

## 历史 TestFlight：2026-11-04（55）

- iPhone 与 Watch：1.1.8 (55)，发布源码 `a55cfa333326be1789dd86e3bb2f07bcaa747e71` 已推送 `codex/gymcount-cleanup-20261011`；后台／看板源码 `bc294b5679d9733d5f2fd88942c2f2ea5f9bb0e4` 已推送并上线。
- Delivery UUID / ASC Build ID：`47b707b7-ef0b-4066-b4ad-a480eb39e14e`。Apple `BUILD-STATUS: VALID`、`INTERNAL_ONLY`、`IN_BETA_TESTING`；内部组 `flyingrtx` 与中英文测试说明已写入并回读确认。
- 502 个提交源文件摘要核验，243 个应用文件与最终原生验证一致；双端签名归档、导出、严格签名、版本／配套关系、HealthKit 与 Watch Siri 权限通过。Duo 中文、SE 英文最大字号及 41mm Watch 中英文最终 3 项原生检查通过，82 条历史回归保持。新动作尚无对应实测标注，未新增真机精度、触感／声音或双端物理传输验收。
- IPA SHA-256：`41103df1f3e5a51574a9f059e40faf63c33bf0d0b30d328fba86cbc8dd318ecd`。正式商店保持 1.1.7，3 个临时发布任务已移除，用户安装与资料保留。
- 产物：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/TestFlight-1.1.8-55/`；详见 [55 版发布记录](docs/testflight-1.1.8-55.md)。

## 历史 TestFlight：2026-11-03（54）

- iPhone 与 Watch：1.1.8 (54)。代码提交 `82f02b30bcf84e4b739338399b395d0fedaef047`，已推送 `codex/gymcount-cleanup-20261011`；集中提交此前积累的 136 个源码、测试与文档文件。
- Delivery UUID / ASC Build ID：`7eeaccd6-e3dc-47a3-9095-34b7e9a15e26`。Apple `BUILD-STATUS: VALID`、`INTERNAL_ONLY`、`IN_BETA_TESTING`；内部组 `flyingrtx` 已确认包含本构建，中英文测试说明已写入并回读。
- 包含 Duo 原生分栏／折叠布局、记录／趋势／补记与备份恢复完善、Watch 页面统一和实时完成反馈修复；Release 移除开发者采集页面、远程采集入口与相机权限，正常记录、报告及传感器同步保留。
- 从提交生成 497 个文件的发布快照并核验；242 个应用源码／资源与本次最终原生验收副本一致。双端签名归档、导出、严格签名、版本／配套关系、HealthKit 与 Watch Siri 权限通过；沿用同源码的独立 iPhone Release 构建及真实历史和原生检查结果。
- IPA SHA-256：`54bac783d72c747342caeaaac0f42bf07dd0cdac2cc595bd1c95ccfe202a4c3a`。82 条原始历史保持；未新增真机佩戴、触感／声音、HealthKit、Siri 口语或双端物理传输验收。正式商店 1.1.7 未改，三个临时发布任务已移除。
- 完整产物：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/TestFlight-1.1.8-54/`；详见 [54 版发布记录](docs/testflight-1.1.8-54.md)。

## iPhone Duo 布局：2026-11-03（TestFlight 54）

- 三入口采用原生 TabView；不要恢复叠加隐藏的系统 TabView 或固定底栏，Duo 的侧边导航和保留区域由系统布局。
- 记录使用 NavigationSplitView，窄屏进入详情，宽屏并排；详情按记录 UUID 管理身份，折叠不清空当前选择。趋势按可用宽度与字体大小调整列数，表单保持阅读宽度，焦点输入随窗口尺寸变化重新定位。
- Xcode 27.1 与用户已有 Duo 模拟器用于实际折叠／展开检查；不再用 iPad 预览充当 Duo 验收。复用现有小屏 iPhone，验证副本用独立 Bundle ID 与真实历史隔离存储。实现、截图、构建和边界见 [Duo 适配](docs/ios-duo-20261103.md)。

## 卧推实时计数与反馈：2026-10-31（TestFlight 54）

- 随后统一三种动作的 `DetectedRepetition` 事件、实时性／去重检查及 `RepCompletionFeedback` 组件，完成触觉调用 5 处收为 1 处；检测器仅输出完成事件，补算传非实时标记，不直接播放反馈。普通／整场训练和采集共用该入口；后续动作不要另加检测器内的振动或独立的计数反馈回调。六条真实卧推回放及配套 iPhone/Watch Release 构建通过，已纳入 TestFlight 54，未新增佩戴验收；见 [反馈组件整理](docs/rep-feedback-refactor-20261031.md)。

- 实时加 1 和系统完成反馈改为消费同一个新鲜顶部完成周期；V8 前缀仅作诊断，结束／暂停／切换时静默核准。准备动作、旧会话和迟到事件不因数字增加而补振动。
- 普通与整场训练、采集保持一致；完成周期保留起点／转折／完成时间，单次动作遇到 V8 无法确认时不误清成 0。内存次数和触觉请求先于草稿写入，避免存储延迟挪动反馈时机；音效遵循 watchOS 静音设置，不加语音报数。
- 六条真实录制直接回放生产检测器，五组 25 个顶部事件及全部 V8 最终结果保持；结束与重置不追加完成事件，有效首周期保留检查通过。未改顶部门限、最终 V8、深蹲／硬拉或云端算法。配套手机／Watch 与独立手机 Release 构建通过，尚未新增真实佩戴触感／声音验收。
- 已提交 Git 并纳入 1.1.8 (54)，此前上传的 1.1.7 (53) 不包含此修复。详见 [完成反馈同步修复](docs/bench-completion-sync-20261031.md)。

## 分组入口与时间轴：2026-10-29（已纳入 TestFlight 51）

- Watch“下一组”收进更多菜单并改名“手动分组”；组号标识仅放组号文本，避免父容器覆盖操作按钮。watchOS 原生菜单会隐藏零次时禁用的分组动作。
- iPhone 整场与传感器时间轴共用淡金区间、首末完成点虚线及组名，使用手机修正后的有效分组。单次组不造时长，缺可靠采样起点不伪造对齐；背景几何不回写状态。
- 双 iPhone 工程与 Watch 构建、4 项实际原生检查通过，82 条隔离 Watch 历史保持；没有修改计数算法、自动分组或同步格式；已纳入 TestFlight 1.1.6 (51)。详情见 [分组显示](docs/set-regions-20261029.md)。

## 整场训练与报告：2026-10-28（已纳入 TestFlight 50）

- 手表首页与 Siri 开始整场训练；同一会话支持多个动作／组、改重量、暂停／继续、下一组、结束报告。50 版最初只提醒，现行逻辑为 5 分钟无新次数提醒、10 分钟自动结束。暂停时不触发，继续训练重新计时。自动结束保存已有组并截去末段空等，空训练不入历史。不因跨 24 小时丢弃草稿或拒绝真实会话保存。
- 逐次完成点与已知周期起点组成报告；实际动作时长、组间间隔、显式暂停分别计算。硬拉／手动次数没有可靠起点时不推测时长或自动分组。手机可拆分／合并同动作组，保留不可变原始来源。
- 新整场健康数据来自真实 HKLiveWorkoutBuilder；未知心率／活动能量不补零、不用固定公式。健康失败不能冒充训练已保存，本地持久化成功后才给保存结果；旧历史导出不得重复生成整场健康记录。
- 快照 v4、训练备份 v4（兼容 v1–v3）；原 v3 快照先保留副本。报告采用有接收端能力与身份校验的文件传输，手机落盘后回执；旧手机不接收降级多动作汇总，报告留在手表。分段原始采样独立保存并随训练删除／放弃清理。
- 三个工程 Release 无签名构建、6 项实际 Intent、手表原生操作与恢复保存、大小屏手机中英文原生分组操作通过。82 条真实历史保持一致，16 份真实采集回放中 12 份／62 个既有检测动作保留；不把回放或模拟器当成真实多组计数、Siri 口语、HealthKit 或双端传输验收。
- 已随 TestFlight 1.1.6 (50) 发布，未提交 Git 或推送；实现和实际截图见 [整场训练与报告](docs/whole-workout-20261028.md)，发布凭证见 [50 版发布记录](docs/testflight-1.1.6-50.md)。

- 报告布局随后精修：摘要同列、时间轴与组列表合并、重复名称精简，恢复分组收进菜单；两工程构建及大小屏 6 项原生页面检查通过。详见 [报告布局精修](docs/report-layout-20261028.md)。
- 整场报告传感器随后补齐：按段传输原始采样，手机落盘后回执，接收端隔离收件箱支持父报告迟到重试；备份 v4 包含分段采样，修正／分组合并不改原始来源。详情直接显示传感器曲线与逐次打点，未知采样起点使用段内时间；详细验证与真机边界见 [报告传感器](docs/report-sensors-20261028.md)。图表布局不得通过 PreferenceKey 回写父状态；异步采样加载 task 要绑定稳定容器，避免条件 Group 切换导致重复加载。

## Watch Siri：2026-10-28（已纳入 TestFlight 50）

- 仅做手表本机 Siri。复用 `StartWorkoutIntent` 与现有动作实体，支持“开始健身计数”并询问动作，以及“用健身计数开始卧推”。手机保持记录端，不添加远程启动。
- 可选重量不再默认 0，未指定动作不再默认深蹲。重复启动、未恢复训练、保存中、采集未完成和草稿保存失败均保留当前状态并报错；实际建立会话后才回应成功。
- 快捷指令短语必须保留应用名占位符；中英文分别放入 `AppShortcuts.strings`。使用 Info.plist 的 `INAlternativeAppNames` 和本地化的 `InfoPlist.strings` 登记“健身计数”别名，不使用无应用名的裸命令或伪造 Siri 识别结果。
- Watch 及配套构建、提取元数据／本地化和 4 项实际 Intent 原生检查通过；没有伪造动作、次数或训练历史。未签名原生检查中的 HealthKit 提示不代表真机授权验收。真人对手表说话的识别及唤起仍待新版真表实测。
- 验证边界及路径见 [手表 Siri](docs/watch-siri-20261028.md)。已纳入 TestFlight 50；Siri 功能本身不改计数算法或同步协议。

## 连续训练与晚间提醒：2026-10-27（已纳入 TestFlight 50）

- 手机记录页与 Watch 首页显示连续训练天数；按本地自然日、已保存正次数计算，同日去重，允许从昨天延续到今天，未来／零次不计。趋势连续值复用同一计算。
- 手机默认 20:00 未训练提醒，设置可关闭，首次请求通知权限。持久化成功后的训练日期回调负责取消当天提醒与续排，后台同步也走同一入口；不能只放在 SwiftUI 页面观察中。Watch 独立开关默认关闭、时间默认 20:00，保留用户明确配置。
- 使用 60 个自然日的系统单次通知窗口；开启、训练变化、后台接收、应用激活、跨日及时区变化续排。不使用无法跳过今天的每日重复请求，不把尚未同步或保存的训练算作已完成。长期完全不运行超出窗口需要打开应用刷新。
- 82 条真实历史、3 个时区与 459 个日期场景及持久化回调回归通过；原生手机开启后系统队列 59 条 20:00 请求，关闭后 0 条。最终中英文手机和 Watch 页面检查通过；未将队列验证当成真机晚间送达验证。
- 详情与验证边界见 [连续训练与提醒](docs/training-streak-20261027.md)。已纳入 TestFlight 50；连续训练功能本身未改变算法、备份与同步格式。

## 历史 TestFlight：2026-10-29（51）

- 版本：1.1.6 (51)，iPhone 与 Watch 一致；478 个发布源文件摘要核验，243 个应用源码／资源／权限文件与已验收副本一致。
- Delivery UUID / ASC Build ID：`8702bb6b-ebd2-4e03-a7ec-4d3bc2afb025`。Apple `BUILD-STATUS: VALID` / `INTERNAL_ONLY` / `IN_BETA_TESTING`；内部组 `flyingrtx` 包含本构建，中英文测试说明已写入并回读。
- Watch 手动分组收进更多菜单；iPhone 整场与传感器时间轴增加淡金分组区域、首末完成点虚线及组名，使用手机调整后的有效分组。未改计数算法、自动分组或同步格式。
- Aqua 双端签名归档、导出、版本／严格签名／HealthKit／配套关系和 Watch Siri 权限／Intent 元数据通过。沿用相同应用源码的三个工程构建及 4 项原生页面检查，82 条真实隔离历史保持；无新增编译警告。
- IPA SHA-256：`d50c3c5abb05a20ae6c52b68956893186ed64a27ec6f6c90312643fe63f29213`。正式商店 1.1.5 及构建关联未改，未提交 Git 或推送，未覆盖用户安装和资料。没有新增真机佩戴、震动、健康数据或双端传输验收。
- 完整产物：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/TestFlight-1.1.6-51/`；详见 [发布记录](docs/testflight-1.1.6-51.md)。

## 历史 TestFlight：2026-10-28（50）

- 版本：1.1.6 (50)，iPhone 与 Watch 一致。原计划 1.1.5 (50) 被 Apple 以 90062 拒收：1.1.5 已获批，需要更高版本号；因此递增到 1.1.6，应用源码不变，拒收凭证保留。
- Delivery UUID / ASC Build ID：`a8ae6848-98fc-4208-8d90-134d6f9a75e9`。Apple `BUILD-STATUS: VALID` / `INTERNAL_ONLY` / `IN_BETA_TESTING`；内部组 `flyingrtx` 包含本构建，中英文测试说明写入并回读。
- 包含整场训练与报告、逐次时间轴和分段传感器同步／备份、报告布局、手表 Siri、连续训练日数与晚间提醒。247 个应用源码／资源文件与最近验证副本一致，476 个发布源文件摘要核验；未提交 Git、未推送。
- Aqua 签名归档与导出、双端版本／严格签名／HealthKit／配套关系通过，Watch Siri 实际签名及 profile 权限与 Intent 元数据核验通过。沿用相同应用源码通过的双工程构建、5 项原生 UI 和真实采样存储／报告回归；不把构建与回放描述为真表 Siri、健康采集、佩戴计数或双端真实传输验收。
- IPA SHA-256：`95de34aef448459988ee30257ea55d7a3b36e3a6fb79279419720c605b9f6aa0`。仅发内部 TestFlight；正式商店 1.1.5 及构建关联保持原状，用户现有安装与记录保留。
- 完整产物：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/TestFlight-1.1.6-50/`；详见 [发布记录](docs/testflight-1.1.6-50.md)。

## 历史 TestFlight：2026-10-27（49）

- 版本：1.1.5 (49)，iPhone 与 Watch 一致。当前授权工作区快照归档，451 个文件 SHA-256 核验；232 个应用源码／资源与本轮性能修复最终原生验收副本一致，未声称工作区已提交。
- Delivery UUID / ASC Build ID：`0d169403-7242-4fe1-ad36-5a72b0cabcb5`。苹果 `BUILD-STATUS: VALID` / `INTERNAL_ONLY` / `IN_BETA_TESTING`；内部组 `flyingrtx` 已确认包含本构建，中英文说明写入并回读。
- 优化趋势筛选和图表切换、时间轴选点；双端重文件操作后台顺序处理、备份逐条写出、同步收件保留及确认顺序；减少 Watch 重复统计、扫描与检查点写入，移除旧调试通道与页面。卧推／深蹲／硬拉算法和分析文件与性能修改前字节一致。
- 配套签名归档、导出、双端版本／签名／HealthKit／配套关系和独立 iPhone Release 构建通过。源码一致后沿用 82 条真实历史、16 份时间轴回归及 5 项 iOS、1 项 Watch 独立原生流程通过结果；首轮测试操作失败及修正后通过的结果均保留，不将全部历史结果包标成通过。详见 [性能修复](docs/performance-repair-20261027.md)。
- 未新增真机同步、长期训练耗电／峰值内存、佩戴触感和人工 VoiceOver 验收。保留用户安装与资料，三个临时 Aqua 任务及约 0.51 GiB 本轮空闲缓存已清理；既有编译提示保留。仅发 TestFlight，正式商店关联仍为构建 45。
- IPA SHA-256：`e5ab22e8ac420e626a9e2ae087d45f8d1ac9e5d15efd103163abc5acf67a3fa0`。
- 完整产物：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/TestFlight-1.1.5-49/`；隔离发布源码：`/private/tmp/GymCount-TestFlight-1.1.5-49-20261027/source`。详见 [发布记录](docs/testflight-1.1.5-49.md)。

## 历史 TestFlight：2026-10-27（48）

- 版本：1.1.5 (48)，iPhone 与配套 Watch 一致。授权工作区快照归档，447 个文件 SHA-256 核验；233 个应用源码／资源与本轮原生验收副本一致。
- Delivery UUID / ASC Build ID：`260dcfd8-138e-48f1-b8c8-72cfe24b64af`。苹果 `BUILD-STATUS: VALID` / `INTERNAL_ONLY` / `IN_BETA_TESTING`；内部组 `flyingrtx` 已确认包含本构建，中英文测试说明已写入并回读。
- iOS 落地统一白金视觉规范：三页标题、同级字号、16 点正文边线、指标数字／单位、按钮层级与按压反馈、分区及局部空状态共享。设置改为紧凑列表；详情、补记、时间轴、采集和上传统一样式。规范见 [iOS 视觉规范](docs/ios-design-system.md)。Watch 内容与 47 版一致，仅配套构建号更新。
- 配套双端 Aqua 签名归档、导出、版本／签名／HealthKit／配套关系核验通过；独立 iPhone Release 构建通过。源码比对后沿用本轮大屏 3 项、小屏 2 项原生通过结果，另有静态截图补截用例通过，0 失败、0 运行时告警；覆盖中英文、大小屏、最大辅助字号、导航、补记键盘、文件面板取消、真实时间轴及趋势末尾记录点击。未重复制造训练数据。
- 未新增真机同步、实际上传、佩戴触感及人工 VoiceOver 验收；未覆盖用户安装与记录，没有新建设备。既有 HealthKit 弃用、采集闭包引用和 AppIntents 编译提示保留。三个临时 Aqua 任务及约 0.51 GiB 本轮空闲构建缓存已清理，归档与证据保留。
- IPA SHA-256：`927ab40f01c7a2d3dddf8624c39f9f91498aab9adf988c70b25477cd46005d62`。
- 完整产物：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/TestFlight-1.1.5-48/`；隔离发布源码：`/private/tmp/GymCount-TestFlight-1.1.5-48-20261027/source`。详见 [发布记录](docs/testflight-1.1.5-48.md)。仅发布 TestFlight；正式商店仍关联构建 45，未替换或重新提交。

## 历史 TestFlight：2026-10-27（47）

- 版本：1.1.5 (47)，iPhone 与 Watch 一致。当前授权工作区快照归档，441 个文件 SHA-256 核验；233 个应用源码／资源与原生验收副本一致。
- Delivery UUID / ASC Build ID：`96808889-a99e-44ca-b0ab-8660ec6fd9ea`。苹果 `BUILD-STATUS: VALID` / `INTERNAL_ONLY` / `IN_BETA_TESTING`，内部组 `flyingrtx` 已确认包含本构建。
- 记录、趋势及概览使用已知动作时长；整段计时只在详情或主动选择总用时时显示。Watch 深蹲累加已识别动作区间，准备与区间外空闲不计入；旧采样只有在次数及完成节点匹配时补算。缺少依据留空，手机次数修正不沿用不匹配的动作时长。未改计数阈值和完成震动条件。
- 包含详情采样状态／定向补传、趋势原生横滑、底栏高度及汇总最后一行点击修复。原生检查另发现切换动作时 Charts 环图 NaN 崩溃，已关闭扇区插值并重建变化的数据集合，零总量显示底环。
- 配套双端签名归档、导出及独立 iPhone Release 构建通过；真实 82 条历史统计、16 份传感器时间轴及真实卧推存储回归通过。大屏 4 项、小屏 1 项原生检查通过，0 失败、无运行时告警。旧时间轴与当前完成节点不一致时没有强行补入时长，不将重放当成独立视频精度验证。
- 没有新建模拟器或覆盖用户安装／资料；真机当前不可连接，未新增佩戴、触感与 WatchConnectivity 实测。三个临时 Aqua 任务已移除，本轮空闲构建缓存约 1.03 GB 已清理。既有编译警告保留。
- IPA SHA-256：`8ddede7eb3d88a3540994980d3a299424179cd49bab7126d37fe24b093a50849`。
- 完整产物：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/TestFlight-1.1.5-47/`；隔离发布源码：`/private/tmp/GymCount-TestFlight-1.1.5-47-20261027/source`。详见 [发布记录](docs/testflight-1.1.5-47.md) 与 [动作时长修复](docs/action-duration-20261027.md)。仅发布 TestFlight，正式审核构建未替换。

## 历史 TestFlight：2026-10-27（46）

- 版本：1.1.5 (46)，iPhone 与 Watch 一致。发布当前已授权工作区快照，438 个文件 SHA-256 已核验；未把未提交工作区标成干净 Git 提交。
- Delivery UUID / ASC Build ID：`6e7e6ef9-5d0f-48a0-9c12-c3f4fa522181`。苹果 `BUILD-STATUS: VALID` / `INTERNAL_ONLY` / `IN_BETA_TESTING`，内部测试组 `flyingrtx` 已确认包含本构建，中英文测试说明已写入。
- Watch 训练、历史、设置、采集及反馈统一白金配色；器械重量和体重共用可直接输入小数的原生页面，优化加减、顶部保存和返回，非法输入拒绝保存，取消保留原值。iOS 沿用 45 版记录、趋势、时间轴及备份功能；未改计数算法和同步协议。
- 双端 Aqua 签名归档、导出、版本／签名／HealthKit／配套关系核验通过。233 个应用源码与已有原生验收输入逐文件一致：iOS 沿用 45 版真实 82 条历史与原生检查，Watch 沿用中文 1 项、英文及设置 2 项、恢复回归 1 项通过的结果；本次未重复执行原生用例，未新增真机键盘、佩戴、同步及触感验收。既有编译警告保留。
- 仅发布 TestFlight；正式审核仍使用 45 版。用户安装和记录保留；本次没有新建模拟器，Watch 仍只保留 41mm 一台。临时 Aqua 发布任务及本次独立编译缓存已移除，归档、IPA、源码与证据保留。
- IPA SHA-256：`8b5a45f2e98d8e3e45702d6f39854b5e44bc136be68de08a57706d5c1ac1c2a0`。
- 完整产物：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/TestFlight-1.1.5-46/`；隔离发布源码：`/private/tmp/GymCount-TestFlight-1.1.5-46-20261027/source`。详见 [发布记录](docs/testflight-1.1.5-46.md)。

## 最新 App Store 提交：2026-10-31（53）

- 版本：1.1.7 (53)，iPhone 与 Watch 一致。本次为用户选定的白金精简海报更新；从已上线 52 的精确发布副本归档，480 文件核验仅两个工程的营销版本／构建号变化，应用代码、资源、权限、算法及数据格式一致。
- Delivery UUID / ASC Build ID：`ac85b5a8-1144-4600-8b31-afa3c3bb3b5d`。Apple `BUILD-STATUS: VALID`，ASC `VALID / APP_STORE_ELIGIBLE`；TestFlight `IN_BETA_TESTING`，`flyingrtx` 组及中英文说明已回读确认。
- App Store Version ID：`4ca2c31b-c641-4233-b5ec-b824d96de594`；Review Submission ID：`8457f91d-3b57-432e-bdd5-b6ec7fc65d80`。提交后版本及审核均 `WAITING_FOR_REVIEW`，`AFTER_APPROVAL`；当前公开 1.1.6，不把已提交海报描述为已公开展示。
- 中英文各 5 张精简 iPhone 海报全部 COMPLETE，顺序和源校验和回读通过；仅留主标题及原生界面，移除装饰英文、小字、编号与页脚。Watch 各 3 张截图沿用 52 并核对一致；审核说明披露营销示例、示意波形及生成摄影。
- Aqua 双端正式签名归档、导出、版本、配套关系、严格签名、HealthKit、Watch Siri/profile 与 Intent 资源检查通过。IPA SHA-256：`81d4776030b429a40b8bd8ca1a90c3a0e6fe2c478e96fff76f446fec02cba4e4`。两个工作区工程文件经摘要保护同步至上传版本；未提交 Git 或推送，未覆盖用户安装／资料。
- 产物：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/AppStore-1.1.7-53/`；详见 [商店海报更新](docs/appstore-1.1.7-53.md)。

## 历史 App Store / TestFlight 提交：2026-10-29（52）

- 版本：1.1.6 (52)，iPhone 与 Watch 一致；应用源码与 TestFlight 51 相同，两个有效工程 18 处构建号递增，正式导出允许 App Store 分发。
- Delivery UUID / ASC Build ID：`066492c3-4229-4793-b468-23e997d23220`。Apple `BUILD-STATUS: VALID` / `APP_STORE_ELIGIBLE`，内部 TestFlight 为 `IN_BETA_TESTING`，`flyingrtx` 组和中英文说明已回读确认。
- App Store Version ID：`35cb7342-bd78-4d54-a0e4-f9b48c988c59`；Review Submission ID：`5c26b8b6-2b6c-41b9-abc0-90dad8675eb1`。提交时版本 `WAITING_FOR_REVIEW`、审核 `WAITING_FOR_REVIEW`，`AFTER_APPROVAL`。本轮开始时实查 1.1.5 (45) 已公开；新版仍需等待审核，不把已上传素材描述为已公开展示。
- 手机与手表商店素材统一白金风格；简体中文、英语各 5 张手机图和 3 张 Watch 图，全部 COMPLETE，顺序与校验和回读通过。手机重点展示整场报告、分组传感器时间轴、记录、趋势和补记；Watch 展示首页、报告与重量输入。
- 中英文介绍、关键词、推广文案、更新说明、副标题和审核说明更新；保留名称、审核联系人和原有分级。真实原生界面使用隔离营销示例，含明确的示例传感器波形；没有使用私人历史，不作为算法精度或健康指标验收。
- 双端签名归档、正式导出、严格签名、配套关系、HealthKit 与 Watch Siri 权限通过；479 个发布源文件核验。原生营销流程手机 2 项、Watch 2 项通过，242 个手机及 129 个 Watch 源码／资源与生产一致；未新建模拟器、未覆盖真机安装。
- IPA SHA-256：`1a913031c1ad5a5676bc45f2f1565960a0375e82ecb0d1818cb06c4305520cf9`。没有新增真机佩戴、Siri 口语、健康数据或双端同步验收；未提交 Git 或推送。
- 产物：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/AppStore-1.1.6-52/`；详见 [商店更新记录](docs/appstore-1.1.6-52.md)。

## 历史 App Store 提交：2026-10-27（45）

- 版本：1.1.5 (45)，iPhone 与 Watch 一致。发布当前已授权工作区快照，434 个文件 SHA-256 已核验；未把未提交工作区标成干净 Git 提交。
- Delivery UUID / ASC Build ID：`01509c3d-5c7c-4734-89ae-a003611a6273`；苹果 `BUILD-STATUS: VALID` / `APP_STORE_ELIGIBLE`。内部 TestFlight 为 `IN_BETA_TESTING`，组 `flyingrtx` 包含本构建，中英文更新说明已核验。
- App Store Version ID：`54507e01-9396-4f32-a45a-57adc52a43dd`；Review Submission ID：`08c4ca4f-425e-42ed-b20b-b3ee88494b2e`。版本及审核状态均为 `WAITING_FOR_REVIEW`，发布方式 `AFTER_APPROVAL`；尚未宣称已公开上架，当前正式版仍为 1.1.4。
- 包含训练详情传感器时间轴与逐次动作打点、累计趋势概览、训练日历、动作环图与重量统计，以及此前记录／补记／同步恢复和 Watch 保存反馈改进。本轮未改计数算法。
- 更新简体中文与英语商店介绍、关键词、推广文案、更新说明及审核操作说明；英语商店名称 PowerReps。每种语言 5 张白金 iPhone 截图与 3 张当前 Watch 原生截图，全部 `COMPLETE`，顺序、来源及校验和已核验。公开截图只使用独立标注的营销示例，不含真实训练资料；示例不作为算法准确率证据。
- 首次提交发现苹果新要求的 `socialMedia` 分级字段为空；按本应用不含社交功能补为 false，保留其他分级答案，再提交成功。保留既有审核联系人。
- 双端 Aqua 签名归档、正式导出、版本／签名／HealthKit／配套关系核验通过。发布源码重新执行 82 条真实历史的手机持久化、趋势统计与 Watch 兼容检查，通过；实际营销原生流程手机 2 项、Watch 2 项通过，无运行时告警。109 个 iOS 与 124 个 Watch 源码／资源文件与原生展示副本一致。
- 尚未新增真机 WatchConnectivity、HealthKit、触感及人工 VoiceOver 验收。此前时间轴与中英文小屏／大字体原生证据按源码一致性沿用；营销截图不冒充真机验收。用户安装与资料保留，7 个临时 GUI 任务已移除，复用的 46mm 模拟器恢复关机。
- IPA SHA-256：`ce67e42133b6369773d584b9b0b02b9a9354d52ea3d742bc321489420425482b`。
- 完整产物：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/AppStore-1.1.5-45/`；隔离归档源码：`/private/tmp/GymCount-AppStore-1.1.5-45-20261027/source`。详见 [发布记录](docs/appstore-1.1.5-45.md)。

## 历史 TestFlight 发布：2026-10-27（44）

- 版本：1.1.5 (44)，iPhone 与 Watch 一致。发布当前已授权工作区快照，424 个文件 SHA-256 已核验；54 项原生验证输入与发布源码一致，构建号单独更新。
- Delivery UUID / ASC Build ID：`00963cfa-6478-47e2-a116-b0df7867374d`。苹果 `BUILD-STATUS: VALID` / `IN_BETA_TESTING` / `INTERNAL_ONLY`；已确认内部组 `flyingrtx` 包含本构建，中英文更新说明已写入。
- iPhone 精简记录与趋势布局、图表摘要及单位，完善补记、编辑、备份恢复、旧汇总同步修正保留与采集接收反馈。Watch 完善中断恢复、保存失败重试、历史及健康数据重复写入处理、提醒设置和反馈。计数算法未改。
- Aqua 签名归档与导出通过，双端版本、签名、HealthKit 及配套关系核验通过；既有三个工程构建及原生页面证据随包保存。发布源码重新执行 82 条真实历史的手机持久化和 Watch 兼容检查，通过迁移、重复导入、修正保留、删除不复现、重启、备份恢复及损坏数据保留检查。
- 尚未新增真机 WatchConnectivity、HealthKit 权限及部分重试、震动触感和人工 VoiceOver 验收；保留用户安装与记录。沿用 HealthKit 弃用、采集闭包引用及 AppIntents 编译警告。
- IPA SHA-256：`853eeaabc9635a8cf8207f9ceadf66d6a929c2599a6ccbe7ff9db5566e60b562`。
- 完整产物：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/TestFlight-1.1.5-44/`；隔离归档源码：`/private/tmp/GymCount-TestFlight-1.1.5-44-20261027/source`。

## 历史 TestFlight 发布：2026-10-26（43）

- 版本：1.1.5 (43)，iPhone 与 Watch 一致；发布源码提交 `54d364737e1117d12a565048df543064f7d3c1b1`，418 个源码文件 SHA-256 已核验。工作区与 Git 有 8 个仅 CRLF/LF 的字节差异，均已单独核对并保留清单。
- Delivery UUID / ASC Build ID：`df88b503-c690-46b2-8383-624f2dc0227a`。苹果 `BUILD-STATUS: VALID` / `IN_BETA_TESTING` / `INTERNAL_ONLY`；内部测试组 `flyingrtx` 已确认包含本构建，中英文更新说明已写入并回读。
- Watch 正式整合用户选择的保存提示 A / M2：深灰紧凑结果、小绿勾、独立 44pt 关闭及计数反馈入口、轻浮现及按压反馈；英文和大字号结果可完整换行。五秒退场随记录及视图生命周期取消，VoiceOver 时保留提示；减弱动态效果走短淡入淡出分支。原持久化成功后的单次震动保留，视图不叠加震动。
- iPhone 105 个源码／资源文件与 42 版一致，仅配套版本号更新。计数算法、记录模型、采样、同步和真实反馈上传流程未改；正式商店 1.1.4 状态及内容未修改。
- Aqua 会话签名归档、导出、双端 IPA 签名／版本／HealthKit／配套关系核验通过；独立 iPhone Release 模拟器构建通过。归档中 7 个相关源码与上一轮原生检查逐文件一致；修复后的中文 2 项、英文大字号 1 项原生检查通过，无运行时告警。保存实际截图、动效录像及区域比较证据，未把构建成功当成真机验收。
- 真机震动触感、系统减弱动态效果开关及人工 VoiceOver 尚待实测；没有覆盖用户手机或手表安装，没有代提交训练反馈。原有首页标题在极大字号下截短，已记录为区域外问题。沿用既有编译警告。
- IPA SHA-256：`bda9c6039e8eefe81e5af966a626750728e292c05020f98e9d08012aaac30b39`。
- 完整产物：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/TestFlight-1.1.5-43/`；隔离归档源码：`/private/tmp/GymCount-TestFlight-1.1.5-43-20261026/source`。本次三个临时发布 LaunchAgent 已移除。

## 历史 TestFlight 发布：2026-10-25（42）

- 版本：1.1.5 (42)，iPhone 与 Watch 一致；发布源码提交 `8f791fd114b55fd54ee1ee93b4ef8f68c4781b3c`，418 个源码文件 SHA-256 已核验。苹果端已确认 1.1.4 正式上架，因此启用 1.1.5 测试版本；未改正式商店提交。
- Delivery UUID / ASC Build ID：`9c9f21cd-e05e-4a6d-a342-275c39fc4c77`。苹果 `BUILD-STATUS: VALID` / `IN_BETA_TESTING` / `INTERNAL_ONLY`；已确认内部测试组 `flyingrtx` 包含本构建，中英文测试说明写入及回读一致。
- iPhone 包含近期记录、趋势和补记布局精修：日／周／月汇总、图表收起、查看偏好保留、首错定位、返回原筛选范围、清除图表选中、真实备份成功时间及 CSV 范围反馈。
- Watch 仅清理未使用的 UI 参数、状态、导入及透明装饰，并升版本号；计数算法、通信协议及训练快照格式不变。重复旧运动图片已清理，继续使用现有共享运动图标。
- 双端 Aqua 签名归档、导出及 IPA 签名／版本／HealthKit／配套关系核验通过。12 个相关源码文件与最近完成的原生验证摘要一致；三个工程构建通过，最近一轮大屏 7 项、小屏 3 项原生检查通过，无运行时告警，历史验证证据随发布保存。
- 独立真机预览安装及 82 条记录回读一致性通过；手机再次锁屏导致实际真机用例执行 0 项。真机交互、双端同步及人工 VoiceOver 仍待补验，用户现有正式安装及数据未覆盖。沿用既有 HealthKit、捕获引用及 AppIntents 编译警告。
- IPA SHA-256：`427411f3d2ff06ea315d042a27048ca9efa8b8f174393cb76bc62eee31ad98f3`。
- 完整产物：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/TestFlight-1.1.5-42/`；隔离归档源码：`/private/tmp/GymCount-TestFlight-1.1.5-42-20261025/source`。三个临时发布 LaunchAgent 已移除。

## 历史 TestFlight 发布：2026-10-24（41）

- 版本：1.1.4 (41)，iPhone 与 Watch 一致；发布源码提交 `cf279071f7c51104e23a8050ab5b187370331f80`，423 个源码文件 SHA-256 已核验。
- Delivery UUID / ASC Build ID：`aca1df33-7b5d-4dca-85d6-af9e342dc3ec`。苹果 `BUILD-STATUS: VALID` / `IN_BETA_TESTING` / `INTERNAL_ONLY`；已确认内部测试组 `flyingrtx` 包含本构建，中英文测试说明已更新。
- 记录页新增每日运动时长图表，随动作、日期范围和日历筛选；支持总用时／动作时长切换、点选与定位当天记录，缺失时长不计为零。保留顶部筛选与底栏修复。
- Watch 功能内容与 40 版一致，仅配套构建号升至 41；四个 Watch 源文件的字节差异仅为 CRLF/LF 换行，已核对。计数算法和通信协议未改，保留保存提示、震动与反馈上传。
- 双端 Aqua 签名归档、导出、IPA 签名／版本／HealthKit／配套关系核验通过。图表相关源码与已完成原生验证逐文件匹配；三个工程构建通过，原生大屏 4 项、小屏 1 项通过，0 失败、无运行时告警。82 条真实历史的时长汇总及既有存储验证通过。
- 真机图表触控、人工 VoiceOver、双端同步等仍待补验；用户设备安装和数据未覆盖。沿用既有 HealthKit 弃用、捕获引用和 AppIntents 编译警告。本次仅发布 TestFlight，正在审核的 1.1.4 (40) 未替换。
- IPA SHA-256：`8258799dd3ca0d272cab966e512dc6f93cd94d27909b65e43196393c4ea9ea11`。
- 完整产物：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/TestFlight-1.1.4-41/`；隔离归档源码：`/private/tmp/GymCount-TestFlight-1.1.4-41-20261024/source`。临时发布 LaunchAgent 已移除。

## 历史 TestFlight 发布：2026-10-24（38）

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

## 历史已上架 App Store 正式版：2026-10-24（40）

- 版本：1.1.4 (40)，iPhone 与 Watch 一致；归档源码提交 `b15e0e2f63cf9c0c593a6b1621a360b859370344`，422 个源码文件 SHA-256 已核验。
- Delivery UUID / ASC Build ID：`d293db2c-6be2-47d9-b164-4976bf49011c`；苹果 `BUILD-STATUS: VALID` / `APP_STORE_ELIGIBLE`。
- App Store Version ID：`2ad53749-061c-4fd6-8cc8-055aa01d57aa`；Review Submission ID：`f02d30e2-5696-4f32-9cd5-064d59841525`。提交时版本及审核状态均为 `WAITING_FOR_REVIEW`，发布方式 `AFTER_APPROVAL`；2026-10-25 通过 ASC 核实为 `READY_FOR_SALE`，当前公开版本为 1.1.4。
- 简体中文商店副标题改为“手表自动计数，手机专注记录”，更新介绍、关键词、推广文本及更新说明，覆盖记录、趋势、多组补记、草稿、备份恢复和 CSV 导出；保留既有审核联系人并更新操作说明。
- iPhone 替换为 4 张白金风格截图，分别展示记录、趋势、补记与备份设置；5 张 Watch 截图保留。所有图片均为 `COMPLETE`，iPhone 图片顺序与来源校验和通过。截图来自当前生产界面和独立、明确标注的展示示例，不含用户真实训练资料。补记 PNG 处理停滞后换用 JPEG，最终已处理完成，原图保留。
- 包含顶部筛选和右上角补记入口；修复退出补记后系统底栏重新出现、遮挡自定义导航的问题。39 版未提交审核，40 版包含此修复。没有新增 Watch 算法改动，沿用保存成功提示、震动及计数反馈。
- 双端 Aqua 签名归档、导出、IPA 签名/版本/HealthKit/配套关系验证通过；两个独立 iPhone 工程 Release 构建通过。真实82条历史的记录/趋势检查、多组录入/键盘/草稿/重启检查共2项通过，最终截图及取消编辑后导航检查1项通过，均无运行时布局告警。生产源码与归档、原生预览逐文件匹配；截图脚本后续只修正了预填重量的录入方式，未改动生产源码。
- IPA SHA-256：`54b0cd831f337baf3908fb23b3f8316f54ebcab0b6b63e2b68d2576a6f6b9168`。
- 完整产物：`/Users/xiangjunsheng/.codex/visualizations/2026/10/18/01a14cce-f633-7fe0-9fe0-30c6f25ab690/AppStore-1.1.4-40/`。用户真机安装和记录未覆盖；实际佩戴、双端同步、真机文件导出恢复及人工 VoiceOver 仍待补验。临时发布 LaunchAgent 已移除。

## 历史已上架 App Store 正式版：1.1.3（36）

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
