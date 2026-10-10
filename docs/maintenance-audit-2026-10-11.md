# 2026-10-11 精简审查

范围：当前包源码、测试、extras、宿主 modules 和运行中 Emacs；不修改真实 Org 数据。
公开命令及外部只读 API 不因缺少 Lisp 内部调用者而自动判为无用。

## 已处理

- 删除包内十个全局绑定和专用安装函数；原键位移入宿主
  `modules/org-workflow-config.el` 的 `use-package :bind`。包启停不再拥有这些键。
- `org-workflow-install-default-bindings` 仅控制共享 Org／Agenda／Embark 可选绑定。
- 删除没有源码消费者、运行中也未安装的任务 mode-line 格式函数、宽度选项、
  标签及子树进度辅助函数和专用测试。
- 删除无菜单／宿主调用且使用退役状态的 `org-workflow-inbox-state-ready`。

## 保留的实际用途

Sprint 局部 mode-line 的“安排：今天／明天”提示当前安排目标日期；
Focus Timer 的 mode-line 刷新同时服务标准 Org Clock 显示；Workflow minor-mode
lighter 表示模式启用。三者与已删除的任务堆栈展示职责不同，继续保留。

READY 的迁移和旧历史读取仍有消费者；planning JSON 是外部只读接口。
本轮未改写这些规则，也未删除公共 marker accessor。

## 第二轮已清理

下面的第一轮候选已进一步核对调用关系并删除。

| 模块 | 候选 | 依据与下一步 |
| --- | --- | --- |
| core | `target--ancestor-marker-at-level`、`--clean-body` | 无生产调用者，已删除 |
| core | `--normalize-discovered-containers`、`--normalize-current-buffer-before-save` | 无直接调用或 hook 注册，已删除；单条 normalize 操作保留 |
| migrate | `system-setup` | 无调用，已删除；显式 mode 生命周期和手动迁移入口保留 |
| agenda-actions | `agenda-selection-label` | 无菜单或其他消费者，已删除 |
| agenda-view | `agenda-direct-parent-breadcrumb`、`agenda-skip-nonplannable-current-leaf`、`agenda-category-parent-group` | 无生产消费者，已删除 |
| agenda-view | `agenda-future` | 已删除旧 renderer 及专用查询；批量回滚测试改用共享 native row renderer |

## 验证

- 87 项相关 ERT 全部通过，包含用户全局键位在组件安装／撤销期间保持不变。
- `make compile` 成功，仍有既有编译警告。
- 全套测试：568 项中 11 项失败。改动前 HEAD 基线为 570 项中 12 项失败；
  现存失败集合一致，差异是已移除的旧 mode-line 测试，不宣称全套通过。
- 运行中包拥有的全局键位由 10 项降为 0，现有全局键值保持一致；
  旧 mode-line 和 inbox READY 函数已清除，未重启 Workflow 或计时。

第二轮同时删除旧 future-expanded 状态、toggle-future 命令及废弃习惯 face；
共享按钮 map 改名为 `org-workflow-agenda-header-button-map`，继续用于今天／明天
切换和完成回顾。宿主删除旧 face 的主题配置。七天排序范围和日期辅助函数保留。

### 第二轮测试清理与最终验证

既有 11 个失败并非 11 个无用测试。旧“全天可选”标题和习惯区 face、旧 future
collection 以及通知 hook 次数的断言已移除或改为当前契约；items 和 completion
fixture 明确上午任务可见的条件，不依赖实际运行钟点。批量回滚、排序、习惯完成、
共享当前项和标准 CLOCK 等有效验证继续保留。

最终 `make test`：568／568 通过。`make compile` 成功，仍有既有编译警告。
本轮没有通过跳过或整项删除有效业务测试来消除失败，也没有改写真实任务或历史。
