# DIVE 与每日尝试

[文档入口](README.md)（文中的默认快捷键需设置 `org-workflow-install-default-bindings` 为 t） · [任务与历史模型](workflow-architecture.md)

## 当前范围

`DIVE` 是当前活跃任务组的未完成 Org 状态，替代旧 `CURR` 标签。
计时开始或停止不自动切换 DIVE。
默认待安排候选是直接父标题为 DIVE 的未安排 TODO 叶子：不穿过中间分组继承，
DIVE 叶子自身也不是当前范围候选。全部 project/area 范围仍可手动切换。
已安排的执行队列不以 DIVE 为准入条件。

## 提前开放下一组

非一级的 DIVE 组剩余未完成直接任务子节点不超过阈值时，组内完成或 HOLD
会尝试把紧邻的下一兄弟任务组设为 DIVE；原组仍保留 DIVE。
不跨父节点、不重开已完成或 HOLD 分支，不把无任务的标题开放为组。
一级里程碑始终手动管理。

阈值是 `org-workflow-dive-lookahead-threshold`，默认 2，nil 禁用。
`M-x org-workflow-sync-dive` 对当前组做一次同步；本轮新开放组不继续连锁推进。
旧 `org-workflow-sync-curr` 和旧阈值名仍是兼容别名，日常使用 DIVE 名称。
刷新 Agenda 不推进相邻组，源缓冲区修改按原有方式保存。

## 每日有效投入

有效尝试是当天正分钟数、已经结束、直接记录在任务上的 Org CLOCK。
Focus Timer 默认不足五分钟的区间会取消；正在计时、被取消的区间和子任务工时不算父任务尝试。
实际完成目标也能兑现当天责任，即使没有时钟。

每日兑现和任务完成分开：尝试不会设置 DONE、改期或删除任务。
普通任务不增加专门图标；承诺任务在 Agenda 目标日期上从空心菱形变为实心。
GNOME 阶段进度包含承诺及其他已安排任务的尝试；承诺进度按固定日期责任集合计算。
明天的进度需要明天的实际投入。

## 历史边界与迁移

数据库的 `attempt-progress-since` 标记规则启用日期，之前的日期沿用旧完成规则；
已有结算快照不自动改写。新承诺详情的 `:satisfied` 和实际 `:outcome` 分开保存。
请假补录要求使用每日兑现结果，不直接按 TODO 是否完成判断。

`M-x org-workflow-migrate-current-scope` 预览显式 CURR 根的转换，前缀参数执行。
要求源文件已保存、未变化且可写，在 `var/workflow-backups/curr-to-dive-*/` 备份。
转换保留其他标签、安排和属性，不重开已完成或 HOLD 分支。
DIVE 通过 Org TODO setup filter 加入本地序列，不为此重写文件头。

启用 `org-workflow-mode` 后调用网页导出 setup：启动导出一次，成功结算触发新快照。
这是当前配置行为；仅调用历史模块自身 setup 会移除旧导出 hook，不能据此推断最终初始化状态。
原生历史面板直接读取后端，网页读取导出的 JSON，详见 [网页说明](../extras/web/README.md)。
