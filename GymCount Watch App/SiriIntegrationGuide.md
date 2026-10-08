# GymCount SiriKit 集成指南

## 概述
GymCount Watch App 现已集成 SiriKit，支持通过语音控制锻炼记录功能。

## 支持的Siri命令

### 1. 开始锻炼
- **中文命令**：
  - "开始记录深蹲"
  - "开始卧推锻炼"
  - "开始硬拉"
  - "开始锻炼"

- **英文命令**：
  - "Start squat workout"
  - "Start bench press workout"
  - "Start deadlift workout"
  - "Start workout"

### 2. 停止锻炼
- **中文命令**：
  - "停止锻炼"
  - "结束锻炼"
  - "停止记录"

- **英文命令**：
  - "Stop workout"
  - "End workout"
  - "Stop recording"

### 3. 添加次数
- **中文命令**：
  - "添加一次"
  - "加一次"
  - "记录一次"

- **英文命令**：
  - "Add rep"
  - "Add one rep"
  - "Record rep"

## 使用方法

### 首次使用
1. 确保Apple Watch已连接到iPhone
2. 在iPhone上打开"设置" > "Siri与搜索"
3. 确保Siri已启用
4. 首次使用时会提示授权Siri访问GymCount

### 语音控制步骤
1. 抬起手腕或点击Apple Watch屏幕
2. 说"嘿Siri"或长按数字表冠
3. 说出相应的锻炼命令
4. Siri会确认并执行操作

## 技术实现

### 文件结构
- `Intents.intentdefinition` - Siri Intent定义文件
- `IntentHandler.swift` - Intent处理器
- `DataManager.swift` - 数据管理器（已更新支持Siri）
- `Info.plist` - 应用配置和权限

### 支持的Intent类型
1. **StartWorkoutIntent** - 开始锻炼
2. **StopWorkoutIntent** - 停止锻炼  
3. **AddRepIntent** - 添加次数

### 权限配置
- `NSSiriUsageDescription` - Siri使用说明
- `NSHealthShareUsageDescription` - 健康数据读取权限
- `NSHealthUpdateUsageDescription` - 健康数据写入权限
- `NSMotionUsageDescription` - 运动数据权限

## 注意事项

1. **网络连接**：Siri需要网络连接才能工作
2. **语言支持**：支持中文和英文语音命令
3. **锻炼状态**：只能在没有活跃锻炼时开始新锻炼
4. **权限管理**：首次使用需要用户授权Siri访问

## 故障排除

### Siri无法识别命令
- 检查网络连接
- 确保Siri已启用
- 尝试更清晰的发音
- 检查应用权限设置

### 命令执行失败
- 确保没有其他活跃的锻炼会话
- 检查应用是否正在运行
- 重启Apple Watch

## 开发者信息

### 自定义Intent
如需添加新的Siri命令，请：
1. 在`Intents.intentdefinition`中添加新的Intent
2. 在`IntentHandler.swift`中实现对应的处理器
3. 更新本地化字符串文件
4. 重新编译并测试

### 调试建议
- 使用Xcode的Intent测试功能
- 检查控制台日志输出
- 测试不同语言环境下的命令识别
