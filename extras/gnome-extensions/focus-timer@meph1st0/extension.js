import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import St from 'gi://St';
import Clutter from 'gi://Clutter';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';

import {parseEmacsclientStatus} from './state.js';
import {planningPresentation, weekTrackStyle} from './planning.js';
import {formatWorkflowTitle, parseWorkflowStatus} from './workflow-state.js';
import {titleLayout} from './layout.js';
import {
    applyStatus,
    applyUnavailable,
    commitmentStreakText,
    dailyProgressState,
    PROGRESS_HEIGHT,
    PROGRESS_WIDTH,
    progressState,
} from './ui.js';
import {addToLeftPanel, keepFirstInRightPanel, orderedPanelActors} from './panel-placement.js';
import {
    DBUS_INTERFACE,
    DBUS_OBJECT_PATH,
    DBUS_SIGNAL,
    refreshIntervalFor,
    isServerUnavailable,
    WORKFLOW_MENU_ACTIONS,
    WORKFLOW_DBUS_INTERFACE,
    WORKFLOW_DBUS_OBJECT_PATH,
    workflowCommandArgv,
} from './sync.js';

const TIMER_STATUS_EXPRESSION = '(org-workflow-focus-timer-status-json)';
const WORKFLOW_STATUS_EXPRESSION = '(org-workflow-status-json)';
const FINISH_EXPRESSION = '(progn (org-workflow-focus-timer-finish-phase) (org-workflow-focus-timer-status-json))';
const STOP_EXPRESSION = '(progn (org-workflow-focus-timer-stop) (org-workflow-focus-timer-status-json))';

function makeProgress(styleClass) {
    const bar = new St.BoxLayout({
        style_class: `focus-timer-progress ${styleClass}`,
        width: PROGRESS_WIDTH,
        height: PROGRESS_HEIGHT,
        x_expand: false,
        y_expand: false,
        y_align: Clutter.ActorAlign.CENTER,
    });
    const fill = new St.Widget({
        style_class: `${styleClass}-fill`,
        x_expand: false,
        y_expand: false,
        height: PROGRESS_HEIGHT,
    });
    bar.add_child(fill);
    return {bar, fill};
}

export default class FocusTimerExtension extends Extension {
    enable() {
        this._enabled = true;
        this._refreshSourceId = null;
        this._refreshIntervalSeconds = null;
        this._refreshInFlight = false;
        this._refreshPending = false;
        this._refreshPending休息art = false;
        this._dbusSignalIds = [];
        this._lastError = null;
        this._lastWorkflowError = null;
        this._unavailableAttempts = 0;
        this._generation = {};
        this._timerStatus = null;
        this._workflowStatus = null;
        this._habitMenuSignature = null;
        this._layoutSignals = [];
        this._layoutIdle = null;
        this._layoutStyle = null;

        this._indicator = new PanelMenu.Button(0.0, 'Workflow：左键切换计时，右键打开菜单', false);
        this._content = new St.BoxLayout({
            style_class: 'focus-timer-content',
            x_expand: false,
            y_expand: false,
            y_align: Clutter.ActorAlign.CENTER,
            clip_to_allocation: true,
        });
        this._taskLabel = new St.Label({
            text: 'No current task',
            style_class: 'org-workflow-task-label',
            y_align: Clutter.ActorAlign.CENTER,
        });
        this._taskLabel.clutter_text.ellipsize = 3;
        this._parentLabel = new St.Label({text: '', style_class: 'org-workflow-parent-label',
            y_align: Clutter.ActorAlign.CENTER, visible: false});
        this._parentLabel.clutter_text.ellipsize = 3;

        const daily = makeProgress('org-workflow-daily');
        this._dailyProgress = daily.bar;
        this._dailyFill = daily.fill;
        this._dailyLabel = new St.Label({
            text: '0/0', style_class: 'org-workflow-daily-label',
            y_align: Clutter.ActorAlign.CENTER,
        });
        this._streakLabel = new St.Label({
            text: '🔥 0', style_class: 'org-workflow-streak-label',
            y_align: Clutter.ActorAlign.CENTER,
        });
        this._streakLabel.accessible_name = 'Commitment streak: 0 days';

        const focus = makeProgress('focus-timer-progress');
        this._progress = focus.bar;
        this._fill = focus.fill;
        this._label = new St.Label({
            text: 'F —', style_class: 'focus-timer-status-label',
            y_align: Clutter.ActorAlign.CENTER,
        });
        this._label.add_style_class_name('focus-timer-inactive');

        this._dailyGroup = new St.BoxLayout({style_class: 'workflow-action-group',
            y_align: Clutter.ActorAlign.CENTER});
        this._dailyGroup.add_child(this._dailyProgress);
        this._dailyGroup.add_child(this._dailyLabel);
        this._focusGroup = new St.BoxLayout({style_class: 'workflow-action-group',
            y_align: Clutter.ActorAlign.CENTER});
        this._focusGroup.add_child(this._progress);
        this._focusGroup.add_child(this._label);
        this._accessoryGroup = new St.BoxLayout({style_class: 'workflow-action-group',
            y_align: Clutter.ActorAlign.CENTER});
        this._separator = new St.Widget({style_class: 'workflow-accessory-separator',
            y_align: Clutter.ActorAlign.CENTER});
        this._accessoryGroup.add_child(this._separator);
        this._accessoryGroup.add_child(this._focusGroup);
        this._accessoryGroup.add_child(this._parentLabel);
        for (const actor of orderedPanelActors({dailyGroup: this._dailyGroup,
            taskLabel: this._taskLabel, accessoryGroup: this._accessoryGroup}))
            this._content.add_child(actor);
        this._indicator.add_child(this._content);
        this._rightIndicator = new PanelMenu.Button(0.0, 'Workflow：左键打开 Sprint，右键打开菜单', false);
        this._rightLabel = new St.Label({text: '', style_class: 'workflow-guidance-label', y_align: Clutter.ActorAlign.CENTER});
        this._rightLabel.clutter_text.ellipsize = 3;
        this._rightContent = new St.BoxLayout({y_align: Clutter.ActorAlign.CENTER});
        this._rightContent.add_child(this._streakLabel);
        this._rightContent.add_child(this._rightLabel);
        this._weekStrip = new St.BoxLayout({style_class: 'workflow-week-strip',
            y_align: Clutter.ActorAlign.CENTER, visible: false});
        this._weekCells = Array.from({length: 7}, () => {
            const cell = new St.BoxLayout({orientation: Clutter.Orientation.VERTICAL, style_class: 'workflow-week-cell',
                y_align: Clutter.ActorAlign.CENTER});
            const track = new St.Widget({style_class: 'workflow-week-track'});
            const unknown = new St.Label({text: '?', style_class: 'workflow-week-unknown',
                x_align: Clutter.ActorAlign.CENTER, visible: false});
            const dot = new St.Widget({style_class: 'workflow-week-today',
                x_align: Clutter.ActorAlign.CENTER, opacity: 0});
            cell.add_child(track);
            cell.add_child(unknown);
            cell.add_child(dot);
            this._weekStrip.add_child(cell);
            return {track, unknown, dot};
        });
        this._rightContent.add_child(this._weekStrip);
        this._rightIndicator.add_child(this._rightContent);
        this._rightBody = new PopupMenu.PopupMenuItem('', {reactive: false, can_focus: false});
        this._rightBody.label.clutter_text.line_wrap = true;
        this._rightBody.label.add_style_class_name('org-workflow-body');
        this._rightIndicator.menu.addMenuItem(this._rightBody);
        this._rightIndicator.menu.addAction('打开 Sprint', () => this._runWorkflowAction('agenda'));
        this._rightIndicator.menu.addAction('打开周日志', () => this._runWorkflowAction('week'));
        Main.panel.addToStatusArea(`${this.uuid}-guidance`, this._rightIndicator, 0, 'right');
        this._releaseRightPlacement = keepFirstInRightPanel(Main.panel, this._rightIndicator);
        this._bindPanelClicks(this._indicator, 'toggle');
        this._bindPanelClicks(this._rightIndicator, 'agenda');
        this._habitMenu = new PopupMenu.PopupSubMenuMenuItem('今日习惯');


        this._bodyItem = new PopupMenu.PopupMenuItem('', {
            reactive: false, can_focus: false,
        });
        this._bodyItem.label.add_style_class_name('org-workflow-body');
        this._bodyItem.label.clutter_text.line_wrap = true;

        this._indicator.menu.addAction('打开当前任务',
            () => this._runWorkflowAction('visit'));
        this._workflowMenuItem = new PopupMenu.PopupSubMenuMenuItem('任务操作');
        for (const action of WORKFLOW_MENU_ACTIONS)
            this._workflowMenuItem.menu.addAction(action.label,
                () => this._runWorkflowAction(action.id));
        this._indicator.menu.addMenuItem(this._workflowMenuItem);
        this._indicator.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem('计时'));
        this._indicator.menu.addAction('切换计时（Super+s）',
            () => this._runWorkflowAction('toggle'));
        this._indicator.menu.addAction('完成当前计时阶段',
            () => this._runCommand(FINISH_EXPRESSION));
        this._indicator.menu.addAction('停止计时',
            () => this._runCommand(STOP_EXPRESSION));
        this._indicator.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem('状态与习惯'));
        this._indicator.menu.addMenuItem(this._habitMenu);
        this._indicator.menu.addMenuItem(this._bodyItem);
        this._indicator.menu.addAction('刷新状态', () => this._refresh());
        addToLeftPanel(Main.panel, Main.sessionMode.panel.left,
            this.uuid, this._indicator);
        for (const actor of [Main.panel._centerBox, this._indicator.container])
            this._layoutSignals.push([actor, actor.connect('notify::allocation',
                () => this._queueLayout())]);

        this._subscribeToEmacsChanges();
        this._refresh({restartSchedule: true});
    }

    disable() {
        this._enabled = false;
        this._generation = null;
        this._stopRefreshTimer();
        this._unsubscribeFromEmacsChanges();
        for (const [actor, id] of this._layoutSignals)
            actor.disconnect(id);
        this._layoutSignals = [];
        if (this._layoutIdle !== null)
            GLib.source_remove(this._layoutIdle);
        this._layoutIdle = null;
        this._releaseRightPlacement?.();
        this._releaseRightPlacement = null;
        this._rightIndicator?.destroy();
        this._rightIndicator = null;
        this._indicator?.destroy();
        this._indicator = null;
        this._taskLabel = null;
        this._dailyFill = null;
        this._dailyLabel = null;
        this._streakLabel = null;
        this._label = null;
        this._fill = null;
        this._bodyItem = null;
        this._workflowMenuItem = null;
    }

    _subscribeToEmacsChanges() {
        for (const [objectPath, interfaceName] of [
            [DBUS_OBJECT_PATH, DBUS_INTERFACE],
            [WORKFLOW_DBUS_OBJECT_PATH, WORKFLOW_DBUS_INTERFACE],
        ]) {
            try {
                const id = Gio.DBus.session.signal_subscribe(
                    null, interfaceName, DBUS_SIGNAL, objectPath, null,
                    Gio.DBusSignalFlags.NONE,
                    () => this._refresh({restartSchedule: true}));
                this._dbusSignalIds.push(id);
            } catch (error) {
                console.warn(`Focus Timer: unable to subscribe to ${interfaceName}: ${error.message}`);
            }
        }
    }

    _unsubscribeFromEmacsChanges() {
        for (const id of this._dbusSignalIds)
            Gio.DBus.session.signal_unsubscribe(id);
        this._dbusSignalIds = [];
    }

    _refresh({restartSchedule = false} = {}) {
        if (!this._enabled)
            return;
        if (this._refreshInFlight) {
            this._refreshPending = true;
            this._refreshPending休息art ||= restartSchedule;
            return;
        }

        this._refreshInFlight = true;
        this._readTimer(restartSchedule);
    }

    _readTimer(restartSchedule) {
        this._runExpression(TIMER_STATUS_EXPRESSION, output => {
            const status = parseEmacsclientStatus(output);
            if (status) {
                this._timerStatus = status;
                this._setTimerStatus(status);
            } else {
                this._setTimerUnavailable('invalid Focus Timer status');
            }
            this._readWorkflow(restartSchedule);
        }, error => {
            this._setTimerUnavailable(error);
            if (isServerUnavailable(error)) {
                this._setWorkflowUnavailable(error);
                this._completeRefresh(restartSchedule);
            } else {
                this._readWorkflow(restartSchedule);
            }
        });
    }

    _readWorkflow(restartSchedule) {
        this._runExpression(WORKFLOW_STATUS_EXPRESSION, output => {
            const status = parseWorkflowStatus(output);
            if (status) {
                this._workflowStatus = status;
                this._setWorkflowStatus(status);
            } else {
                this._setWorkflowUnavailable('invalid Org Workflow status');
            }
            this._completeRefresh(restartSchedule);
        }, error => {
            this._setWorkflowUnavailable(error);
            this._completeRefresh(restartSchedule);
        });
    }

    _completeRefresh(restartSchedule) {
        if (!this._enabled)
            return;
        this._unavailableAttempts = this._timerStatus && this._workflowStatus
            ? 0 : this._unavailableAttempts + 1;
        this._syncRefreshTimer(
            this._timerStatus, this._workflowStatus, restartSchedule);
        this._refreshInFlight = false;
        this._updatePlanning();
        if (!this._enabled) {
            this._refreshPending = false;
            return;
        }
        if (this._refreshPending) {
            const restart = this._refreshPending休息art;
            this._refreshPending = false;
            this._refreshPending休息art = false;
            this._refresh({restartSchedule: restart});
        }
    }

    _updatePlanning() {
        const panel = this._workflowStatus?.panel;
        const view = planningPresentation(this._timerStatus, panel, this._workflowStatus?.resume);
        const idle = this._timerStatus?.phase === 'inactive';
        this._progress.visible = !idle;
        this._label.visible = !idle;
        this._focusGroup.visible = !idle;
        this._parentLabel.visible = idle && this._workflowStatus?.available === true &&
            Boolean(this._workflowStatus.parent);
        this._accessoryGroup.visible = !idle || this._parentLabel.visible;
        this._queueLayout();
        const days = view.days ?? [];
        this._rightLabel.set_text(view.right);
        this._rightLabel.visible = days.length === 0;
        this._weekStrip.visible = days.length > 0;
        this._weekCells.forEach(({track, unknown, dot}, index) => {
            const day = days[index];
            track.style_class = `workflow-week-track workflow-week-${day?.state ?? 'future'}`;
            track.set_style(weekTrackStyle(day));
            track.visible = day?.state !== 'unknown';
            unknown.visible = day?.state === 'unknown';
            dot.opacity = day?.today ? 255 : 0;
        });
        this._rightIndicator.accessible_name = view.right;
        this._rightIndicator.visible = Boolean(view.right);
        this._rightBody.label.set_text([view.details,
            this._workflowStatus?.resume ? `下次从这里开始：${this._workflowStatus.resume}` : ''].filter(Boolean).join('\n\n'));
        const signature = JSON.stringify(panel?.habits ?? []);
        if (signature !== this._habitMenuSignature) {
            this._habitMenuSignature = signature;
            this._habitMenu.menu.removeAll();
            (panel?.habits ?? []).forEach((habit, index) => {
                this._habitMenu.menu.addAction(`${habit.done ? '✓' : '○'} ${habit.title}`,
                    () => this._runCommand(`(org-workflow-panel-visit-habit ${JSON.stringify(habit.key)})`));
            });
        }
    }

    _queueLayout() {
        if (!this._enabled || this._layoutIdle !== null)
            return;
        this._layoutIdle = GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
            this._layoutIdle = null;
            if (this._enabled)
                this._fitTitles();
            return GLib.SOURCE_REMOVE;
        });
    }

    _fitTitles() {
        const scale = St.ThemeContext.get_for_stage(global.stage).scale_factor;
        const [centerX] = Main.panel._centerBox.get_transformed_position();
        const [ownX] = this._indicator.container.get_transformed_position();
        const available = Math.max(0, (centerX - ownX) / scale - 24);
        // Before the panel's first allocation there is no usable geometry yet.
        if (available === 0)
            return;
        const measure = actor => actor.get_preferred_width(-1)[1] / scale;
        const taskNatural = measure(this._taskLabel.clutter_text);
        const parentNatural = this._parentLabel.visible ? measure(this._parentLabel.clutter_text) : 0;
        const accessory = this._accessoryGroup.visible;
        const fixed = measure(this._dailyGroup) + (accessory ? 32 + 7 : 16) +
            (this._focusGroup.visible ? measure(this._focusGroup) : 0);
        const caps = titleLayout(available, fixed, taskNatural, parentNatural);
        const style = `${available}:${caps.task}:${caps.parent}`;
        if (style !== this._layoutStyle) {
            this._layoutStyle = style;
            this._content.set_style(`max-width: ${Math.floor(available)}px;`);
            this._taskLabel.set_style(`max-width: ${caps.task}px;`);
            this._parentLabel.set_style(`max-width: ${caps.parent}px;`);
        }
    }

    _syncRefreshTimer(timerStatus, workflowStatus, restartSchedule) {
        const seconds = refreshIntervalFor(timerStatus, workflowStatus, this._unavailableAttempts);
        if (restartSchedule || this._refreshSourceId === null ||
            this._refreshIntervalSeconds !== seconds)
            this._startRefreshTimer(seconds);
    }

    _startRefreshTimer(seconds) {
        this._stopRefreshTimer();
        this._refreshIntervalSeconds = seconds;
        this._refreshSourceId = GLib.timeout_add_seconds(
            GLib.PRIORITY_DEFAULT, seconds, () => {
                this._refresh();
                return GLib.SOURCE_CONTINUE;
            });
    }

    _stopRefreshTimer() {
        if (this._refreshSourceId !== null) {
            GLib.Source.remove(this._refreshSourceId);
            this._refreshSourceId = null;
        }
        this._refreshIntervalSeconds = null;
    }

    _bindPanelClicks(indicator, action) {
        // GNOME 51's PanelMenu owns a press gesture, independent of actor events.
        indicator._clickGesture.set_enabled(false);
        indicator.remove_action(indicator._clickGesture);
        for (const button of [1, 3]) {
            const gesture = new Clutter.ClickGesture();
            gesture.set_required_button(button);
            gesture.set_recognize_on_press(true);
            gesture.connect('recognize', () => {
                if (button === 3)
                    indicator.menu.toggle();
                else {
                    indicator.menu.close();
                    this._runWorkflowAction(action);
                }
            });
            indicator.add_action(gesture);
        }
    }

    _runCommand(expression) {
        this._runExpression(expression, () => this._refresh(), () => this._refresh());
    }

    _runWorkflowAction(actionId) {
        let argv;
        try {
            argv = workflowCommandArgv(actionId);
        } catch (error) {
            this._refresh();
            return;
        }
        this._runEmacsclient(argv, () => this._refresh(), () => this._refresh());
    }

    _runExpression(expression, onSuccess, onFailure) {
        this._runEmacsclient(['emacsclient', '--timeout=5', '--eval', expression],
            onSuccess, onFailure);
    }

    _runEmacsclient(argv, onSuccess, onFailure) {
        const generation = this._generation;
        let process;
        try {
            process = Gio.Subprocess.new(
                argv,
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE);
        } catch (error) {
            onFailure(error.message);
            return;
        }
        process.communicate_utf8_async(null, null, (subprocess, result) => {
            try {
                const [, stdout, stderr] = subprocess.communicate_utf8_finish(result);
                if (!this._enabled || this._generation !== generation)
                    return;
                if (!subprocess.get_successful()) {
                    onFailure(stderr.trim() ||
                        `emacsclient exited with status ${subprocess.get_exit_status()}`);
                    return;
                }
                onSuccess(stdout);
            } catch (error) {
                if (!this._enabled || this._generation !== generation)
                    return;
                onFailure(error.message);
            }
        });
    }

    _setTimerStatus(status) {
        this._lastError = null;
        applyStatus(this._indicator, this._label, status);
        const {width, variant} = progressState(status);
        this._fill.set_size(width, PROGRESS_HEIGHT);
        this._fill.remove_style_class_name('focus-timer-progress-break');
        this._fill.remove_style_class_name('focus-timer-progress-overtime');
        if (variant === 'break')
            this._fill.add_style_class_name('focus-timer-progress-break');
        else if (variant === 'overtime')
            this._fill.add_style_class_name('focus-timer-progress-overtime');
    }

    _setTimerUnavailable(message) {
        if (!isServerUnavailable(message) && message !== this._lastError)
            console.warn(`Focus Timer: ${message}`);
        this._lastError = message;
        this._timerStatus = null;
        applyUnavailable(this._indicator, this._label,
            isServerUnavailable(message) ? 'Waiting for Emacs' : message);
        this._fill.set_size(0, PROGRESS_HEIGHT);
    }

    _setWorkflowStatus(status) {
        this._lastWorkflowError = null;
        this._taskLabel.set_text(formatWorkflowTitle(status));
        this._parentLabel.set_text(status.parent);
        this._parentLabel.visible = this._timerStatus?.phase === 'inactive' &&
            status.available && Boolean(status.parent);
        this._bodyItem.label.set_text([status.task,
            [status.parent, status.parentProgress].filter(Boolean).join(' '),
            status.body || 'No task notes.',
            status.resume ? `下次从这里开始：${status.resume}` : ''].filter(Boolean).join('\n\n'));
        const {width, text, variant} = dailyProgressState(status);
        this._dailyFill.set_size(width, PROGRESS_HEIGHT);
        this._dailyLabel.set_text(text);
        this._dailyLabel.accessible_name = `Stage attempts: ${text}`;
        this._setCommitmentStreak(status);
        this._dailyFill.remove_style_class_name('org-workflow-daily-complete');
        if (variant === 'complete')
            this._dailyFill.add_style_class_name('org-workflow-daily-complete');
        this._updateAccessibleName();
    }

    _setWorkflowUnavailable(message) {
        this._parentLabel.visible = false;
        if (!isServerUnavailable(message) && message !== this._lastWorkflowError)
            console.warn(`Org Workflow: ${message}`);
        this._lastWorkflowError = message;
        this._workflowStatus = null;
        this._taskLabel.set_text(isServerUnavailable(message)
            ? 'Waiting for Emacs' : 'Workflow unavailable');
        this._bodyItem.label.set_text('Org Workflow is temporarily unavailable.');
        this._dailyFill.set_size(0, PROGRESS_HEIGHT);
        this._dailyLabel.set_text('0/0');
        this._dailyLabel.accessible_name = 'Stage attempts unavailable';
        this._setCommitmentStreak(null);
        this._updateAccessibleName();
    }

    _setCommitmentStreak(status) {
        const streak = status?.commitmentStreak ?? 0;
        this._streakLabel.set_text(commitmentStreakText(status));
        this._streakLabel.accessible_name =
            `Commitment streak: ${streak} ${streak === 1 ? 'day' : 'days'}`;
    }

    _updateAccessibleName() {
        const task = this._workflowStatus
            ? formatWorkflowTitle(this._workflowStatus)
            : 'Workflow unavailable';
        const timer = this._label?.text ?? 'F —';
        const streak = this._workflowStatus?.commitmentStreak ?? 0;
        this._indicator.accessible_name =
            `${task}; Commitment streak: ${streak} ${streak === 1 ? 'day' : 'days'}; Focus Timer: ${timer}`;
    }
}
