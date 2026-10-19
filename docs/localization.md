# 手机与手表名称、界面语言

手机原来把 `CFBundleDisplayName` 固定为 GymCount，没有打包名称翻译；手表已有中文“健身计数器”、英文 PowerReps，因此同一套应用的桌面名称不一致。

现在两个有效工程的默认名称都为 PowerReps，iPhone 与 Watch 的 `InfoPlist.strings` 均提供简体中文“健身计数器”和英文 PowerReps。手机相机、健康权限说明也提供两种语言。系统根据应用语言和偏好语言选择已打包的资源，未添加自定义语言开关。

训练、历史、设置、休息提醒、手表补传、开发者采集/录像核对的文案和无障碍标签使用原生本地化。保留中文原文作为翻译键；动态 String、条件按钮、状态与错误提示显式使用 `String(localized:)`，SwiftUI 数字插值使用编译器提取的格式键。手机记录日期不再强制 `zh_CN`。手表已有的翻译、原始记录、数据字段与计数算法保留。

验证使用编译器实际生成的 `.stringsdata` 和编译后 `.app` 内的资源。`scripts/verify-localization.swift` 检查两端语言匹配、桌面名称、所有提取出的中文界面键、原生 Bundle 查找与格式占位符。该检查不等同于在用户手机上验收桌面名称、页面排版或 Siri 识别。

```sh
xcrun swiftc -parse-as-library scripts/verify-localization.swift -o /tmp/verify-gymcount-localization
/tmp/verify-gymcount-localization /path/to/GymCount.app /path/to/DerivedData
```

提取界面键时构建需传入 `SWIFT_EMIT_LOC_STRINGS=YES`。两个工程均需编译，发布包还需签名与资源核验。

平台说明：[Apple 本地化文档](https://developer.apple.com/documentation/xcode/localization)。

## 2026-10-19 发布

1.1.3 (30) 已通过苹果处理，状态 VALID / IN_BETA_TESTING，内部组 flyingrtx 可用。Delivery UUID：`caa47e53-b166-4cd8-8561-a01065f92317`；发布应用源码 `e696632`。两个工程编译通过，签名归档、导出与最终 IPA 的名称、语言资源、签名、HealthKit 和配套关系核验通过。

实际编译资源检查覆盖手机 200 项、Watch 136 项中文界面键的双语翻译与占位符。Release 优化可能将共享函数的翻译键放入其他源文件的提取结果，因此脚本按 `.build` 目标目录归属校验，不按源码路径推断应用归属。发布证据、编译器提取文件和实际运行的校验器保存在 `build/TestFlight-1.1.3-30/`。

手机当前不可连接，尚未进行新版真机桌面名称、排版、Siri 或双端同步交互验收；用户需更新两端后确认。没有覆盖安装或删除原应用来做验证。
