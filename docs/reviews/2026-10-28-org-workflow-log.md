# org-workflow 审查行动日志（2026-10-28）

目标提交 `5b1ff87`，独立包路径 `user-lisp/org-workflow`。
主审加三个只读分工：执行／领域、Agenda／归类、桌面／展示。
下列为按动作批次记录的命令、目的和结果；同批独立读取使用并行调用。
真实用户 Org／SQLite、Emacs daemon、GNOME 会话均未用于写入测试。

| 顺序 | 动作与入口 | 目的／结果 |
| --- | --- | --- |
| 1 | 读取 ub-mode、using-superpowers、dispatching-parallel-agents、verification-before-completion；后续读取 systematic-debugging | 确立先证据后结论、分模块只读审查、核验失败后再提出修复方向 |
| 2 | 定向检索 MEMORY.md；读取两个 AGENTS.md、docs/CONTEXT.md | 确认独立包、临时数据、现有 runner 和历史语义边界；当前事实再以源码验证 |
| 3 | pwd；父／包 git status --short；包 git log -5 | 包干净、HEAD 5b1ff87；记录并保留父配置已有脏改动 |
| 4 | rg --files；wc -l；读取 Makefile、scripts/build-package.el、test/run-tests.el、docs/gtd-module-layout.md | 盘点模块和测试；确认官方测试使用源码副本、隔离 profile |
| 5 | 发现工具名；command -v crapper dryer mutator emacs gjs node python3 | 三个 ub 度量工具不可用；Emacs／GJS／Node／Python 可用，未安装新依赖 |
| 6 | 三个独立审查分工；cat／sed／rg 对照对应源码、调用者和测试 fixture | 覆盖下表 40 个 Lisp 库、extras 与宿主声明入口；不写生产源码 |
| 7 | 官方 build-package test，经 ert selector 仅排除缺失文件交互项 | 774 项执行／761 通过／13 失败；完整日志 ert.log |
| 8 | PACKAGE_USER_DIR=宿主elpa make compile lint checkdoc smoke | compile 通过；lint 因缺 package-lint 中止；未把后续目标当作已执行 |
| 9 | PACKAGE_USER_DIR=宿主elpa make -k checkdoc smoke | checkdoc 9 警告；独立 smoke 通过 |
| 10 | 读取 store／history／journal／migrate／cleanup 及事务测试；rg BEGIN／COMMIT／save-buffer／quit | 跟踪数据库、文本、磁盘和 CLOCK 的实际提交／回滚边界 |
| 11 | 临时 store-probes.el：提交后 quit、保存后错误 | 两个预期一致性断言均失败；打印真实 SQL／文本／磁盘状态 |
| 12 | 同一 probe 的公开 org-todo 保存错误、运行 CLOCK 后 hook 错误 | 两个预期一致性断言均失败；确认影响能经公开状态命令到达 |
| 13 | 关闭 Workflow store 包装的原生 Org 对照 | 1/1 通过，保留已关闭 CLOCK，定位问题来自事务包装 |
| 14 | 执行域既有相关测试 195 项；生命周期／可选集成 13 项 | 全部通过；selected harness 初缺 test-root 变量的问题已单独修正，不列产品缺陷 |
| 15 | Agenda 既有相关契约 35 项＋摘要／捕获 30 项 | 全部通过；新增 probe 补充旧套件未覆盖的身份／撤销场景 |
| 16 | 三个 shell stub 测试、GJS tests/*.test.js | 两个 shell 通过，一个旧 argv 预期失败；14 个 JS 文件通过 |
| 17 | 临时真实 settlement → history-read → exporter → Node 直接运行 history.ts | 原生接受；网页拒绝 dailyMinimumMinutes，移除后仍拒绝 satisfied |
| 18 | 同标题无 ID habit 的真实扫描 → panel-toggle-habit | 请求第二项却选择第一项，两行同时选中 |
| 19 | 非图形有效 payload → 菜单目标与公开 history-panel 对照 | 直接 workbench 报颜色参数错误；公开 router 到达 terminal tracker ready |
| 20 | 主审独立重跑执行 5 项预期不变量、Agenda 3 项故障观测、集成 3 项观测 | 执行 5 项均在目标断言失败；Agenda／集成观测确认故障；观测通过不代表功能通过 |
| 21 | Emacs read 解析顶层定义，不 eval 源表单 | 40 库、818 函数／宏；长度热点用于阅读，不冒充 CRAP／覆盖率 |
| 22 | git worktree list --porcelain | 仅现有主检出，未创建／清理用户 worktree |
| 23 | 对照各分工原始报告、nl -ba 定位、复核差异 | 合并同一身份根因；去除 fixture 错误、推测与未完成的新文件探查 |
| 23a | 追加公开键盘归类复现并独立重跑 | 限定为源标题／ID 被替换但旧 Agenda 行保留；未把底层删除案例扩大为所有公开路径 |
| 24 | 编写本报告与日志，git diff --check，检查暂存路径并本地提交 | 仅审查文档；不推送、不更改运行时 |

## 覆盖地图

- 执行／领域／生命周期：org-workflow、core、items、projects、commands、lifecycle、planning、guidance、periods、habits、focus-timer、sources、leave、weekly、evening，共 15 库。
- Agenda／捕获／归类：agenda、agenda-actions、console、inbox、layout、mouse、notes、plan-undo、projects、review、view，以及 project-classify、project-view，共 13 库。
- 持久化／历史／迁移：store、history、journal、migrate、cleanup，共 5 库。
- 展示／集成：history-view、chart、panel、workbench，以及 panel、screenshot、web-export，共 7 库。
- extras：GNOME JS 状态／同步／菜单／布局、shell 桥接、截图 helper、网页 parser／App、构建／CI／README；宿主 config/org-workflow-config.el 及相关加载声明只读核对。

没有在其余已读模块中确认更多缺陷，不表示证明它们完全无错。
没有运行真实 GUI、桌面安装／服务、Portal、通知／音频、物理按键或浏览器渲染。

## 可重跑命令与临时证据

本轮证据目录 `/tmp/wf-audit-20261028/`，探查代码不在自动回归测试目录中。
`/tmp` 文件可能被系统清理；长期结论、触发步骤与源码位置保存在主报告。

官方 runner 的唯一 selector 调整：

```elisp
(require 'ert)
(advice-add 'ert-run-tests-batch-and-exit :around
 (lambda (original selector)
  (funcall original
   '(not (member workflow-sprint-create-new-file-commit-failure-restores-buffer)))))
(setq command-line-args-left '("test"))
(load "/home/meph1st0/.config/emacs/user-lisp/org-workflow/scripts/build-package.el" nil t)
```

运行时设置 `PACKAGE_USER_DIR=/home/meph1st0/.config/emacs/elpa`。
主要命令及输出：

```sh
PACKAGE_USER_DIR=/home/meph1st0/.config/emacs/elpa emacs -Q --batch -l /tmp/wf-audit-20261028/run-suite.el
PACKAGE_USER_DIR=/home/meph1st0/.config/emacs/elpa make compile
PACKAGE_USER_DIR=/home/meph1st0/.config/emacs/elpa make -k checkdoc smoke
```

`/tmp/workflow-run-selected.el` 激活宿主依赖，将本次源码／测试复制至临时目录，
绑定临时 Org／SQLite，再按 `WF_TEST_FILES` 和 `WF_TEST_SELECTOR` 运行既有 fixture。
根审复核命令：

```sh
WF_TEST_FILES=/tmp/wf-audit-20261028/store-probes.el WF_TEST_SELECTOR='^audit-store-' emacs -Q --batch -l /tmp/workflow-run-selected.el
WF_TEST_FILES=/tmp/wf-audit-20261028/store-probes.el WF_TEST_SELECTOR='^audit-public-' emacs -Q --batch -l /tmp/workflow-run-selected.el
WF_TEST_FILES=/tmp/wf-audit-20261028/store-probes.el WF_TEST_SELECTOR='^audit-control-' emacs -Q --batch -l /tmp/workflow-run-selected.el
WF_TEST_FILES=/tmp/wf-audit-execution-probes.el WF_TEST_SELECTOR='^wf-audit-execution-' emacs -Q --batch -l /tmp/workflow-run-selected.el
WF_TEST_FILES=/tmp/wf-audit-agenda-probes.el WF_TEST_SELECTOR='^audit-\(classify-\|commitment-replacement-\|public-mouse-\)' emacs -Q --batch -l /tmp/workflow-run-selected.el
WF_TEST_FILES=/tmp/wf-audit-agenda-probes.el WF_TEST_SELECTOR='^audit-public-keyboard-' emacs -Q --batch -l /tmp/workflow-run-selected.el
WF_TEST_FILES=/tmp/wf-audit-integrations-probe.el WF_TEST_SELECTOR='^audit-integrations-' emacs -Q --batch -l /tmp/workflow-run-selected.el
node --experimental-strip-types /tmp/wf-audit-20261028/web-contract.mjs
```

日志 `store-probes.log`、`public-store-probes.log`、`native-control.log`、
`verified-execution.log`、`verified-agenda.log`、`verified-integrations.log`、
`verified-keyboard-classify.log`、
`web-contract.log`、`ert.log`、`build.log`、`checkdoc-smoke.log`、`structure.log` 位于证据目录。
分工原始报告为 `/tmp/wf-audit-execution.md`、`/tmp/wf-audit-agenda.md`、
`/tmp/wf-audit-integrations.md`，各自含细分读取／运行记录。

## 13 项既有 ERT 失败的分类

| 测试 | 与当前契约的分歧 |
| --- | --- |
| my/org-mouse-auto-scroll-only-originating-workbench | 仍禁止同工作台右栏滚动；右栏现在是归类目的地 |
| my/org-mouse-batch-commitment-updates-all-and-rolls-back-bad-date | 仍把当天任务当成不能选择的承诺日期 |
| my/org-mouse-drop-batch-undo-restores-source-and-two-panes | 仍期待改期任务离开左栏；随时现在会列项目步骤；在撤销断言前已失败 |
| my/org-mouse-drop-no-op-keeps-source-and-undo-record | fixture 的二级 TODO 现在是阶段，不是任务 |
| my/org-mouse-mixed-drop-skips-already-correct-task | 同上，需按三级任务重建 fixture |
| note-gtd-journal-review-groups-original-items-without-copying | 旧日志回顾视图／SEED 契约 |
| note-gtd-journal-review-refiles-original-and-refreshes | 旧独立回顾／refile 契约 |
| note-gtd-journal-template-install-preserves-current-target | 旧 capture 模板状态预期 |
| org-workflow-agenda-inbox-complete-refreshes-review-without-copying-content | 仍期待完成条目从全部 marker 消失；现在进入今日已完成 |
| org-workflow-agenda-inbox-historical-arrangement-enters-queue-and-undo-restores | 仍期待已安排行不含 Inbox 归类身份；当前保留身份但不重复显示 |
| org-workflow-agenda-inbox-single-and-double-have-distinct-sections | 列表仍遗漏已有未来安排的 Inbox 条目，并保留旧栏目预期 |
| org-workflow-task-types-use-a-separate-org-type-set | 仍期待自动安装 QA／LAB／HW 类型序列；当前新 QA 用直接标签 |
| workflow-inbox-excludes-stage-candidates-and-completes-without-focus | 旧逻辑排除项目待安排步骤；当前随时展示前四项 |

这些分类不替代更新测试后的回归验收；尤其鼠标批量安排／U 的 fixture 应继续验证完整行为。
shell 的 org-workflow-client-test.sh 也仍期待已移除的 frame 参数，在第一处断言即退出，
其后分支不能宣称已由该脚本覆盖。

checkdoc 的 9 处分别在 agenda-layout:127、agenda-notes:99、agenda-projects:126／268／486、
agenda-view:146、project-classify:5／82、project-view:5。
本次没有为了通过检查而修改它们。
