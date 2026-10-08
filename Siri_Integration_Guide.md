# SiriKit 集成指南

## 概述
已成功为 GymCount Watch App 集成了完整的 SiriKit 功能，用户现在可以通过 Siri 语音控制锻炼的开始、停止和记录次数。

## 功能特性

### 支持的语音命令

#### 1. 开始锻炼 (StartWorkout)
用户可以说以下命令来开始锻炼：

- **开始记录深蹲**
  - "Hey Siri, 开始记录深蹲"
  - "Hey Siri, 开始深蹲锻炼"
  
- **开始记录卧推**
  - "Hey Siri, 开始记录卧推"
  - "Hey Siri, 开始卧推锻炼"
  
- **开始记录硬拉**
  - "Hey Siri, 开始记录硬拉"
  - "Hey Siri, 开始硬拉锻炼"
  
- **指定重量开始锻炼**
  - "Hey Siri, 开始记录深蹲，重量50公斤"
  - "Hey Siri, 开始卧推锻炼，重量60公斤"

#### 2. 停止锻炼 (StopWorkout)
- "Hey Siri, 停止锻炼"
- "Hey Siri, 结束当前锻炼"
- 完成时会自动保存记录并同步到 HealthKit

#### 3. 添加次数 (AddRep)
- "Hey Siri, 添加一次"
- "Hey Siri, 记录一次"
- 实时更新当前锻炼的次数统计

## 技术实现

### 1. Intent 定义 (`Intents.intentdefinition`)

定义了三个主要意图：

**StartWorkout Intent**
- `exerciseType`: 锻炼类型枚举（卧推、深蹲、硬拉）
- `weight`: 重量参数（可选，默认使用设置中的默认重量）

**StopWorkout Intent**
- 无参数
- 结束当前活跃的锻炼会话

**AddRep Intent**
- 无参数
- 为当前锻炼添加一次计数

**ExerciseTypeIntent Enum**
- `unknown` (0): 未知类型
- `benchPress` (1): 卧推
- `squat` (2): 深蹲
- `deadlift` (3): 硬拉

### 2. Intent 处理器 (`IntentHandler.swift`)

实现了完整的 Intent 处理逻辑：

**IntentHandler 主类**
- 根据 Intent 类型分发到对应的处理器

**StartWorkoutIntentHandler**
- 实现 `StartWorkoutIntentHandling` 协议
- `handle()`: 处理开始锻炼请求
- `resolveExerciseType()`: 解析并验证锻炼类型
- `resolveWeight()`: 解析并验证重量参数（0-500kg）
- `confirm()`: 确认是否可以开始锻炼
- ExerciseTypeIntent → ExerciseType 枚举转换

**StopWorkoutIntentHandler**
- 实现 `StopWorkoutIntentHandling` 协议
- `handle()`: 处理停止锻炼请求
- `confirm()`: 确认是否有活跃的锻炼
- 自动保存历史记录并同步到 HealthKit

**AddRepIntentHandler**
- 实现 `AddRepIntentHandling` 协议
- `handle()`: 处理添加次数请求
- `confirm()`: 确认是否有活跃的锻炼
- 实时更新次数统计

### 3. 数据管理器集成 (`DataManager.swift`)

添加了 Siri 支持方法：
- `canStartWorkout()`: 检查是否可以开始新锻炼
- `getCurrentWorkoutStatus()`: 获取当前锻炼状态
- `startWorkout()`: 开始锻炼会话
- `endWorkout()`: 结束锻炼并保存
- `addRep()`: 添加一次计数

### 4. 本地化支持

**中文字符串 (zh-Hans)**
- `siri_workout_already_active`: "已有活跃的锻炼会话，请先结束当前锻炼"
- `siri_invalid_exercise_type`: "无效的运动类型"
- `siri_workout_started`: "已开始记录 %@ 锻炼"
- `siri_no_active_workout`: "没有活跃的锻炼，请先开始锻炼"
- `siri_workout_stopped`: "已完成 %@ 锻炼，共 %d 次"
- `siri_rep_added`: "已添加一次，当前 %@ 共 %d 次"

**英文字符串 (en)**
- `siri_workout_already_active`: "There's already an active workout session..."
- `siri_invalid_exercise_type`: "Invalid exercise type"
- `siri_workout_started`: "Started recording %@ workout"
- `siri_no_active_workout`: "No active workout, please start a workout first"
- `siri_workout_stopped`: "Completed %@ workout with %d reps"
- `siri_rep_added`: "Added 1 rep, current %@ total: %d reps"

### 5. 权限配置 (`Info.plist`)
- 添加了 `NSSiriUsageDescription` 权限说明
- 配置了必要的应用权限

## 使用方法

### 首次使用
1. 用户首次使用 Siri 功能时，系统会请求 Siri 权限
2. 用户需要授权应用访问 Siri
3. 可以在 Apple Watch 设置中管理 Siri 权限

### 完整工作流程示例

```
用户: "Hey Siri, 开始记录深蹲"
Siri: "已开始记录深蹲锻炼"

用户: "Hey Siri, 添加一次"
Siri: "已添加一次，当前深蹲共 1 次"

用户: "Hey Siri, 添加一次"
Siri: "已添加一次，当前深蹲共 2 次"

用户: "Hey Siri, 停止锻炼"
Siri: "已完成深蹲锻炼，共 2 次"
```

### 错误处理

**开始锻炼时**
- 已有活跃的锻炼会话 → "已有活跃的锻炼会话，请先结束当前锻炼"
- 无效的锻炼类型 → "无效的运动类型"
- 重量超出范围（0-500公斤）→ 提示重量无效

**停止锻炼时**
- 没有活跃的锻炼 → "没有活跃的锻炼"

**添加次数时**
- 没有活跃的锻炼 → "没有活跃的锻炼，请先开始锻炼"

## 开发注意事项

### 1. Intent 参数验证
- 锻炼类型必须从预定义的枚举中选择
- 重量范围限制在 0-500 公斤
- 所有操作前都检查锻炼会话状态

### 2. 用户体验
- 提供清晰的语音反馈
- 支持中英文双语
- 处理各种边界情况
- 实时更新统计数据

### 3. 集成测试
- 测试各种语音命令组合
- 验证错误处理逻辑
- 确保与现有功能兼容
- 测试 HealthKit 同步

### 4. 数据一致性
- Intent 操作与 UI 操作保持数据同步
- 通过 `DataManager.shared` 单例确保状态一致
- 使用 `@Published` 属性自动更新 UI

## 配置步骤

### Xcode 项目配置

1. **添加 Siri 能力**
   - 在 Xcode 中选择项目 Target
   - 转到 "Signing & Capabilities"
   - 点击 "+ Capability"
   - 添加 "Siri"

2. **Info.plist 配置**
   - 添加 `NSSiriUsageDescription` 键
   - 值：描述为什么需要 Siri 权限（例如："让您通过语音控制锻炼记录"）

3. **Intent 文件配置**
   - 确保 `Intents.intentdefinition` 已添加到 Target
   - 在 Target Membership 中勾选对应的 Target

4. **构建设置**
   - 确保 Intent 定义文件已正确编译
   - Xcode 会自动生成 Intent 类（如 `StartWorkoutIntent`）

## 故障排除

### 常见问题

1. **Siri 无法识别命令**
   - 确保应用已获得 Siri 权限
   - 检查语音命令是否准确
   - 验证 Intent 是否正确注册

2. **锻炼无法开始**
   - 检查是否已有活跃的锻炼会话
   - 验证锻炼类型和重量参数
   - 查看控制台日志获取详细信息

3. **权限问题**
   - 在 Apple Watch 设置中检查 Siri 权限
   - 重新授权应用访问 Siri
   - 确保 Info.plist 中包含 `NSSiriUsageDescription`

4. **Intent 无法识别**
   - 清理项目并重新构建
   - 检查 Intents.intentdefinition 文件配置
   - 验证 IntentHandler 是否正确实现

5. **数据不同步**
   - 确保使用 `DataManager.shared` 单例
   - 检查 `@Published` 属性是否正确声明
   - 验证 UI 是否监听了数据变化

## 调试技巧

### 控制台日志
IntentHandler 中包含详细的日志输出：
- `🎤 Siri: 处理开始锻炼请求`
- `✅ Siri: 成功开始 [类型] 锻炼`
- `⚠️ Siri: 已有活跃的锻炼`
- `❌ Siri: 无效的运动类型`

### 测试命令
可以使用以下命令进行测试：
```
"Hey Siri, 开始记录深蹲"
"Hey Siri, 开始记录卧推，重量60公斤"
"Hey Siri, 添加一次"
"Hey Siri, 停止锻炼"
```

## 总结

✅ **已完成的功能**
- ✅ 三个完整的 Intent 处理器（开始、停止、添加次数）
- ✅ ExerciseTypeIntent 枚举转换
- ✅ 完整的参数验证和错误处理
- ✅ 中英文双语支持
- ✅ HealthKit 自动同步
- ✅ 数据管理器集成
- ✅ 详细的日志记录

SiriKit 集成已完成，用户现在可以通过语音命令完整控制锻炼流程：开始锻炼、记录次数、停止锻炼。该实现具有良好的错误处理、多语言支持和用户体验。
