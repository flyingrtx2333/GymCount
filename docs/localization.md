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
