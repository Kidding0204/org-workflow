# Optional companion tools

These sources are distributed with the repository and excluded from the Emacs package archive. Install them explicitly. They use the enabled Workflow package in an existing Emacs daemon; they do not contain personal tasks or historical JSON.

## Desktop clients

The clients in `bin/` use Linux user systemd's `emacs.service` and `emacsclient`. They start that service idempotently and use `--alternate-editor=false` to avoid creating another daemon. Configure your service separately and enable Workflow in its normal init file.

Install the clients together, because they locate `emacs-systemd-client` beside themselves:

```sh
install -Dm755 bin/emacs-systemd-client "$HOME/.local/bin/emacs-systemd-client"
install -Dm755 bin/org-workflow-client "$HOME/.local/bin/org-workflow-client"
install -Dm755 bin/org-protocol-client "$HOME/.local/bin/org-protocol-client"
```

Run `~/.local/bin/org-workflow-client visit` to open the current task. Frame-aware actions reuse or create a graphical frame before dispatch; `select` creates a dedicated selection frame. Other actions use a daemon request. `org-protocol-client` passes a validated org-protocol URL into a capture frame. Browser protocol-handler registration and desktop shortcuts remain user configuration.

## GNOME

The [`focus-timer@meph1st0`](gnome-extensions/focus-timer@meph1st0/README.md) extension targets GNOME Shell 50/51. Its UUID and D-Bus names are retained for protocol compatibility. Install the desktop clients at `~/.local/bin/` before using its actions. It calls canonical `org-workflow-` functions for timer and task status. Follow its bundle instructions; the extension is not installed by `package.el`.

## 截图

截图工具需要 Python 3、PyGObject（`gi`）、桌面截图 Portal，以及通知工具 `notify-send`。
Wayland 剪贴板收集另需 `wl-paste`。安装后在 Emacs 配置辅助程序的绝对路径：

```sh
install -Dm755 bin/org-screenshot "$HOME/.local/bin/org-screenshot"
install -Dm755 bin/org-screenshot-client "$HOME/.local/bin/org-screenshot-client"
```

```elisp
(setq org-workflow-screenshot-helper
      (expand-file-name "~/.local/bin/org-screenshot"))
```

通过 `M-x org-workflow-screenshot-capture` 或桌面快捷键调用 `org-screenshot-client`。
截图追加到当前任务；取消截图不修改任务。详见 [截图指南](../docs/screenshot-inbox.md)。

## Web history

[`web/`](web/README.md) contains the React/Vite source only. Configure an export path into its `public/data/` directory and run the site yourself. The core package provides `org-workflow-web-open-function` for your browser or local-server launcher; no Ghostty/Fish launcher is imposed.

## Checks

```sh
bash test/emacs-systemd-client-test.sh
bash test/org-workflow-client-test.sh
bash test/org-protocol-client-test.sh
```

These use stub executables to verify client arguments. GNOME source tests verify JavaScript contracts. They do not verify a running desktop, a real daemon, portal access or the final installed extension.
