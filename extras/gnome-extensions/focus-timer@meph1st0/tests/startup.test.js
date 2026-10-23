import {minimumInvestmentState, PROGRESS_HEIGHT} from '../ui.js';
import GLib from 'gi://GLib';
import {currentHabitReminder, workflowTitleState} from '../workflow-state.js';
import {planningPresentation, weekTrackStyle} from '../planning.js';
import {isServerUnavailable, refreshIntervalFor, workflowCommandArgv} from '../sync.js';

// Exercise refresh control flow without a GNOME Shell session.
const Extension = class {};
const PopupMenu = {Ornament: {DOT: 1, NONE: 0}};
const [, bytes] = GLib.file_get_contents('extension.js');
const source = new TextDecoder().decode(bytes)
    .replace(/^import [\s\S]*?;\n/gm, '')
    .replace('export default class', 'class');
const ExtensionClass = eval(`${source}\nFocusTimerExtension;`);
function assert(value, message) {
    if (!value)
        throw new Error(message);
}
const extension = Object.create(ExtensionClass.prototype);
Object.assign(extension, {
    _enabled: true,
    _unavailableAttempts: 0,
    _refreshPending: false,
    _timerStatus: null,
    _workflowStatus: null,
    _setTimerUnavailable() {},
    _setWorkflowUnavailable() {},
    _syncRefreshTimer() {},
    _updatePlanning() {}, _updateLeftMenu() {},
});
let calls = 0;
let workflowReads = 0;
extension._runExpression = (_expression, _success, failure) => {
    calls++;
    failure("emacsclient: can't find socket; have you started the server?");
};
extension._readWorkflow = () => workflowReads++;
extension._refresh();
assert(calls === 1 && workflowReads === 0,
    'missing socket must not launch a redundant workflow request');
assert(!extension._refreshInFlight && extension._unavailableAttempts === 1,
    'failed request must release the refresh lock and schedule recovery');
extension._timerStatus = {phase: 'inactive'};
extension._workflowStatus = {};
extension._completeRefresh(false);
assert(extension._unavailableAttempts === 0, 'successful recovery resets backoff');
let scheduled = 0;
extension._syncRefreshTimer = () => scheduled++;
extension._enabled = false;
extension._completeRefresh(false);
assert(scheduled === 0, 'disabled extension must not restart polling');
print('focus-timer startup lifecycle tests passed');

// Exercise the presentation boundary, including replacement of the timer actors.
const label = () => ({text: '', set_text(text) { this.text = text; },
    clutter_text: {set_markup(text) { this.markup = text; }}});
Object.assign(extension, {
    _progress: {}, _label: {}, _parentLabel: label(), _taskLabel: label(),
    _morePage: {}, _bodyItem: {label: label()},
    _focusGroup: {}, _accessoryGroup: {}, _queueLayout() {},
    _weekStrip: {}, _weekCells: Array.from({length: 7}, () => ({track: {set_style(value) { this.style = value; }}, unknown: {}, dot: {}})),
    _settings: {get_string() { return 'hint'; }},
    _idleDisplayItems: ['investment', 'hint'].map(mode => ({mode,
        item: {setOrnament(value) { this.ornament = value; }}})),
    _investmentGroup: {}, _investmentLabel: label(),
    _investmentFill: {set_size(width) { this.width = width; },
        remove_style_class_name() {}, add_style_class_name() {}},
    _rightLabel: label(), _rightIndicator: {}, _rightBody: {label: label()},
    _habitMenu: {removeAll() {}, addAction() { return {setSensitive() {}}; }},
    _timerStatus: {phase: 'inactive'},
    _workflowStatus: {available: true, parent: 'Course', panel: {available: true, started: false, hint: 'Start here',
        habits: [{title: 'SICP', key: 'abc', done: false}],
        week: [{date: '2026-09-21', state: 'complete', basis: 'investment'}]}},
});
ExtensionClass.prototype._updatePlanning.call(extension);
assert(!extension._progress.visible && extension._parentLabel.visible,
    'idle shows parent instead of timer');
assert(extension._rightLabel.text === 'Start here', 'hint appears before first focus');
extension._timerStatus.phase = 'focus';
extension._workflowStatus.panel.started = true;
ExtensionClass.prototype._updatePlanning.call(extension);
assert(extension._progress.visible && !extension._parentLabel.visible,
    'focus restores timer');
assert(extension._weekStrip.visible && !extension._rightLabel.visible, 'started shows graphical week');
assert(extension._weekCells[0].track.style_class.includes('complete'), 'achievement styling');
assert(extension._focusGroup.visible && extension._accessoryGroup.visible, 'timer is grouped after the separator');
extension._timerStatus.phase = 'short-break';
ExtensionClass.prototype._updatePlanning.call(extension);
assert(extension._progress.visible && !extension._parentLabel.visible, 'break retains timer');
print('Workflow panel actor transitions passed');

extension._timerStatus.phase = 'inactive';
extension._workflowStatus.resume = 'Continue this task';
ExtensionClass.prototype._updatePlanning.call(extension);
assert(!extension._weekStrip.visible && extension._rightLabel.visible, 'stopping returns to text');
assert(extension._rightLabel.text === 'Continue this task', 'stopped displays current task cue');
extension._workflowStatus.resume = 'New task cue';
ExtensionClass.prototype._updatePlanning.call(extension);
assert(extension._rightLabel.text === 'New task cue', 'task switching updates cue');
extension._workflowStatus.parent = '';
ExtensionClass.prototype._updatePlanning.call(extension);
assert(!extension._parentLabel.visible && !extension._accessoryGroup.visible, 'no empty parent slot');

extension._workflowStatus.kind = 'habit';
extension._workflowStatus.task = 'Run';
extension._workflowStatus.panel.habitReminder = {key: 'run', title: 'Run', done: false};
ExtensionClass.prototype._updatePlanning.call(extension);
assert(extension._taskLabel.text === '习惯 · Run',
    'idle shows latest reminder');
extension._timerStatus.phase = 'focus';
extension._workflowStatus.kind = 'task';
extension._workflowStatus.task = 'Original task';
ExtensionClass.prototype._updatePlanning.call(extension);
assert(extension._taskLabel.text === 'Original task',
    'focus preserves actual task');
extension._timerStatus.phase = 'inactive';
extension._workflowStatus.kind = 'habit';
extension._workflowStatus.task = 'Run';
ExtensionClass.prototype._updatePlanning.call(extension);
assert(extension._taskLabel.text === '习惯 · Run', 'stopping focus restores pending reminder');
extension._workflowStatus.panel.habitReminder = null;
extension._workflowStatus.kind = 'task';
extension._workflowStatus.task = 'Original task';
ExtensionClass.prototype._updatePlanning.call(extension);
assert(extension._taskLabel.text === 'Original task', 'skipping restores underlying task');
print('Habit reminder actor transitions passed');

extension._workflowStatus.panel.habitReminder = {key: 'run', title: 'Run', done: false};
extension._workflowStatus.kind = 'habit';
extension._workflowStatus.task = 'Selected habit';
ExtensionClass.prototype._updatePlanning.call(extension);
assert(extension._taskLabel.text === '习惯 · Selected habit',
    'an explicit habit selection controls title');
extension._workflowStatus.kind = 'task';
extension._workflowStatus.task = 'Original task';
ExtensionClass.prototype._updatePlanning.call(extension);
assert(extension._taskLabel.text === 'Original task',
    'restoring the queue controls title and actions despite the old reminder');

// Keep subprocess lifecycle guards real while controlling action completion order.
const processes = [];
let spawnError = false;
const Gio = {
    SubprocessFlags: {STDOUT_PIPE: 1, STDERR_PIPE: 2},
    Subprocess: {new() {
        if (spawnError)
            throw new Error('spawn failed');
        return {
            communicate_utf8_async(_input, _cancel, callback) {
                processes.push(success => {
                    this.success = success;
                    callback(this, {});
                });
            },
            communicate_utf8_finish() { return [true, '', 'action failed']; },
            get_successful() { return this.success; },
        };
    }},
};
const reads = [];
const refreshes = [];
const actions = Object.create(ExtensionClass.prototype);
Object.assign(actions, {
    _enabled: true, _generation: {}, _actionsInFlight: 0,
    _refreshInFlight: false, _refreshPending: false, _refreshPending休息art: false,
    _timerStatus: {}, _workflowStatus: {},
    _syncRefreshTimer() {}, _updatePlanning() {},
    _readTimer(restart) {
        reads.push('timer');
        refreshes.push(() => {
            reads.push('workflow');
            this._completeRefresh(restart);
        });
    },
});
actions._runWorkflowAction('complete');
actions._refresh({restartSchedule: true});
actions._refresh({restartSchedule: true});
assert(reads.length === 0, 'action signals wait for the final state');
processes.shift()(true);
refreshes.shift()();
assert(reads.join(',') === 'timer,workflow' && !actions._refreshPending,
    'command completion and Changed signals share exactly one status pair');

reads.length = 0;
actions._runCommand('(org-workflow-panel-toggle-habit "run")');
actions._runWorkflowAction('cancel');
actions._refresh({restartSchedule: true});
processes.shift()(true);
assert(reads.length === 0, 'concurrent actions wait until all have completed');
processes.shift()(false);
actions._refresh({restartSchedule: true});
refreshes.shift()();
refreshes.shift()();
assert(reads.join(',') === 'timer,workflow,timer,workflow',
    'a failure still refreshes, and a later change during the read is retained');

reads.length = 0;
actions._refresh();
actions._runWorkflowAction('complete');
actions._refresh({restartSchedule: true});
refreshes.shift()();
assert(reads.length === 2 && actions._refreshPending,
    'an older read completing during an action defers its pending refresh');
processes.shift()(true);
refreshes.shift()();
assert(reads.join(',') === 'timer,workflow,timer,workflow',
    'action completion drains the deferred refresh once');

reads.length = 0;
spawnError = true;
actions._runWorkflowAction('cancel');
spawnError = false;
refreshes.shift()();
assert(actions._actionsInFlight === 0 && reads.length === 2,
    'synchronous subprocess failure releases the action lock');

reads.length = 0;
actions._runWorkflowAction('cancel');
actions._enabled = false;
actions._generation = null;
processes.shift()(true);
assert(reads.length === 0, 'disabled extension ignores outstanding action completion');
actions._enabled = true;
actions._generation = {};
actions._actionsInFlight = 0;
actions._runWorkflowAction('cancel');
actions._generation = {};
actions._actionsInFlight = 0;
processes.shift()(false);
assert(reads.length === 0 && actions._actionsInFlight === 0,
    'old action callbacks cannot alter a re-enabled extension');
print('Workflow action refresh coalescing passed');

// The default investment mode replaces hints only while inactive.
extension._settings.get_string = () => 'investment';
extension._workflowStatus.dailyMinimumMinutes = 60;
extension._workflowStatus.focusTotalMinutes = 30;
for (const phase of ['inactive', 'focus', 'short-break', 'long-break']) {
    extension._timerStatus.phase = phase;
    ExtensionClass.prototype._updatePlanning.call(extension);
    assert(extension._investmentGroup.visible === (phase === 'inactive'), 'investment is idle only');
    assert(!extension._rightLabel.visible, 'hint hidden in investment mode');
}
assert(extension._investmentLabel.text === '30/60m', 'actual investment label');
assert(extension._idleDisplayItems[0].item.ornament === PopupMenu.Ornament.DOT &&
    extension._idleDisplayItems[1].item.ornament === PopupMenu.Ornament.NONE, 'menu marks selected mode');
extension._timerStatus = null;
ExtensionClass.prototype._updatePlanning.call(extension);
assert(!extension._investmentGroup.visible && extension._rightLabel.text === '—',
    'timer failure does not masquerade as idle');
print('Minimum investment actor transitions passed');
