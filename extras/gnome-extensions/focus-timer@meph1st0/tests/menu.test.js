import GLib from 'gi://GLib';
import {leftMenuPresentation} from '../ui.js';
import {WORKFLOW_MENU_ACTIONS} from '../sync.js';
const Signals = imports.signals;

// Only the GNOME actors are replaced; exercise the extension's real menu builder,
// tab transitions and action callbacks without a compositor or personal Org data.
class Actor {
    constructor(props = {}) {
        Object.assign(this, {visible: true, children: [], classes: new Set(), clutter_text: {}}, props);
    }
    add_child(child) { this.children.push(child); }
    set_child(child) { this.children = [child]; }
    add_style_class_name(name) { this.classes.add(name); }
    add_style_pseudo_class(name) { this.classes.add(name); }
    remove_style_pseudo_class(name) { this.classes.delete(name); }
    connect(_signal, callback) { this.activate = callback; }
    set_text(text) { this.text = text; }
    set_policy() {}
    syncSensitive() {
        this.sensitive = this._sensitive && (this.parent?._sensitive ?? true);
        this.reactive = this.sensitive;
        return this.sensitive;
    }
    setSensitive(value) { this._sensitive = value; this.syncSensitive(); }
}
class Menu {
    constructor() { this.actor = new Actor(); this.box = this.actor; this.items = []; this._sensitive = true; }
    addMenuItem(item) { this.items.push(item); }
    addAction(text, callback) {
        const item = new Actor({label: new Actor({text}), activate: callback});
        item.parent = this;
        item._sensitive = true;
        // Native PopupMenuBase hooks this return value into imports.signals.
        this.connect('notify::sensitive', () => item.syncSensitive());
        this.addMenuItem(item);
        return item;
    }
    close() { this.closed = true; }
    removeAll() { this.items = []; }
    setSensitive(value) { this._sensitive = value; this.emit('notify::sensitive'); }
}
Signals.addSignalMethods(Menu.prototype);
const PopupMenu = {
    PopupBaseMenuItem: Actor, PopupMenuItem: Actor, PopupSeparatorMenuItem: Actor,
    PopupMenuSection: Menu,
    PopupSubMenuMenuItem: class extends Actor {
        constructor(text) { super({label: text}); this.menu = new Menu(); }
    },
};
const St = {Label: Actor, Button: Actor, Icon: Actor, BoxLayout: Actor, ScrollView: Actor, Widget: Actor,
    PolicyType: {NEVER: 0, AUTOMATIC: 1}};
const Clutter = {ActorAlign: {CENTER: 0}, Orientation: {VERTICAL: 1}};
const Extension = class {};
const [, bytes] = GLib.file_get_contents('extension.js');
const source = new TextDecoder().decode(bytes).replace(/^import [\s\S]*?;\n/gm, '')
    .replace('export default class', 'class');
const ExtensionClass = eval(`${source}\nFocusTimerExtension;`);
function assert(value, message) { if (!value) throw new Error(message); }
const extension = Object.create(ExtensionClass.prototype);
const commands = [];
Object.assign(extension, {_indicator: {menu: new Menu()}, _timerStatus: null, _workflowStatus: null,
    _runWorkflowAction(action) { commands.push(action); }, _runCommand(expression) { commands.push(expression); }, _refresh() {}});
extension._buildLeftMenu();
assert(extension._taskPage.actor.visible && !extension._habitPage.actor.visible, 'opens on task page');
assert(!extension._menuComplete.reactive && !extension._menuRecord.reactive, 'disconnected task actions disabled');
assert(extension._habitEmpty.visible, 'empty habit page has explanation');
extension._selectMenuTab('habit');
assert(!extension._taskPage.actor.visible && extension._habitPage.actor.visible, 'habit tab changes visible page');
assert(extension._menuTabs.habit.checked && !extension._menuTabs.task.checked, 'tab selection follows page');
assert(commands.length === 0, 'switching pages does not execute an action');
extension._selectMenuTab('more');
assert(extension._morePage.actor.visible && !extension._taskPage.actor.visible && !extension._habitPage.actor.visible, 'more actions have an independent page');
extension._selectMenuTab('habit');
extension._workflowStatus = {available: true, task: 'Task', body: 'Notes', tasks: [{key: 'first', title: 'Task', selected: true}, {key: 'second', title: 'Other', selected: false}], panel: {habits: [{key: 'one'}]}};
extension._timerStatus = {phase: 'focus', elapsed: 12};
extension._updateLeftMenu();
assert(extension._menuSummary.accessible_name === 'Task' && extension._menuPreview[0].text === 'Notes', 'refresh updates summary');
assert(extension._menuComplete.reactive && extension._menuCancel.reactive, 'available actions enabled');
assert(extension._morePage.items.every(item => item.reactive), 'all operations recover after initial disconnection');
assert(!extension._habitEmpty.visible && extension._habitPage.actor.visible, 'refresh preserves selected tab');
extension._menuVisit.activate();
extension._menuComplete.activate();
assert(commands.join(',') === 'visit,complete' && extension._indicator.menu.closed, 'summary actions close menu and use existing commands');
extension._workflowStatus = null;
extension._timerStatus = null;
extension._updateLeftMenu();
assert(!extension._menuComplete.reactive && !extension._menuCancel.reactive && extension._morePage.items.every(item => !item.reactive),
    'disconnect removes stale action availability');
print('Left popup tab, summary and command behavior passed');

extension._workflowStatus = {available: true, body: '1\n2\n3\n4',
    tasks: [{key: 'first', title: 'Same', selected: true}, {key: 'second', title: 'Same', selected: false}]};
extension._updateLeftMenu();
assert(extension._menuPreview[2].text === '3…' && extension._menuPreview.length === 3, 'summary contains only three body rows');
assert(extension._taskMenu.items.length === 2 && !extension._taskEmpty.visible, 'task page renders the supplied stack');
const before = commands.length;
extension._taskMenu.items[0].activate();
assert(commands.length === before, 'clicking the selected task does not interrupt its clock');
extension._taskMenu.items[1].activate();
assert(commands.at(-1) === '(org-workflow-panel-select-task "second")', 'direct row selection sends the exact source key');
const items = extension._taskMenu.items;
extension._updateLeftMenu();
assert(items === extension._taskMenu.items, 'unchanged refresh does not rebuild task rows');
print('Direct task stack selection and preview passed');

extension._selectMenuTab('more');
extension._morePage.items[0].activate();
assert(commands.at(-1) === 'step', 'more page routes existing task commands');
extension._menuCancel.activate();
extension._menuRecord.activate();
assert(commands.slice(-2).join(',') === 'cancel,record-last-pomodoro', 'compact timer buttons retain existing actions');
assert(extension._menuCancel.accessible_name === '取消计时' && extension._menuRecord.accessible_name === '补记番茄钟', 'short labels retain full accessible names');
extension._workflowStatus.kind = 'habit';
extension._updateLeftMenu();
assert(extension._morePage.items.every(item => !item.reactive) && extension._morePage.actor.visible, 'habit targets disable task-only actions without switching tabs');

extension._workflowStatus.kind = 'task';
extension._updateLeftMenu();
assert(extension._morePage.items.every(item => item.reactive), 'all four operations recover after a disabled state');
for (const item of extension._morePage.items)
    item.activate();
assert(commands.slice(-4).join(',') === WORKFLOW_MENU_ACTIONS.map(action => action.id).join(','), 'every restored operation routes its own command');
print('All operation rows recover from disabled states');
