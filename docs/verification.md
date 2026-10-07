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
