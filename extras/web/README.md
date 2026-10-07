# Workflow 网页历史快照

[文档入口](../../docs/README.md) · [任务与历史模型](../../docs/workflow-architecture.md)

这是可选的只读网页：展示已结束日期，不控制当前任务或 Focus Timer，也不写 Org 或 SQLite。
原生 [历史面板](../../docs/workflow-history-panel.md) 直接读取后端，不依赖 JSON。
仓库不携带个人历史快照；第一次使用前需要导出自己的数据。

## 导出与运行

在 Emacs 中设置导出路径，指向此网页源码所在目录：

```elisp
(setq org-workflow-web-export-file
      "/absolute/path/to/org-workflow/extras/web/public/data/workflow-history.v1.json")
(setq org-workflow-web-open-function
      (lambda () (browse-url "http://localhost:5173")))
```

启用 Workflow 后初始化导出一次，成功的历史结算再次触发导出。
手动更新：`M-x org-workflow-web-export-history`，或：

```sh
emacsclient --eval '(org-workflow-web-export-history)'
```

在 `extras/web/` 执行：

```sh
npm ci
npm run dev
npm test
npm run build
```

启动本地服务器后，`M-x org-workflow-web-open` 先导出，再调用用户配置的打开函数。
构建产生静态 bundle；Emacs 离线时可以展示最后一次有效快照。
导出验证失败保留旧快照；不能假定浏览器展示的数据自动更新到最新日期。
`node_modules/`、`dist/` 和 `public/data/` 不纳入 Git 或 Emacs 包。
历史 JSON 包含个人任务及投入信息，自行决定是否发布；默认仅在本地使用。

## 数据语义

网页读取 `public/data/workflow-history.v1.json`，使用 `org-workflow-history` schema v1。
热力图只依据 `focusTotalMinutes`。`met` 延续承诺 streak，`unmet`、`untouch` 和 missing 中断。
missing 不等于零投入或没有承诺；未知习惯工时不能推算为零。
每日兑现与实际完成分开，详见 [DIVE 与每日尝试](../../docs/dive-and-daily-attempts.md)。
前端验证 schema/version，只展示现有字段，不自行解析 Org 或重新解释承诺。
