# org-workflow

Org Workflow is an Emacs package for planning and doing work in Org, with a persistent record of commitments and daily effort. It brings task selection, Sprint planning, timers, weekly journals, an inbox, habits and a native history panel into one workflow.

Version 0.1.0 is the first extraction of an existing personal configuration. The package is prepared for a dedicated GitHub repository; it has not been submitted to or accepted by MELPA.

## Requirements

- Emacs 31.1 or newer, with SQLite support. SVG support and a graphical frame are needed for the graphical history charts.
- Org, Vulpea, Vulpea Journal, vui, Transient and Org Super Agenda. Exact minimum versions are declared in `org-workflow.el`.
- An Org notes directory and Agenda files. Task files use `project` or `area` file tags; `TODO` and `DIVE` are active states, `DONE` and `HOLD` are terminal states.

Evil and Org Modern are optional. Desktop utilities are optional integrations and are installed separately.

## Installation

Until a public repository is created, build from this checkout:

```sh
make bootstrap
make package
```

`bootstrap` downloads dependencies from GNU ELPA and MELPA into `.ci/elpa/`. The package archive is written to `dist/org-workflow-0.1.0.tar`; the version comes from the source header. In your normal Emacs, install the declared dependencies first, then use `M-x package-install-file` to select the archive.

For development, add this directory to `load-path` after installing the dependencies. Configure the paths before enabling Workflow:

```elisp
(require 'org-workflow)
(setq org-directory (expand-file-name "~/Org/notes/")
      org-workflow-directory org-directory
      org-agenda-files (list (expand-file-name "projects.org" org-directory))
      org-workflow-store-file
      (expand-file-name "org-workflow.sqlite" user-emacs-directory)
      org-workflow-clock 'org-workflow-focus-timer
      org-workflow-install-default-bindings t)
(org-workflow-mode 1)
```

Create the notes directory and your Agenda files first. Tag task files with `#+filetags: :project:` or `:area:`. Configure Vulpea's database for your notes according to its own setup; Workflow reads those notes and manages weekly journal files beneath `org-workflow-directory`. The example opts into Workflow's global bindings and Focus Timer. Both are optional: global bindings default to disabled, and the default clock backend is ordinary `org-clock`. Use `M-x customize-group RET org-workflow RET` to inspect the options.

Enabling the global minor mode installs Workflow's hooks and integrations. Loading the package alone does not start the workflow. Disable it with `(org-workflow-mode -1)`. This cancels Workflow timers and clears the Focus Timer phase; an active standard Org clock remains running and can be stopped with `org-clock-out`. Activation opens the store and performs recovery, but does not automatically import legacy journals. If upgrading legacy data, back up your sources and run `M-x org-workflow-migrate` explicitly before continuing normal work. Existing users should retain their existing notes, journal and database paths when switching from the configuration modules.

## Workflow and data

Tasks retain standard Org scheduling, priorities and clocks. `DIVE` identifies active task groups. The current model uses `A`, `B` and `C` priorities for morning, afternoon and evening availability. The package tracks commitments separately from completion: working on a committed task can satisfy a daily responsibility without marking the task done.

Org files store tasks, schedules and clocks; SQLite stores commitments, events, settled history and recovery records. The database is durable data. Back up it together with the Org files. Do not delete it to clear the interface or resolve a recovery conflict.

The native history panel reads the same persisted history as the optional web export. Its charts have keyboard date selection as well as mouse interaction. See the documents in [`docs/`](docs/) for detailed workflows, current semantics and maintenance guidance.

## Optional integrations

[`extras/`](extras/) contains the web dashboard, GNOME integration and desktop client and screenshot helpers. These are companion tools, not part of the Emacs package archive. Follow their own instructions and review paths and desktop requirements before installing them. The core package does not install a GNOME extension or desktop executable.

For screenshots, install `extras/bin/org-screenshot` and set `org-workflow-screenshot-helper` to its absolute path. The desktop clients use a user systemd Emacs service. For the optional web dashboard, set `org-workflow-web-export-file` to the companion site's `public/data/workflow-history.v1.json` and configure `org-workflow-web-open-function` to open your local site. See the [companion instructions](extras/README.md) for requirements and examples.

Personal Org files, databases, backups, caches and personal Emacs configuration are excluded from package builds. A build includes only root-level `org-workflow*.el` libraries, the license, and generated package metadata and autoloads.

## Development and verification

```sh
make bootstrap  # download declared dependencies and package-lint
make check      # compile, ERT, metadata lint, checkdoc, build and install smoke
```

`EMACS` selects the executable. `PACKAGE_USER_DIR` selects the dependency installation directory; by default it is `.ci/elpa/`. Compilation uses disposable copies in `dist/compile/` and leaves source files untouched. The installation smoke test uses a fresh directory for Workflow and activates the separately installed dependencies, without loading the user's init file or enabling the workflow.

See [the extraction verification record](docs/verification.md) for the checks actually completed and their limits. Compilation succeeds with inherited nonfatal warnings.

The GitHub Actions configuration runs these checks on Emacs 31.1. A checked-in workflow is not evidence of a completed hosted run. The checks include Checkdoc documentation checks. Compilation errors, ERT failures, package metadata issues and installation errors fail the checks. Run the checks on the exact revision you intend to publish; local success does not substitute for a hosted CI run or MELPA review.

The candidate recipe is [`recipes/org-workflow`](recipes/org-workflow). It assumes the future repository is `Kidding0204/org-workflow`; update it if the published repository differs. Before submitting, test it against the actual published repository using MELPA's package-build tooling. Local tar construction does not verify the MELPA fetcher or release tagging.

## License and maintenance

Copyright © 2026 Jinwang Dong. Licensed under GPL version 3 or, at your option, any later version; see [`LICENSE`](LICENSE). AI tools assisted with the extraction and packaging. Source headers record this assistance. The human maintainer is responsible for reviewing and maintaining the code.

Packaging references: [Emacs package format](https://www.gnu.org/software/emacs/manual/html_node/elisp/Packaging.html), [MELPA contribution requirements](https://github.com/melpa/melpa/blob/master/CONTRIBUTING.org).
