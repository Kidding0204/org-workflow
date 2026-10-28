# Focus Timer GNOME Shell extension

This GNOME Shell 50/51 extension displays the current Org Workflow task, daily
commitment progress, commitment streak, and Emacs Focus Timer in the top bar.
Emacs remains the only state source: the extension runs fixed-argument
`emacsclient --eval` commands, and neither reads Org files nor creates tasks.

The left daily bar overlays two independent measures: solid green shows completed
commitments, and pale diagonal hatching shows recorded investment toward the daily
minimum. Counts and actual minutes remain visible beside it. Meeting either daily
floor never fills the other measure. Historical facts and task state are unchanged.

The left right-click popup uses a Tasklane-inspired dark rounded surface. Its
summary shows only the first three lines of the current item's body. Each source
line occupies one ellipsized row; an additional ellipsis marks omitted body lines.
Use **打开** to read the full source. **完成** still applies to the current item.
The **任务** tab lists today's full ordered task stack directly, marking the current
item. Clicking another row selects that source through the same transition used
by the Emacs selector: stop previous execution normally, never auto-start a timer.
Duplicate titles use distinct source keys; stale/completed rows are revalidated
before selection. **选择任务** also offers the existing wider Emacs selector.
The action row is **打开 / 完成 / 取消 / 跳过 / 补记**. **打开**, **取消** and
**补记** retain the full accessible names **打开任务**, **取消计时** and **补记番茄钟**.
**跳过** sits immediately left of **补记** on the right: it skips only today's
occurrence for a current habit, or reuses **移至晚间** for an ordinary task.
It follows the current item independently of the selected tab or pending reminders,
and is disabled without a current item. The habit page has no separate skip row. **操作** is a third tab beside
**任务 / 习惯**, with the existing task-planning actions. The default tab remains
**任务**; refresh preserves the selected tab. Task-only actions are disabled for habits.
Long task lists scroll. No timer or task state
is stored in the popup. The right popup and panel gestures are unchanged.

Both the menu and GNOME shortcuts call `bin/org-workflow-client`.  For frame-aware actions the bridge
first runs a no-wait client without `--eval`, leaving a persistent graphical
frame, and only then dispatches the action through a second client request.
For `visit`, `step`, and `prerequisite`, an existing graphical frame is reused; closing a newly created client frame
leaves the daemon running.

`bin/emacs-systemd-client` is the shared daemon boundary.  It starts
`emacs.service` idempotently and connects with `--alternate-editor=false`, so
desktop clients never create a second daemon outside systemd ownership.

Use the same bridge from a terminal when a visible frame is required:

```sh
~/.config/emacs/bin/org-workflow-client visit
```

## Choose the current task

In Emacs, use `C-c o t` (`M-x my/org-target-select`).  The Vertico selector
lists today's full queue first, followed by unfinished task leaves directly
under a DIVE heading outside that queue. DIVE is an unfinished TODO state that
opens its direct task children; it is not inherited like the former CURR tag.
HOLD subtrees are excluded.
Groups show category/direct parent; candidate text includes TODO state, priority,
and task tags, all available for filtering.

The GNOME shortcut **Super+Shift+s** runs:

```sh
~/.config/emacs/bin/org-workflow-client select
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

The UUID is `focus-timer@meph1st0`.  Keep this directory in the Emacs
configuration repository; install a bundle rather than editing the copied
user-extension directory.

```sh
cd /home/meph1st0/.config/emacs/user-lisp/org-workflow/extras/gnome-extensions/focus-timer@meph1st0
mkdir -p /tmp/focus-timer-extension
gnome-extensions pack --force --out-dir /tmp/focus-timer-extension --extra-source=state.js --extra-source=workflow-state.js --extra-source=ui.js --extra-source=panel-placement.js --extra-source=layout.js --extra-source=sync.js --extra-source=planning.js .
gnome-extensions install --force /tmp/focus-timer-extension/focus-timer@meph1st0.shell-extension.zip
```

On GNOME Shell 50/51 Wayland sessions, newly installed extension directories
are discovered after the next login.  Enable it then with:

```sh
gnome-extensions enable focus-timer@meph1st0
```

Run the contract tests with:

```sh
gjs -m tests/state.test.js
gjs -m tests/workflow-state.test.js
gjs -m tests/ui.test.js
gjs -m tests/menu.test.js
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
project statistics. Week tracks preserve achievement hues (green/gray/amber)
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

Version 21 calls `org-workflow-focus-timer-status-json`,
`org-workflow-focus-timer-finish-phase` and `org-workflow-focus-timer-stop`
directly. Personal Emacs configuration no longer provides the old name aliases.
After installing this update, log out and log back in before restarting Emacs:
GNOME Shell caches the loaded extension module, so disabling/enabling cannot
activate changed JavaScript. See the [GNOME extension debugging guide](https://gjs.guide/extensions/development/debugging.html#reloading-extensions).
The current Emacs process may retain the three old definitions until the old
GNOME session ends; they are absent from saved configuration.

## Habit reminders (v22)

Configure work windows with `org-workflow-work-periods` in use-package, and
habit placement/reminder clocks with `org-workflow-habits-configure` in Emacs.
Emacs delivers one notification per habit/day and stores the latest reminder.
The title shows that habit only when the timer is inactive and no Org clock
runs; focus/breaks preserve their actual task. New reminders overwrite older
ones. Use the menu's “跳过当前习惯（仅今天）” to dismiss for today without completing.
Start/toggle/visit/complete target the displayed habit. After skip or completion
older reminders do not resurface. Reloading Shell does not repeat notifications.
Updated JS needs a new GNOME Wayland login; installing files alone does not
prove the live Shell loaded v22.

## Simplified context menu

Left click and Super+s switch timer state. Each successful toggle plays the
short Freedesktop `audio-volume-change` sound at -12 dB through the same
asynchronous player used for deadline reminders. Customize
`org-workflow-focus-timer-toggle-sound-event` in Emacs to choose another event,
or set it to `nil` for silence. Failed actions and status refreshes stay silent. The task submenu offers adding a
step or prerequisite and deferring a task or group. Direct actions offer
completion, cancellation (discard the active interval) and recording a past
Pomodoro ending now on the shared current item. Recording requires an inactive
timer and Org clock. Adding a step uses the existing operation that moves the
parent task's recorded effort to a named TODO child. Low-level finish and stop
commands remain available in Emacs for explicit timing control.

## Direct menu actions

The left menu offers opening the current item, completing the current task,
cancelling timing and recording a past Pomodoro before the task submenu.
Habits appear directly under the status/habits separator: activate an unfinished
row to make it the current item; activate that current habit again to restore
the ordinary task queue. The selected row shows an arrow. Completion stays in
the direct completion action; completed rows show a check and are disabled. The right menu opens the native long-term history panel or weekly
journal. Left click on the right indicator still opens Sprint.

Week indicators use a compact translucent rounded backing, soft state fills
and a warm underline for today. The existing green/gray/amber achievement
colors and continuous recorded-time intensity remain unchanged in meaning.

### Left popup acceptance

After installing and starting a new Shell session, right-click the left indicator.
Check task/习惯 tab switching, three-line body preview, long Chinese lines and scrolling task lists, task open/complete,
habit selection and today's skip, and the two timer tools. Check keyboard focus and
Escape under your display scaling. Local GJS tests verify presentation and action
routing; native Shell layout and pointer behavior still require this manual check.

Operation availability is applied to each native menu item individually. GNOME's
section sensitivity signal can stop after the first item returns true, leaving
later rows disabled on recovery. The menu test uses GJS signals to cover both
disconnected → task and habit → task recovery for every operation.

## Combined daily progress (v27)

One left-hand track shows solid commitment completion and diagonal investment
hatching. Both lengths cap at 100%; the label retains overtime minutes. For
example, `1/5 · 86/60m` has 20% solid fill and full-width hatching. With an older
daemon, the bar retains its original stage progress and adds no invented time.

The idle right indicator always shows the task resume cue, falling back to the
opening hint. Its compact rounded surface uses a small arrow and one ellipsized
line; the right-click menu preserves the full text. Focus/break still show the
week strip. The old idle-display switch has been retired; its schema is retained
only for compatibility and saved values no longer affect presentation.
On Wayland, installed JavaScript takes effect at the next login. No Emacs restart
or business-data migration is needed.


## Work-period ring (v28)

The 18px ring before the left daily bar shows elapsed wall-clock time in the current
work window, clockwise from twelve o'clock. Morning uses soft blue, afternoon warm
orange, and evening lavender. The full faint track shares the period's color; the
bright arc indicates elapsed time. No extra panel text is added.

`org-workflow-work-periods` remains the only schedule: Emacs sends `workPeriod`
with name and local-day start/end Unix timestamps. The ring reuses existing status
refreshes; it adds no timer or Org scanning. Meal/rest gaps retain the previous full
ring, the next start resets it, and before morning it is neutral. Old/unavailable
backends show a neutral ring. Palette and drawing live in `ui.js` (`PERIODS`,
`drawPeriodProgress`); the actor size is in `extension.js`.

The daily investment target is independent: set `org-workflow-daily-minimum-minutes`
in the host's `config/org-workflow-config.el` (240 minutes = 4 hours). The value is
recorded once per day; later configuration changes affect the next unrecorded day,
without rewriting past daily records. The present adjustment explicitly updates
only today's stored threshold as well.

Run `gjs -m tests/period.test.js` for boundary/palette and real Cairo drawing checks.
On Wayland install the bundle above, then log out and back in when convenient to
load the new JavaScript. Re-enabling alone can retain the already imported module.
