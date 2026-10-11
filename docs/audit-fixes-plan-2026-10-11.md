# 审查修复执行计划

范围：用户确认的审查问题 1–10；不处理报告末尾两个低影响候选。
保护 Org/SQLite 用户数据；仅临时 fixture 演练写入。不新增依赖、重写历史或推送。
源码备份：`/tmp/org-workflow-before-audit-fixes-20261011.bundle`（修复前所有本地 refs）。

- [x] 桌面与计时（1、8、10）：标题/动作共用当前项；休息恢复拒绝其他 CLOCK；修正模拟菜单。
  文件：workflow-state.js、focus-timer.el 和对应 Lisp/JS tests。
- [x] 持久化（2、6、7、9）：prepared/applied 合法恢复链；失败初始化释放连接；删除错误总数校验；清空已回滚映像。
  文件：store.el、migrate.el 和 store tests。
- [x] 历史（3、4）：投入只累计一次；以承诺 ID 保存投入兑现事实并读取已有日结中的可关联事实。
  文件：history.el 和 attempt/history tests。
- [x] 新增任务（5）：通过已有 org-schedule/事务入口建立明天承诺。
  文件：agenda-console.el 和 agenda-create tests。
- [x] 更新 CONTEXT.md；核对差异；make check、全部 GNOME JS tests 与三个 shell bridge tests。
- [x] 独立审查数据边界；按范围创建本地提交，报告 GUI 和部署限制。

各实现先新增失败回归并确认原因，再作最小修复和相关测试。最后主代理检查全部差异及最终验证。
重点：保留外部改动冲突保护、已结算历史、每条承诺责任、手动 CLOCK；测试不依赖宿主旧字节码。

## 执行验证

- 新增失败回归后修复；最终 `make check`：607/607 ERT、编译、metadata lint、Checkdoc 0、构建及隔离安装启停通过。继承的非致命编译警告仍在。
- 全部 10 个 GNOME `*.test.js` 及三个 shell bridge 测试通过。
- 独立复审验证：30 个旧快照两次检查的扫描从 930 降至 60；新文件提交前 SQL 失败回滚；提交后刷新失败保留文字和已提交事实。
- 用户真实 Org/SQLite 未演练写操作；未热加载当前 Emacs、部署扩展或验证实际 GUI。旧快照没有关联 ID 且来源已经失去时，无法安全补出兑现事实。
