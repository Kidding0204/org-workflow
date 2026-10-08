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
