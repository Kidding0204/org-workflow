# Focus Timer GNOME Shell extension

This GNOME Shell 50/51 extension displays the current Org Workflow task, daily
commitment progress, commitment streak, and Emacs Focus Timer in the top bar.
Emacs remains the only state source: the extension runs fixed-argument
`emacsclient --eval` commands, and neither reads Org files nor creates tasks.

The stage bar counts both commitment and added tasks with a valid focus record
on that day, or an actually completed goal. Its full-bar feedback acknowledges
daily attempts; unfinished tasks remain unfinished and can still be selected.
The commitment streak uses the same daily-attempt rule for commitment tasks.

The title-bar menu keeps **Open in Emacs** as a direct action and groups the
desktop workflow commands under **Workflow Actions**.  Both the menu and GNOME
shortcuts call `extras/bin/org-workflow-client`.  For frame-aware actions the bridge
first runs a no-wait client without `--eval`, leaving a persistent graphical
frame, and only then dispatches the action through a second client request.
For `visit`, `step`, and `prerequisite`, an existing graphical frame is reused; closing a newly created client frame
leaves the daemon running.

`extras/bin/emacs-systemd-client` is the shared daemon boundary.  It starts
`emacs.service` idempotently and connects with `--alternate-editor=false`, so
desktop clients never create a second daemon outside systemd ownership.

Use the same bridge from a terminal when a visible frame is required:

```sh
~/.local/bin/org-workflow-client visit
```

## Choose the current task

In Emacs, use `C-c o t` (`M-x org-workflow-target-select`).  The completion selector
lists today's full queue first, followed by unfinished task leaves directly
under a DIVE heading outside that queue. DIVE is an unfinished TODO state that
opens its direct task children; it is not inherited like the former CURR tag.
HOLD subtrees are excluded.
Groups show category/direct parent; candidate text includes TODO state, priority,
and task tags, all available for filtering.

The GNOME shortcut **Super+Shift+s** runs:

```sh
~/.local/bin/org-workflow-client select
```

Unlike `visit`, `select` always creates a dedicated minibuffer-only graphical
frame and queues the interaction so status clients remain responsive.  The
frame closes automatically after selection, cancellation, or an error.

Selection overrides the current target for this daemon session and day without
rewriting schedules or priorities.  It survives refreshes and ends when the task
becomes ineligible, changes TODO state, or is explicitly deferred.  Switching
away from a timed current task stops its interval normally; selection does not
start a new timer.  Use **Super+s** to start timing the selected task.

## Source and installation

The UUID is `org-workflow-focus-timer@meph1st0`.  Keep this directory in the package
source repository; install a bundle rather than editing the copied
user-extension directory.

```sh
cd extras/gnome-extensions/focus-timer@meph1st0
mkdir -p /tmp/focus-timer-extension
gnome-extensions pack --force --out-dir /tmp/focus-timer-extension --extra-source=state.js --extra-source=workflow-state.js --extra-source=ui.js --extra-source=panel-placement.js --extra-source=layout.js --extra-source=sync.js --extra-source=planning.js .
gnome-extensions install --force /tmp/focus-timer-extension/focus-timer@meph1st0.shell-extension.zip
```

On GNOME Shell 50/51 Wayland sessions, newly installed extension directories
are discovered after the next login.  Enable it then with:

```sh
gnome-extensions enable org-workflow-focus-timer@meph1st0
```

Run the contract tests with:

```sh
gjs -m tests/state.test.js
gjs -m tests/workflow-state.test.js
gjs -m tests/ui.test.js
gjs -m tests/panel-placement.test.js
gjs -m tests/sync.test.js
gjs -m tests/startup.test.js
gjs -m tests/extension-contract.test.js
bash ../../test/emacs-systemd-client-test.sh
bash ../../test/org-workflow-client-test.sh
```

## Immediate state refresh

After a Focus Timer phase change or deadline, Emacs broadcasts an empty
session D-Bus `io.github.meph1st0.FocusTimer.Changed` signal.  The extension
then rereads `org-workflow-focus-timer-status-json` and restarts its minute-based refresh
cadence.  The signal contains no timer state; Emacs remains authoritative.

## Waiting for Emacs

Status reads wait at most five seconds. While the server socket is unavailable,
the panel displays “Waiting for Emacs” without logging expected startup errors
or issuing a second, redundant Workflow read. Recovery polling backs off through
5, 10, 20, 40 and 60 seconds, resets after both status reads succeed, and can be
interrupted by a state-change signal or manual Refresh. Other backend errors
remain visible and repeated identical errors are logged only once per component.
Callbacks from a disabled extension cannot update a later enabled instance.

## Planning display (version 10)

Emacs provides `panel` (opening hint, started-today fact, seven daily investment
indicators and habit references) and `resume` alongside the existing status.
The extension does not compute business dates or write workflow facts.
Idle timer space shows habits; focus and break keep the timer. The right side
shows the seven-day investment strip during focus/break cycles. When inactive,
it shows the current task resume cue, falling back to the opening hint.
The persisted first-focus marker no longer controls this selection (version 13).
Missing data displays a dash/question mark, distinct from an unrecorded day.
Clicking a habit only visits it in an existing Emacs frame.

Installed JavaScript may remain cached in a running Wayland Shell even after
disable/enable. Log out and back in to load an updated bundle; no automatic
logout or Shell restart is attempted.

The week uses seven equal tracks: green for completed days,
outlined for incomplete days, dim lines for future days, and a question mark for
unknown data. An independent dot marks `panel.today`, supplied by Emacs rather
than inferred from the desktop clock. Weekday/date descriptions remain in the
menu and accessible label. Guidance uses natural width up to 440px, preserving
the Shell's native hover background.

Version 12 fixes GNOME 51 startup by using `Clutter.Orientation.VERTICAL` on
`St.BoxLayout`. The removed `vertical` property caused version 11 to fail during
`enable()`. In addition to the pure tests, validate constructor properties
against the installed native libraries (Fedora GNOME 51 paths shown):

```sh
GI_TYPELIB_PATH=/usr/lib64/gnome-shell:/usr/lib64/mutter-51 \
LD_LIBRARY_PATH=/usr/lib64/gnome-shell:/usr/lib64/mutter-51 \
gjs -m tests/native-properties.js
```

This check loads actual property metadata without constructing actors or
requiring a display. It does not replace verification after Shell loads the
new extension version.

Version 14 places the commitment streak beside the guidance in the right panel,
between the central date and the input-method/tray indicators. This group stays
first in the right panel even when tray extensions load later. The left task
area retains daily progress and the focus timer.

Version 15 uses Chinese menus with task actions, timer controls, and status/habits
sections. Left-click the task indicator to invoke the same `toggle` action as
Super+s; right-click either indicator for its menu. Left-click the streak/guidance
indicator to open Sprint Agenda. Agenda and weekly journal actions use the frame
bridge, reusing a graphical frame or creating one when none exists.

Version 16 replaces PanelMenu's default click gesture with separate primary and
secondary button gestures on GNOME 51, avoiding nullable captured-event sources.

Version 17 separates stage progress, the current title, and habit/timer into
three groups. Titles use natural widths capped at 320/160 logical pixels;
secondary habit text shrinks first and becomes a count on narrow panels. The
current title no longer includes project context, which remains in the menu.
Seven-day tracks now represent fulfilled commitments; on days with no
commitments, retained focus or actual completion (including habits) qualifies.
Partial commitment fulfillment does not light the day. Past dates read sealed
snapshots only, with missing snapshots shown as unknown. Leave does not count
as achievement or override a complete/unknown day.

Version 18 restores the immediate parent as a separate dim 100px field, without
project statistics. Week tracks preserve achievement hues (green/gray/purple)
and vary intensity continuously over 0–600 recorded minutes, saturating at ten
hours. Menus show exact hours/minutes. Today sums direct task and habit clocks;
past days use sealed total time without rewriting history. Missing time is not
treated as zero; future/unknown dates receive no time shading.

Version 19 replaces the idle habit slot after the separator with the compact
parent label. Focus/rest retains the timer in that slot. Habits are available
only through the existing menu; their tracking and completion rules do not change.

Version 20 lets the idle parent use its natural width. When space runs short,
the parent shrinks to 80px before the task shrinks. Extreme widths can reduce
both further to keep the central clock clear. The task's existing 320px cap stays.
