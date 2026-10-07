# Workflow 规划辅助

[文档入口](README.md)（文中的默认快捷键需设置 `org-workflow-install-default-bindings` 为 t） · [任务与历史模型](workflow-architecture.md)

## 项目接口

在 Emacs 中启用 `org-workflow-mode` 后使用这些接口。接口读取包括未保存修改的活跃 buffer，写入后由用户保存。不要绕过接口编辑 SQLite。

- `(org-workflow-planning-context-json FILE POSITION)`：POSITION 是当前阶段标题位置；只读返回该子树与下一兄弟子树、文件 SHA256、任务位置／ID、标签、估时、边界、依赖、记录、最近七日投入及背景／周日志路径。查询不创建 ID。
- `M-x org-workflow-planning-background`：明确创建或访问独立 Vulpea 背景笔记；只有此编辑动作会为项目补 ID。背景文件保存在笔记目录 `planning/PROJECT-ID.org`。
- `M-x org-workflow-planning-preview`：选择建议 JSON 文件。SPC 标记，a 采纳所选；C-u a 在明确确认后替换已有值。一次采纳后需要重新生成上下文。
- `(org-workflow-planning-set-week-goals DATE TEXT)`：目标周日志“周目标”正文写入入口；保留其他节。仅在用户确定目标后调用。

通过 `emacsclient --eval` 调用；构造参数时使用正确的 Lisp 字符串转义，不把外部文本插进 shell 代码。导出的 file/hash/position/title 必须原样引用。版本过期必须重新导出。建议文件可放 `/tmp`，正式的分析、范围和不确定性放项目背景或源任务说明中。

建议 JSON 示例（值仅作格式示范，不是课程工时事实）：

```json
{"version":1,"file":"/absolute/project.org","hash":"exported-sha256","suggestions":[{"position":123,"title":"原任务标题","tag":"@deep","effort":"1:00","boundary":"能用自己的话解释并完成一个例子","reason":"选择一小时作为初步完成估计，区间 45–90 分钟","uncertainty":"尚不清楚已有知识；首次探索预算 25 分钟，与完成估时不同"}]}
```

省略 tag/effort/boundary 表示不建议更改；空缺信息不要伪造。默认保留已存在的值，包括继承的互斥标签。CLOCK 不完整、任务未完成或范围改变时不可当作完成耗时。

## 日常入口

Sprint 直接键位：`y` 切换今天／明天，`W` 访问目标周的周目标，`E` 编辑或清空明日开工提示，`N` 编辑任务的“下次从这里开始”；`?` 查看全部按键。明日视图顶部只读取周目标，不会因缺少日志而创建文件。周日的提示和周目标均指向下周。

长期指导：`M-x org-workflow-guidance-open` 打开专门的 Org 笔记，每个标题写一句指导；在需要的标题运行 `org-workflow-guidance-select`。没有当日提示时使用这个标题，不轮播。任务续接提示存入不继承的 `WORKFLOW_RESUME` 属性。

历史首次专注标记仍保存在 SQLite 的 `started:YYYY-MM-DD` 元数据。只有实际开始 focus 才写入，安装前的计时不回推；取消、休息和重启不删除标记；该标记不再决定顶栏显示。周投入读取已结算快照以及当天保留的 CLOCK／完成记录，不以承诺兑现率替代投入。来源缺失或读取失败显示未知。

GNOME 配套扩展空闲时在原计时区域显示当前任务的父组；专注和休息显示计时状态，习惯入口保留在菜单。右侧在专注循环（含短休息、长休息）中显示七天投入；停止循环后优先显示当前任务的续接提示，缺少时回退到当日提示／长期指导，详情保留提示及当前任务续接信息。长文本截短，未来日期淡化。更新 GNOME 扩展文件后，Wayland 会话可能需要重新登录才重新载入 JavaScript。

## 背景与编码

`org-workflow-planning-background` 也接受可选的标题位置，用于文件内 CS50x 这样的独立里程碑。上下文会向上寻找已有背景关联。背景创建是明确的编辑动作，可以添加 ID；只读上下文不会。

`org-workflow-planning-context-json` 返回已解码的 Unicode JSON 文本，可用 UTF-8 保存。直接调用 `json-serialize` 得到的是 UTF-8 字节串，插入多字节 buffer 前需解码，避免中文乱码或触发编码选择提示。
