import GLib from 'gi://GLib';
import {planningPresentation, weekTrackStyle} from '../planning.js';
import {isServerUnavailable, refreshIntervalFor} from '../sync.js';

// Exercise refresh control flow without a GNOME Shell session.
const Extension = class {};
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
    _updatePlanning() {},
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
print('org-workflow-focus-timer startup lifecycle tests passed');

// Exercise the presentation boundary, including replacement of the timer actors.
const label = () => ({text: '', set_text(text) { this.text = text; },
    clutter_text: {set_markup(text) { this.markup = text; }}});
Object.assign(extension, {
    _progress: {}, _label: {}, _parentLabel: label(),
    _focusGroup: {}, _accessoryGroup: {}, _queueLayout() {},
    _weekStrip: {}, _weekCells: Array.from({length: 7}, () => ({track: {set_style(value) { this.style = value; }}, unknown: {}, dot: {}})),
    _rightLabel: label(), _rightIndicator: {}, _rightBody: {label: label()},
    _habitMenu: {menu: {removeAll() {}, addAction() {}}},
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
