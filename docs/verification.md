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

## 2026-10-09：习惯完成后桌面状态刷新触发 Org parser 警告

用户警告栈为 status-json → history-progress → responsibilities → history--tasks →
org-map-entries → Org element cache，报 Invalid search bound。
旧 history--tasks 直接 find-file-noselect 并用缓存扫描普通任务；改为复用 source-read，
局部禁用缓存、保留未保存文本／point／收窄范围，并避免访问原本关闭的后台文件。
不全局关闭缓存，不抑制警告，不变更 Org／SQLite 历史事实。

两个新增回归检查：注入启用缓存时的同类扫描错误，仍读到未保存的任务及正确 CLOCK，
排除习惯；原本关闭的源文件读取完成事实后仍关闭，且不运行 UI hooks。
完整 `TZ=Asia/Shanghai make test` 558/558；编译成功（既有警告保留），diff 检查通过。
实际 Emacs 已编译加载，status-json 返回正常；只读查询原警告日期 2026-10-06，
捕获到的 Org parser 警告为 0。未执行真实习惯完成，也未操作桌面；快捷键／右键
实际完成入口由用户日常使用复验。

## 2026-10-10：全天可选与统一任务捕获源

Sprint 全天可选区聚合自由习惯、未安排 Inbox 项、每个直接 DIVE 父组最前两项，
原文顺序；不要求启动专注，也不自动生成承诺或改变执行选择。
原生 marker、归类、安排／撤销仍可用，已安排项不重复显示。新 capture t/p/L 和
时段 I 创建都写 projects.org/Inbox；新周日志仅随记和周回顾。
日常收集查询只读 projects，不再查询旧周日志 Vulpea 索引。

完整 `TZ=Asia/Shanghai make test` 562/562；编译成功（既有警告保留），diff 检查通过。
新增验证涵盖跨周统一捕获、直接子项与嵌套内容、周模板、全天可选排序与分组限额、
完成不启动计时。既有分栏、安排／撤销、拖动及捕获协议回归通过。

用户授权的数据迁移：52 个完整任务子树（28 TODO、24 DONE）从旧 inbox.org 与五份周日志
迁到 projects.org 一级 Inbox；其中有三个已安排任务和一个带 ID／承诺的任务。
先校验所有文件哈希和现场干净缓冲区、prepared/applied 操作数 0，再备份；先持久化
目标并校验完整子树，随后移除来源子树，逐文件校验最终哈希。保留日期、ID、CLOCK、
安排和正文；旧 SEED 笔记及随记／回顾不动。目标原前缀逐字保留。
备份与哈希清单在宿主 var/backups/unified-inbox-20261010-181330/，不提交用户数据。
实际 Emacs 干净源缓冲区刷新、ID 定位及 Vulpea 索引更新，加载本轮定义并安装新捕获模板，
确认统一 Inbox 未完成 28 项、移动 ID 可定位到新文件。未操作桌面或完成真实任务；
视觉验收交由用户。

## 2026-10-10：原生完成后的光标定位

原先 org-agenda-change-all-lines 队列保存完成任务的源 marker，post-command 刷新后
再次 goto-task，因此跟随条目进入今日已完成。现在仅对 Sprint 的原生 TODO 完成操作
预先记录下一项可见未完成任务（无下一项则上一项），完成后以它作为刷新定位目标。
无剩余任务时以原行附近定位，并限制在完成区域之前。普通刷新、改期、优先级和普通
非 Sprint Agenda 不改变行为。

仅运行相关选择器，共 7/7：新增下一项／最后一项／唯一任务定位测试，以及现有
native-edit、双栏 redo/filter、native-plan-undo 回归。未跑全量测试，未执行真实任务完成。

## 2026-10-10：Inbox 日终自动归档

自动入口接在 history-catch-up 所有旧日结算成功之后；复用现有午夜定时器与启动补结算，
不增加第二套定时器。失败结算不清理。只处理 projects.org/Inbox 的直属 DONE，
尊重 CLOSED 截止日、Org 原生归档位置和完整子树；更新 ID 定位。
未保存／外部改变的源和档案暂缓；目标先保存，源后保存。目标写入失败恢复源缓冲区；
源写入失败时档案已有完整副本，保留未保存源编辑供恢复，不伪装成成功。

只跑相关选择器：8/8（六个归档测试、两个统一捕获／查询测试）。
覆盖真实原生归档、CLOCK／属性／ID 保留、当天未结算项排除、重复运行、dirty source／target、
两种保存失败，以及全部日结顺序与结算失败不归档。未跑全量测试。
运行时只加载函数并确认既有午夜 timer，不立即调用 catch-up 或归档真实数据。

## 2026-10-13：状态查询与历史补结算性能

- 空任务事实不再被当成尚未读取；10 条当天未兑现承诺的进度计算仅扫描一次。
- `status-json` 内共享任务事实及进度，缓存随请求结束释放；错误不缓存，下一次请求重新读取。
- 新建和已有 SQLite 库在打开时获得 `events(id)` 索引；临时旧库重开测试确认查询使用索引且 `quick_check=ok`。
- 补结算一次读取兑现和生命周期事件，按到期日推进候选集合；365 个已结算日、交替使用投入兑现和 DONE 事件的测试，兑现检查不超过 365 次。旧 CLOCK 回填、更早投入、乱序／重开事件和失败重试保留。
- GNOME 动作期间的 Changed／轮询合并，成功、失败及并发动作结束后读取最终状态；读取期间的新变化继续保留。不能将这个优化描述为所有桌面动作固定减少一半延迟。

验证：`make test` 共 624 项，623 通过；唯一失败是既有的
`workflow-leave-panel-distinguishes-completion-leave-and-unknown`，该测试仍将
2026-09-16 当成周数组索引 2，而当前周日起点对应索引 3。已从修改前 HEAD
提取到独立 `/tmp` 目录，以同一依赖运行该单项并复现相同失败，本轮未修改它。
`make compile checkdoc` 成功，Checkdoc 0 警告，编译仍有非致命警告。
GNOME 目录的 10 个 `tests/*.test.js` 均经 `gjs -m` 通过，包含新增动作刷新合并测试。

性能对照使用独立临时 Org／SQLite：200 个标题、11 条当天未兑现承诺；每次清空
面板缓存、GC 阈值固定为 64 MiB，各运行三次。修改前源码状态查询为
669／422／424 ms，修改后为 187／74／73 ms，中位数约下降 83%。
返回 JSON 的 SHA256 完全一致；编译后代码也返回同一 JSON，三次为
187／70／72 ms。这是受控数据基准，不是当前桌面会话端到端提速。

未修改真实 Org 数据或为真实数据库建索引，未热加载 Emacs、部署 GNOME 或注销会话。
包更新由宿主 User Lisp 在后续启动处理；数据库索引在新版重新打开库后生效。
GNOME 配套源码需另行安装并进入新 Shell 会话，尚未完成实际桌面验收。
