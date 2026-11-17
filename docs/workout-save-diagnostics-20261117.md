# Watch 保存分步诊断

仅增加诊断，不改计数算法、模型、分组、保存顺序、文件队列、HealthKit 等待及超时策略，也不修改“间隔”状态的 UI。此前已授权删除的 iOS 图表“有时长”提示另行提交，一起打包。

## 文件

Watch App 容器内：

`Library/Application Support/Diagnostics/workout-save-v1.jsonl`

轮换文件为同目录的 `workout-save-v1.previous.jsonl`。每份上限 256 KiB，共两份；写入使用独立队列，最多积压 512 条，超出部分丢弃并在后续记录写入 `droppedBefore`。诊断失败不影响业务返回值和错误，不额外等待日志落盘。

只记录时间、运行／操作随机标识、构建号、阶段、结果和错误域／代码；不记录原始采样、动作次数、重量、心率、卡路里、用户标识或错误描述。

## 阶段与读取

- `file.*`：begin 为入队，running 为开始执行，end 为完成或失败。running 的 elapsedMs 是排队耗时，end 减 running 是执行耗时；包括共享队列上的其他任务，历史传感器索引明确标记为 `file.sync.sensor_index`。
- `motion.*`：停止、排空、最终分析及应用结果。
- `timeline.build/encode/write`：构建及校验时间轴、编码、原子写入。
- `draft.persist`、`report.validate`、`history.encode/write`：草稿、报告校验与历史落盘。
- `health.stop/collection/commit/finish`：系统健康训练收尾。原等待和失败处理保持。
- `workout.save`、`segment.close`：整场及片段总时间。文件可能保留多次启动的数据，以 run + operation 区分。

从配对的 Watch 使用已验证的 `devicectl device copy from --domain-type appDataContainer --domain-identifier com.flyingrtx.GymCount.watchkitapp` 通道复制这两个普通文件，无需系统日志导出。只传入实际存在的文件，随后运行：

```sh
rtk bypass python3 scripts/read-workout-save-diagnostics.py current.jsonl previous.jsonl
```

没有 end 只表示缺少结束记录，可能是仍在等待、进程结束、轮换或记录丢弃，不能单独认定卡死。

## 验证范围

使用现有 41mm Watch 模拟器的独立 App 标识执行队列等待／返回值／错误保持、文件轮换、不可写目录、整场保存与文件读取验证；沿用停止采样不等待无关文件队列的回归。健康写入仍须新版实际佩戴后采集，模拟器未签名环境不作 HealthKit 真机验收。最终结果与发布凭证见 `AGENTS.md`。
