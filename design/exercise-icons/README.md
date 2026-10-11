# GymCount 动作线条图标库

43 个独立 SVG：40 个常见训练动作和 3 个采集类别。沿用已选定的 imagegen 人体线稿风格，使用自然人体比例、短颈、圆润关节和真实器械轮廓；卧推采用屈肘姿态，弯举为单手。

## 覆盖范围

| 分类 | 数量 | 动作 |
| --- | --- | --- |
| 杠铃 | 12 | 深蹲、卧推、硬拉、前蹲、罗马尼亚硬拉、相扑硬拉、俯身划船、肩上推举、弓步蹲、臀推、弯举、仰卧臂屈伸 |
| 哑铃 | 10 | 单手弯举、卧推、上斜卧推、飞鸟、肩推、侧平举、前平举、单臂划船、锤式弯举、过顶臂屈伸 |
| 器械与绳索 | 9 | 高位下拉、坐姿绳索划船、夹胸、三头下压、弯举、面拉、腿举、坐姿腿屈伸、俯卧腿弯举 |
| 自重与壶铃 | 9 | 引体向上、俯卧撑、双杠臂屈伸、保加利亚分腿蹲、高脚杯深蹲、壶铃摆动、站姿提踵、平板支撑、仰卧起坐 |
| 采集类别 | 3 | 静止、走动、其他非训练 |

## 文件与使用

- `svg/{id}.svg`：透明背景、64 × 64 viewBox、使用 currentColor 的独立矢量文件。内部全部为贝塞尔路径，不包含 PNG、base64 或外链。线条已展开为闭合轮廓，路径孔洞保持透明；放大不会依赖原始图片分辨率。改变线宽需要编辑轮廓节点，而不是修改 stroke-width。
- `catalog.json`：稳定动作 ID、中文名、分组、资源名以及来源线稿和裁切区域。已有 ID 沿用接口名称。
- `index.html`：离线目录，支持按器械筛选、中文或 ID 搜索、深浅主题、26/32/48 px 预览及单个/整套下载。
- `sprite.svg`：网页 symbol 合集，按 `exercise-{id}` 引用。标识图配合可访问动作名称使用。
- `gymcount-exercise-icons.zip`：完整 SVG、目录、sprite 和离线预览的便携包。
- `overview*.svg`：整套及分类设计总览；`strength-detail.svg`：原有四个训练动作的放大图。
- `concepts/`：已选线稿、四组新增动作的 imagegen 原稿和完整提示词。既有的彩色及旧版设计稿仍保留供追溯。
- `validation/`：规范化的源轮廓和转换报告。验证结果及渲染预览位于项目忽略目录 `build/ExerciseIcons/`。

建议列表图标为 32–48 px，动作详情为 96 px 或以上。26 px 仅作为辅助标识，始终配合动作名称；复杂器械图在较大尺寸下细节更清楚。

```html
<svg width="48" height="48" aria-hidden="true">
  <use href="/icons/exercises/sprite.svg#exercise-single_arm_row"></use>
</svg>
<span>单臂哑铃划船</span>
```

嵌入单个 SVG 或 sprite 后可通过 CSS color 着色；作为普通 img 使用时默认为黑色。Apple image set 使用 universal SVG，保留矢量并按 template 着色。

## 维护与复现

1. 以 `concepts/imagegen-exercises-line-v1.png` 为风格参考生成新动作。每个动作选择能够清楚区分的姿态；人体关节和器械不得粘连。原始图片不作为运行时依赖。
2. 将新增动作的稳定 ID、中文名及原稿登记到 `concepts/expansion-manifest.json`；新增大量动作时用独立分组原稿，不变更已有 ID。转换脚本当前处理 1254 × 1254 的九宫格，已选七个动作使用明确的无标签裁切区域。
3. 安装 Pillow 和 potrace，然后运行 `scripts/vectorize-exercise-icons.py`。脚本沿空白间隔分离图形，统一留白后输出 SVG 路径。转换配置是确定的，不会重新调用 imagegen。
4. 运行 `python3 scripts/build-exercise-icons.py`，同步 Watch/iPhone 资源并生成目录、sprite、总览和 ZIP。
5. 安装 CairoSVG 后运行 `scripts/verify-exercise-icons.py`。检查无图片负载、透明性、独立图形、边界留白、转换前后轮廓一致性和 ZIP 完整性；再目视检查姿态及深浅主题/小尺寸。

当前转换脚本将 43 个的数量作为本轮完整性断言。扩展目录时同步更新数量断言和目录文案。

图标库已接入 Watch 主菜单、采集动作选择和 iPhone 训练预览。新增图标作为资源库提供，并不改变 App 现有动作菜单、计数算法或云端动作支持。2026-10-09 已随 iOS 与 Watch 1.1.3 (10) 发布到内部 TestFlight，Apple 状态为 VALID，现有 flyingrtx 测试组可安装；发布凭证见项目 CAPTURE-TESTFLIGHT.md。
