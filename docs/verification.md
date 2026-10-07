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
未安装新的 GNOME 扩展、未调用截图 Portal、未运行 GitHub hosted CI。
MELPA recipe 尚未针对公开远端用 package-build 验证，未提交或获得 MELPA 接受。
