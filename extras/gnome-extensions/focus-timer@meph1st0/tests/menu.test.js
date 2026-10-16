import GLib from 'gi://GLib';
import {leftMenuPresentation} from '../ui.js';

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
    setSensitive(value) { this.sensitive = value; }
}
class Menu {
    constructor() { this.actor = new Actor(); this.items = []; }
    addMenuItem(item) { this.items.push(item); }
    addAction(text, callback) {
        const item = new Actor({label: text, activate: callback});
        this.addMenuItem(item);
        return item;
    }
    close() { this.closed = true; }
}
const PopupMenu = {
    PopupBaseMenuItem: Actor, PopupMenuItem: Actor, PopupSeparatorMenuItem: Actor,
    PopupMenuSection: Menu,
    PopupSubMenuMenuItem: class extends Actor {
        constructor(text) { super({label: text}); this.menu = new Menu(); }
    },
};
const St = {Label: Actor, Button: Actor, Icon: Actor, BoxLayout: Actor, ScrollView: Actor,
    PolicyType: {NEVER: 0, AUTOMATIC: 1}};
const Clutter = {ActorAlign: {CENTER: 0}, Orientation: {VERTICAL: 1}};
const Extension = class {};
const WORKFLOW_MENU_ACTIONS = [{id: 'step', label: '添加步骤…'}];
const [, bytes] = GLib.file_get_contents('extension.js');
const source = new TextDecoder().decode(bytes).replace(/^import [\s\S]*?;\n/gm, '')
    .replace('export default class', 'class');
const ExtensionClass = eval(`${source}\nFocusTimerExtension;`);
function assert(value, message) { if (!value) throw new Error(message); }
const extension = Object.create(ExtensionClass.prototype);
const commands = [];
Object.assign(extension, {_indicator: {menu: new Menu()}, _timerStatus: null, _workflowStatus: null,
    _runWorkflowAction(action) { commands.push(action); }, _runCommand() {}, _refresh() {}});
extension._buildLeftMenu();
assert(extension._taskPage.actor.visible && !extension._habitPage.actor.visible, 'opens on task page');
assert(!extension._menuComplete.reactive && !extension._menuRecord.sensitive, 'disconnected task actions disabled');
assert(extension._habitEmpty.visible, 'empty habit page has explanation');
extension._selectMenuTab('habit');
assert(!extension._taskPage.actor.visible && extension._habitPage.actor.visible, 'habit tab changes visible page');
assert(extension._menuTabs.habit.checked && !extension._menuTabs.task.checked, 'tab selection follows page');
assert(extension._workflowMenuItem.menu.closed && commands.length === 0, 'switching closes submenu without a task action');
extension._workflowStatus = {available: true, task: 'Task', body: 'Notes', panel: {habits: [{key: 'one'}]}};
extension._timerStatus = {phase: 'focus', elapsed: 12};
extension._updateLeftMenu();
assert(extension._menuTitle.text === 'Task' && extension._menuTime.text === '12:00', 'refresh updates summary');
assert(extension._menuComplete.reactive && extension._menuCancel.sensitive, 'available actions enabled');
assert(!extension._habitEmpty.visible && extension._habitPage.actor.visible, 'refresh preserves selected tab');
extension._menuVisit.activate();
extension._menuComplete.activate();
assert(commands.join(',') === 'visit,complete' && extension._indicator.menu.closed, 'summary actions close menu and use existing commands');
extension._workflowStatus = null;
extension._timerStatus = null;
extension._updateLeftMenu();
assert(!extension._menuComplete.reactive && !extension._menuCancel.sensitive && !extension._workflowMenuItem.sensitive,
    'disconnect removes stale action availability');
print('Left popup tab, summary and command behavior passed');
