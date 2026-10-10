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

## 后续候选

以下是静态调用审查发现的候选，本轮只记录，未改变其行为。

| 模块 | 候选 | 依据与下一步 |
| --- | --- | --- |
| core | `target--ancestor-marker-at-level`、`--clean-body` | 无生产调用者的内部辅助函数，可进一步清理 |
| core | `--normalize-discovered-containers`、`--normalize-current-buffer-before-save` | 无直接调用或 hook 注册；单条 normalize 操作仍在使用，须保持其行为 |
| migrate | `system-setup` | 无调用，重复旧初始化／自动迁移步骤；当前入口是显式 mode 生命周期，需单独确认退役范围 |
| agenda-actions | `agenda-selection-label` | 无菜单或其他消费者 |
| agenda-view | `agenda-direct-parent-breadcrumb`、`agenda-skip-nonplannable-current-leaf`、`agenda-category-parent-group` | 无生产消费者，属于旧 Agenda 路径候选 |
| agenda-view | `agenda-future` | 旧 renderer 只有专用测试调用；共享按钮 map 仍被新 renderer 使用，不能整组删除 |

## 验证

- 87 项相关 ERT 全部通过，包含用户全局键位在组件安装／撤销期间保持不变。
- `make compile` 成功，仍有既有编译警告。
- 全套测试：568 项中 11 项失败。改动前 HEAD 基线为 570 项中 12 项失败；
  现存失败集合一致，差异是已移除的旧 mode-line 测试，不宣称全套通过。
- 运行中包拥有的全局键位由 10 项降为 0，现有全局键值保持一致；
  旧 mode-line 和 inbox READY 函数已清除，未重启 Workflow 或计时。
