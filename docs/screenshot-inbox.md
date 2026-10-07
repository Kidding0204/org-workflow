# 当前任务截图收集

[文档入口](README.md)（文中的默认快捷键需设置 `org-workflow-install-default-bindings` 为 t） · [任务与历史模型](workflow-architecture.md)

先安装 [截图辅助工具](../extras/README.md#截图)。可自行将 **Super + Ctrl + Print** 绑定到 `org-screenshot-client`。

按下后在系统截图界面选择区域并确认，图片链接会通过 Org Capture 自动追加到
Org Workflow 当前聚焦任务的正文末尾并保存，不弹出笔记编辑窗口。
如果任务含子任务，链接放在其正文末尾、首个子标题之前，不会落入子任务。

图片保存在任务所在 Org 文件旁的 `doc/images/`，目录不存在时自动创建：

```text
项目目录/
  project.org
  doc/images/20261004-143000-a1b2c3d4.png
```

正文中的链接使用 `[[file:doc/images/…png]]`。不同截图使用独立文件名。
收集目标在开始截图时确定；没有当前任务、任务文件只读或不是本地文件时，
先报错，不启动截图。取消系统截图不会追加链接。

Emacs 内也可按 `C-c o S`，或 `C-c o c` 后选择大写 `S`。
`C-u C-c o S` 收集已经复制到 Wayland 剪贴板的 PNG。
用 `org-toggle-inline-images` 显示图片。

桌面入口为 `extras/bin/org-screenshot-client`，通过现有的服务启动入口调用 Emacs，
不新建窗口。使用系统截图 Portal，首次调用可能需要允许截图。
如果图片已保存而后续 Org 写入失败，图片保留在 `doc/images/`，可以手动找回。
Org Capture 会保存任务所在文件，包括其中已有的未保存编辑。
