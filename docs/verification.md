# 0.1.0 提取验收记录

日期：2026-10-07。Emacs 31.1；依赖从 GNU ELPA / MELPA 安装到独立目录。

- `make check`：506 个 ERT 全部通过，byte compilation 成功，package-lint 通过，checkdoc 0 项。
- 实际 tar 安装：新 package-user-dir 安装 33 个库；编译后的加载不激活模式，显式启用／停用成功，集成记录清空。
- 配套源码：55 个网页测试、TypeScript/Vite 构建、3 个客户端契约脚本和 11 个 GJS 测试通过。
- 现有个人配置：systemd Emacs 重启后无 init 错误，已加载独立包；兼容命令和状态接口可用。
- 临时 Wayland 图形 frame：Sprint 与历史面板均显示双栏；Agenda 行保留源 marker，历史面板生成 SVG display。
- 切换前后：Org 源文件 SHA256 与 SQLite 全部 7 张表内容一致，未保存源 buffer 为零。

编译仍报告继承代码的非阻断警告（长文档、少量未知可选函数及过时 Org API）。
本次 GUI 检查验证窗口、模式、marker 和 image 对象；未重新完成物理鼠标及全部主题视觉验收。
未安装新的 GNOME 扩展、未调用截图 Portal。公开仓库的远端验证见 [GitHub CI](https://github.com/Kidding0204/org-workflow/actions/workflows/ci.yml)。
MELPA recipe 尚未针对公开远端用 package-build 验证，未提交或获得 MELPA 接受。

## User Lisp 部署复核

同日迁至 `~/.config/emacs/user-lisp/org-workflow/`，启用标准启动准备。
开发目录通过 `user-lisp-ignored-directories` 排除；自动生成的 autoload 文件
不含测试、脚本和依赖缓存。实际服务冷启动无 init 错误，入口和核心函数均从
`.elc` 加载；独立回归仍为 506/506。Wayland 双栏和 SVG 再次通过，数据库表内容
及源文件保持一致。用户配置适配器仅 require，不再手动设置包的 load-path。

Web 导出测试显式指定上海时区；UTC 环境完整 `make check` 为 506/506，
测试在源文件副本中运行，避免用户自动编译字节码与隔离依赖的 Org 版本冲突。

## 原生主入口与部署编译

同日扩展 `org-workflow-menu` 为分组 Transient 主入口；移除网页启动器与
后台快照生成，保留显式静态导出和迁移解析。本次本地 `make check` 为
503/503 ERT、checkdoc 0 项、编译／metadata lint／安装启停验证通过。

实际 User Lisp 33 个库完成字节编译及异步原生编译；服务冷启动加载 `.elc`，
无 init 错误，网页命令、旧快捷键和导出 hook 均不存在。
隐藏 Wayland frame 中通过真实 `C-c k` 键盘入口，`h` 打开双栏历史和 SVG，
`A` 打开双栏 Sprint；所有菜单分组可见，`f t` 动作分派通过无副作用替身验证。
Org 源文件和 SQLite 全部七张表仍与操作前一致。

隔离进程比较三次包 require（依赖预先激活）：源码中位数 206 ms，编译中位数
182 ms。该数据仅衡量包加载，不代表完整个人 Emacs 启动时间。
本节记录本地工作树；本次新增代码未宣称完成 hosted CI。

## 2026-10-09：习惯重复与截止阶段目标

- 增加完成后间隔、固定一个／多个星期和每周 1–7 次；每天最多计一次，
  周日至周六统计，达标后停止主动呈现，下周重置而不累计未完成数量。
- 七天习惯轨迹改为日—六，规则／周进度可见；非执行日与周目标自由安排日中性显示。
- Sprint 头部展示原生 TODO + DEADLINE，保留原生进度 cookie、marker 与完成操作；
  不扩大仅有截止日期目标的执行队列准入。
- `TZ=UTC make test`：551/551，包括新增 14 个规则／截止目标测试；
  `make compile` 成功，既有编译警告仍存在；`git diff --check` 通过。
- 本地午夜上海时区完整回归的 8 个旧测试失败，在未修改 HEAD 基线中完全复现。
  它们依赖真实任务开放时段；UTC 当日下午环境完整回归通过，不在本轮修改旧测试。
- 实际运行中的 Emacs 加载／编译本轮定义，用 `/tmp` fixture 通过真实
  `org-agenda` Sprint 入口核对阶段目标、中文规则、2/3 周进度、日—六轨迹及
  `C-c r` 路由，恢复窗口并清理临时缓冲区。未修改真实 Org／SQLite 数据。
- 当前 daemon 不能连接已有 :0 或 :1 显示服务器，无法创建图形验证 frame。
  GUI 中文像素排版、主题与物理鼠标验收未完成；不将真实 Agenda 文本验证等同 GUI 验收。
- 本轮文档为 `habit-system.md`，CONTEXT 阅读地图已关联；没有建立阶段百分比计算器。

## 2026-10-09：阶段目标语义修正与周目标退役

用户明确阶段目标是活跃阶段的中／短期进度承诺，来源为 DIVE + DEADLINE。
普通 TODO 截止任务不再列为阶段目标；保留原生 [n/m] 进度与截止日期。
今天／明天 Sprint 顶部共用阶段目标，W 与主菜单 w 访问源阶段。
退役旧周目标的展示、读写接口和新周日志模板节，已有日志原文保留。

`TZ=UTC make test` 553/553；`make compile` 成功（既有警告保留）；diff 检查通过。
测试包含 CMU Deep Learning Intro [1/28]、普通 TODO 排除、双视图与 W 路由、
只读访问源标题，以及旧周目标文本在其他编辑中保留。
实际 Wayland 临时 frame 通过真实 Sprint 入口渲染并导出 PNG，确认中文标题、
CMU 阶段、原生进度及截止日期位于今日安排之前；W 路由核对成功。
fixture 位于 /tmp，未修改真实 Org 数据；临时 frame 与缓冲区已清理。
图形证据 `/tmp/workflow-stage-preview.png` 为临时验证产物，不是仓库文件。

## 2026-10-09：阶段目标在收窄源缓冲区中的定位修复

报告场景：源文件收窄到 TODO 子任务后，阶段目标行错误显示该子任务标题，
却使用父 DIVE 的截止日期。扫描通过 source-read 展开全文取得父位置，渲染时
未展开全文，goto-char 被夹到收窄起点；并非 TODO 被筛选为阶段目标。

新增临时 fixture 先在旧代码复现相同的错误标题与父截止日期；渲染改用
org-with-wide-buffer 后通过，marker 指向父 DIVE，源文件收窄范围与未修改状态保留。
完整回归 `TZ=Pacific/Honolulu make test` 554/554（选择工作时段避开既知时间敏感旧测试）。
实际 Emacs 编译并加载修复、刷新用户 Agenda，头部确认显示
CMU Deep Learning Intro [1/28] 与 2026-10-10；章节 TODO 留在今日安排。
未修改真实任务或展开用户源缓冲区。

## 2026-10-09：阶段目标紧凑样式与同行日期切换

去掉阶段目标区域标题与普通任务菱形／标签；保留既有六空格缩进与正文大小。
阶段目标复用父标题的 group-progress 渲染与 org-modern faces，仍无硬依赖。
截止提示改为剩 n 天／今天截止／逾期 n 天；按真实今天计算，剩余 3 天以内
名称与倒计时使用 error face，进度条颜色独立。悬停提示准确日期；倒计时为完整显示单元。
“安排”与日期按钮同行，不再使用今日安排／明日安排。

完整回归 `TZ=Pacific/Honolulu make test` 556/556，编译成功（既有警告保留）。
新增检查包括 3／4 天临界色、当天／逾期、准确日期 help-echo、共用进度条、
原生日期按钮及切换后倒计时保持不变。既有布局断言同步新的标题。
宽窗口实际 GUI 导出确认进度条与红色提示、同行按钮。
窄窗口初检发现倒计时拆字，已改为原子 display；该最终调整自动测试通过，
图形复验留给用户。重复临时 fixture 文件触发重新读取询问，验证客户端已停止，
按用户要求不继续桌面控制或猜测窗口。后续截图／视觉验收由用户提供。
