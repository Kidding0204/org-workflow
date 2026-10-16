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
import {formatWorkflowTitle, parseWorkflowStatus, currentHabitReminder, workflowTitleState} from './workflow-state.js';
import {titleLayout} from './layout.js';
import {
    leftMenuPresentation,
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
        this._actionsInFlight = 0;
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
        this._taskMenuSignature = null;
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
        this._rightIndicator.menu.addAction('打开长期状态追踪', () => this._runWorkflowAction('history'));
        this._rightIndicator.menu.addAction('打开周日志', () => this._runWorkflowAction('week'));
        Main.panel.addToStatusArea(`${this.uuid}-guidance`, this._rightIndicator, 0, 'right');
        this._releaseRightPlacement = keepFirstInRightPanel(Main.panel, this._rightIndicator);
        this._bindPanelClicks(this._indicator, 'toggle');
        this._bindPanelClicks(this._rightIndicator, 'agenda');
        this._buildLeftMenu();
        addToLeftPanel(Main.panel, Main.sessionMode.panel.left,
            this.uuid, this._indicator);
        for (const actor of [Main.panel._centerBox, this._indicator.container])
            this._layoutSignals.push([actor, actor.connect('notify::allocation',
                () => this._queueLayout())]);

        this._subscribeToEmacsChanges();
        this._refresh({restartSchedule: true});
    }

    _buildLeftMenu() {
        const menu = this._indicator.menu;
        menu.actor.add_style_class_name('workflow-task-menu');
        const row = style => {
            const item = new PopupMenu.PopupBaseMenuItem({reactive: false, can_focus: false});
            item.add_style_class_name(style);
            return item;
        };
        const label = (style, wrap = false) => {
            const actor = new St.Label({style_class: style, x_expand: true});
            actor.clutter_text.line_wrap = wrap;
            if (wrap)
                actor.clutter_text.ellipsize = 0;
            return actor;
        };
        const button = (text, action, style = '') => {
            const actor = new St.Button({label: text, style_class: `workflow-menu-button ${style}`,
                can_focus: true, reactive: true, y_align: Clutter.ActorAlign.CENTER});
            actor.connect('clicked', action);
            return actor;
        };
        const run = action => {
            menu.close();
            this._runWorkflowAction(action);
        };
        const header = row('workflow-menu-header');
        header.add_child(new St.Label({text: 'Org Workflow', x_expand: true,
            style_class: 'workflow-menu-brand'}));
        const refresh = new St.Button({style_class: 'workflow-menu-icon', can_focus: true, reactive: true,
            accessible_name: '刷新状态'});
        refresh.set_child(new St.Icon({icon_name: 'view-refresh-symbolic', icon_size: 16}));
        refresh.connect('clicked', () => this._refresh());
        header.add_child(refresh);
        menu.addMenuItem(header);

        this._menuSummary = row('workflow-menu-summary');
        const summaryBox = new St.BoxLayout({orientation: Clutter.Orientation.VERTICAL, x_expand: true});
        this._menuPreview = Array.from({length: 3}, () => {
            const line = label('workflow-menu-preview');
            line.clutter_text.ellipsize = 3;
            summaryBox.add_child(line);
            return line;
        });
        this._menuSummary.add_child(summaryBox);
        menu.addMenuItem(this._menuSummary);
        const actions = row('workflow-menu-summary-actions');
        this._menuVisit = button('打开任务', () => run('visit'));
        this._menuComplete = button('完成', () => run('complete'), 'workflow-menu-primary');
        actions.add_child(this._menuVisit);
        actions.add_child(this._menuComplete);
        menu.addMenuItem(actions);

        const tabs = row('workflow-menu-tabs');
        this._menuTabs = {};
        for (const [id, text] of [['task', '任务'], ['habit', '习惯']]) {
            const tab = button(text, () => this._selectMenuTab(id), 'workflow-menu-tab');
            tab.x_expand = true;
            tab.toggle_mode = true;
            this._menuTabs[id] = tab;
            tabs.add_child(tab);
        }
        menu.addMenuItem(tabs);
        this._taskPage = new PopupMenu.PopupMenuSection();
        this._taskEmpty = new PopupMenu.PopupMenuItem('暂无今日任务', {reactive: false, can_focus: false});
        this._taskPage.addMenuItem(this._taskEmpty);
        this._taskMenu = new PopupMenu.PopupMenuSection();
        // Keep the native section's item registration and lifetime, with a bounded viewport.
        const taskScroll = new St.ScrollView({style_class: 'workflow-menu-task-scroll', x_expand: true});
        taskScroll.set_policy(St.PolicyType.NEVER, St.PolicyType.AUTOMATIC);
        taskScroll.set_child(this._taskMenu.box);
        this._taskMenu.actor = taskScroll;
        taskScroll._delegate = this._taskMenu;
        this._taskPage.addMenuItem(this._taskMenu);
        this._taskPage.addAction('＋ 选择任务…', () => this._runWorkflowAction('select'));
        this._workflowMenuItem = new PopupMenu.PopupSubMenuMenuItem('更多操作');
        for (const action of WORKFLOW_MENU_ACTIONS)
            this._workflowMenuItem.menu.addAction(action.label,
                () => this._runWorkflowAction(action.id));
        this._taskPage.addMenuItem(this._workflowMenuItem);
        menu.addMenuItem(this._taskPage);

        this._habitPage = new PopupMenu.PopupMenuSection();
        this._habitEmpty = new PopupMenu.PopupMenuItem('暂无今日习惯', {reactive: false, can_focus: false});
        this._habitPage.addMenuItem(this._habitEmpty);
        this._habitMenu = new PopupMenu.PopupMenuSection();
        this._habitPage.addMenuItem(this._habitMenu);
        this._skipHabitItem = this._habitPage.addAction('跳过当前习惯（仅今天）',
            () => this._runCommand("(org-workflow-panel-habit-action 'skip)"));
        menu.addMenuItem(this._habitPage);
        menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        this._menuCancel = menu.addAction('取消计时', () => this._runWorkflowAction('cancel'));
        this._menuRecord = menu.addAction('补记番茄钟', () => this._runWorkflowAction('record-last-pomodoro'));
        this._selectMenuTab('task');
        this._updateLeftMenu();
    }

    _selectMenuTab(id) {
        this._taskPage.actor.visible = id === 'task';
        this._habitPage.actor.visible = id === 'habit';
        // Hidden submenu actors live beside their parent item in PopupMenuSection.
        if (id !== 'task')
            this._workflowMenuItem.menu.close();
        for (const [key, tab] of Object.entries(this._menuTabs)) {
            tab.checked = key === id;
            if (key === id)
                tab.add_style_pseudo_class('checked');
            else
                tab.remove_style_pseudo_class('checked');
        }
    }

    _updateLeftMenu() {
        const view = leftMenuPresentation(this._timerStatus, this._workflowStatus);
        this._menuSummary.accessible_name = view.title;
        this._menuPreview.forEach((line, index) => {
            line.set_text(view.preview[index] ?? '');
            line.visible = index < view.preview.length;
        });
        const tasks = this._workflowStatus?.tasks ?? [];
        const taskSignature = JSON.stringify(tasks);
        this._taskEmpty.visible = tasks.length === 0;
        if (taskSignature !== this._taskMenuSignature) {
            this._taskMenuSignature = taskSignature;
            this._taskMenu.removeAll();
            tasks.forEach(task => {
                const item = this._taskMenu.addAction(`${task.selected ? '●' : '○'} ${task.title}`,
                    () => {
                        if (!task.selected)
                            this._runCommand(`(org-workflow-panel-select-task ${JSON.stringify(task.key)})`);
                    });
                item.label.clutter_text.ellipsize = 3;
                item.accessible_name = [task.title, task.parent, task.selected ? '当前任务' : ''].filter(Boolean).join(' · ');
                if (task.selected)
                    item.add_style_class_name('workflow-menu-current-task');
            });
        }
        for (const actor of [this._menuVisit, this._menuComplete]) {
            actor.reactive = view.canAct;
            actor.can_focus = view.canAct;
            actor.opacity = view.canAct ? 255 : 100;
        }
        this._workflowMenuItem.setSensitive(view.canAct);
        this._menuCancel.setSensitive(view.canCancel);
        this._menuRecord.setSensitive(view.canAct);
        this._habitEmpty.visible = !(this._workflowStatus?.panel?.habits?.length);
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
        for (const key of ['_menuSummary', '_menuPreview', '_taskMenu', '_taskEmpty',
            '_menuVisit', '_menuComplete', '_menuCancel', '_menuRecord', '_menuTabs',
            '_taskPage', '_habitPage', '_habitEmpty', '_habitMenu', '_skipHabitItem'])
            this[key] = null;
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
        if (this._refreshInFlight || this._actionsInFlight > 0) {
            this._refreshPending = true;
            this._refreshPending休息art ||= restartSchedule;
            return;
        }

        restartSchedule ||= this._refreshPending休息art;
        this._refreshPending = false;
        this._refreshPending休息art = false;
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
        if (this._refreshPending)
            this._refresh();
    }

    _updatePlanning() {
        const panel = this._workflowStatus?.panel;
        const view = planningPresentation(this._timerStatus, panel, this._workflowStatus?.resume);
        const idle = this._timerStatus?.phase === 'inactive';
        this._progress.visible = !idle;
        this._label.visible = !idle;
        this._focusGroup.visible = !idle;
        const title = workflowTitleState(this._workflowStatus, this._timerStatus);
        this._taskLabel.set_text(title.title);
        this._parentLabel.set_text(title.parent);
        this._parentLabel.visible = idle && this._workflowStatus?.available === true &&
            Boolean(title.parent);
        const reminder = currentHabitReminder(this._workflowStatus, this._timerStatus);
        this._skipHabitItem.visible = Boolean(reminder);
        this._workflowMenuItem.visible = !reminder;

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
        this._updateLeftMenu();
        const signature = JSON.stringify(panel?.habits ?? []);
        if (signature !== this._habitMenuSignature) {
            this._habitMenuSignature = signature;
            this._habitMenu.removeAll();
            (panel?.habits ?? []).forEach(habit => {
                const item = this._habitMenu.addAction(`${habit.selected ? '▶ ' : ''}${habit.done ? '✓' : '○'} ${habit.title}`,
                    () => this._runCommand(`(org-workflow-panel-toggle-habit ${JSON.stringify(habit.key)})`));
                item.setSensitive(!habit.done);
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
        this._runAction(['emacsclient', '--timeout=5', '--eval', expression]);
    }

    _runWorkflowAction(actionId) {
        let argv;
        try {
            argv = workflowCommandArgv(actionId);
        } catch (error) {
            this._refresh();
            return;
        }
        this._runAction(argv);
    }

    _runAction(argv) {
        if (!this._enabled)
            return;
        this._actionsInFlight++;
        const complete = () => {
            this._actionsInFlight--;
            // Changed signals during the action are covered by this final read.
            this._refresh({restartSchedule: true});
        };
        this._runEmacsclient(argv, complete, complete);
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
