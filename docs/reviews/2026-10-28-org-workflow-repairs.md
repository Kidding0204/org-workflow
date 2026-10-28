# org-workflow 审查修复记录（2026-10-28）

范围：[已批准审查](2026-10-28-org-workflow.md) 的 11 类问题，以及独立终审复现的 3 个关联边界。
基线 `65cfb22`。用户确认后原地修复当前功能分支，保留父配置的无关修改。
真实 Org、SQLite、daemon 和 GNOME 会话未用于写入测试。

## 修复与维护入口

| 范围 | 根因修复 | 维护入口 |
| --- | --- | --- |
| 任务身份 | 原标题首星号的原生 marker 范围＋已有 ID；删除／替换后拒绝动作，重命名／原生移动保留选择 | core 的 source-current/validate-execution；items 的 source-live-p |
| 归类身份 | 保留渲染时的 ID／标题，整批预检；有 ID 优先验证 ID，无 ID 核对标题 | agenda-view、agenda-projects、project-classify |
| 每日承诺 U | 记录所有受影响挂接、当日项目索引和事件差异；追加补偿而不删历史，检查后来变化 | agenda-plan-undo、projects-superseded-p |
| CLOCK 与失败事务 | 回滚状态／安排时保留实际完成的 CLOCK 关闭／取消，不恢复运行中的计时状态 | store 的 clock-snapshot/result/retain-clock-result |
| COMMIT 中断 | 短临界区保护 SQLite COMMIT、内存提交标记与变更组接受 | store--operation |
| 事务内保存 | 原生保存 hook 记录字节映像；错误时只恢复已验证为本次写入的磁盘内容，外部冲突保留恢复记录 | store--before-save/after-save/restore-saves；commands-setup |
| 关闭分支 | 队列和已有责任复用 DONE/HOLD 执行阻断规则；失效当前对象释放匹配计时 | core execution-blocked-p、projects row-blocked-p |
| 进度政策 | 新 completion-floor 日期只计 DONE；旧日期继续按既有政策解释 | core stage-progress |
| 无 ID 习惯 | 使用绑定原始标题范围的内存 key，不复用补位位置、不写源 ID；源失效后要求重新选择 | items item-key/current-item，panel toggle-habit |
| 网页契约 | 严格校验可选的底线字段和 task.satisfied，保留旧快照兼容 | extras/web/src/history.ts |
| 历史入口 | 主菜单复用 history-panel 的图形／终端路由 | weekly 的菜单 h |

原生 Org 的移动保存只登记它自己的 CLOCK／Agenda／日志 marker，没有额外来源 hook。
因此使用生命周期拥有的窄 `org-save-markers-in-region :after` 集成登记选择范围。
停用时移除，且释放选择引用。若 Org 将来提供公开扩展入口，应改用该入口并删除此 advice。

源码范围 key 是内存身份，不是持久 Org ID。普通标题／正文编辑保留该身份；
未登记的原生习惯移动可使旧 key 失效，要求重新选择，不能自动操作补位条目。

## 独立终审与修复波次

新鲜上下文审查发现 3 项 Important，全部进入同一修复波次并先复现失败：

1. 习惯切换复制普通任务 marker 后，身份判断降级；旧任务被删仍可完成下一任务。
   通过 marker 的源位置／范围身份核对及 panel 保留原始 item 纠正。
2. 删除旧任务后，其 collapsed marker 恰好指向另一手动 CLOCK，释放动作误取消无关计时。
   源已丢失时，只有捕获的原始计时间隔能证明归属，不使用补位位置作为归属证据。
3. 无 ID 习惯的旧位置 key 被后继习惯复用。改成 buffer-local 标题范围身份，
   保留显式但失效的选择，避免回落到另一个习惯或普通任务后执行完成。

终审 3 个失败案例均已 RED→GREEN；补测删除习惯后也不能完成普通任务。
没有未处理的 Critical／Important，也没有终审提出的 Minor 待办。
未进行第二轮重复审查；最终通过故障回归及完整测试验证这一修复波次。

## 验证

- 官方 `make test`，没有 selector 排除：**816／816 通过**。
- `make compile checkdoc smoke`：通过，**checkdoc 0 警告**；全新安装、无副作用 require、模式启停通过。
- 真实 TS parser 的独立 Node 契约：**22／22 通过**。
- 3 个 shell 桥接测试脚本通过；14 个 GNOME 纯逻辑测试文件通过。
- 所有数据写入测试使用临时 Org／SQLite，公开 C／鼠标承诺／U／TODO 路径包含在回归中。
- 既有 13 个陈旧断言按当前用户契约更新，保留事务、marker、正文、归类、撤销和数量上限检查。
  新文件提交失败测试改为验证新目标的回滚，不提前把不存在的目标加入 Agenda 并卡在原生提示。
- 完整 npm／Vitest 实际尝试后因本机没有 node_modules／vitest 无法执行；未安装新依赖。
  package-lint 同样未安装，metadata lint 未完成。源码编译／checkdoc／smoke 不依赖这些检查。
- 物理键盘／鼠标、真实 GUI、Portal／音频／桌面服务和浏览器渲染未验证。
  故障注入不等同于真实断电或跨进程文件系统原子性证明。

## 提交

- `14f27e6`：历史解析契约、菜单路由和客户端测试。
- `8f7cf81`：任务身份、关闭分支、进度政策和习惯身份初步修复。
- `acce948`：归类身份与每日承诺完整撤销。
- `251ccc4`：事务、磁盘保存与实际 CLOCK 结果。
- `757967f`：独立终审发现的习惯切换／旧 key／无关计时边界。
- 最后一次文档／测试提交整理当前规则、陈旧 fixture、checkdoc 和本记录。

## 行动日志与决策

1. 读取包约定、当前上下文、ub-mode、TDD／验证与审查流程；核对独立包干净、基线及父配置改动。
2. 以审查文档作为规格，写实施计划；按无重叠文件归属并行处理，主审负责持久化和最终集成。
3. 将公开复现转换为临时数据回归。最初事务 4 项失败、执行 7 项失败、Agenda 7 项失败、
   网页 16 项失败；分别观察目标断言后最小修复。fixture 错误单独修正，没有当作产品缺陷。
4. 通过原生保存 hook 记录磁盘写入；对“外部改动导致原生 undo 提示”的失败重新定位：
   自有文本回滚期间暂时脱离 visited-file 名称，保留真实 visited mtime，使以后保存仍会检测外部变化。
5. 对提交边界、公开 TODO、内层事务、取消／结束 CLOCK、原有未保存正文、外部编辑做故障验证。
   额外发现 CLOCK 行已不存在时不能把邻接正文当作 CLOCK，先 RED 后修复。
6. 更新旧模板／栏目／三级任务 fixture 与 shell argv 断言；检查新增会话引用在停用时释放。
7. 完整套件先 812／812，通过编译／安装；新鲜整体审查独立复现上述 3 项 Important。
   主审一次修复并加入公开动作回归，最终全套 816／816。
8. 重新验证 TS parser、shell 和 GNOME 纯逻辑；更新当前维护文档与审查修复指针，核对差异并分批本地提交。
9. 同步本地包编译产物。新的条目结构布局需要重新启动 Emacs，避免把旧会话对象与新访问器混用。
   未自动热载或重启用户会话。

采用的规则及取舍：

- 关闭的 DONE／HOLD 分支统一阻断未完成执行与当日责任；完成历史保留。
  若用户以后希望保留关闭分支的执行入口，需要显式调整这条共享政策。
- 无 ID 来源以只读内存身份支持动作；失效时多一次选择，代价是保守交互，收益是不改错条目。
- 检测到外部磁盘变化时保留 prepared 恢复事实，不覆盖它；这类冲突需要显式恢复决策。
- 整体审查暂不判断的 GUI、实际断电、文件竞态和前端构建边界，均按上述“未验证”报告，
  不把 batch 结果推断成真实会话验收。

完整临时命令／RED／GREEN 日志保留在 `/tmp/wf-repair-20261028/`，系统可能清理。
主要日志：full-reviewed／acceptance-ert、build-reviewed、acceptance-node、store-final、
execution-report、agenda-report、integrations-report、stale-tests-report、final-review、review-fixes-final。
