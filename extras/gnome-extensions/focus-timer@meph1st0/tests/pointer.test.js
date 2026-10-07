import GLib from 'gi://GLib';
const Extension = class {};
class Gesture {
    set_enabled(value) { this.enabled = value; }
    set_required_button(value) { this.button = value; }
    set_recognize_on_press(value) { this.onPress = value; }
    connect(_signal, callback) { this.recognize = callback; }
}
const Clutter = {ClickGesture: Gesture};
const [, bytes] = GLib.file_get_contents('extension.js');
const source = new TextDecoder().decode(bytes)
    .replace(/^import [\s\S]*?;\n/gm, '')
    .replace('export default class', 'class');
const Class = eval(`${source}\nFocusTimerExtension;`);
const extension = Object.create(Class.prototype);
let calls = [];
extension._runWorkflowAction = action => calls.push(action);
function check(value, message) { if (!value) throw new Error(message); }
for (const action of ['toggle', 'agenda']) {
    calls = [];
    const original = new Gesture();
    const gestures = [original];
    const indicator = {_clickGesture: original,
        remove_action: gesture => gestures.splice(gestures.indexOf(gesture), 1),
        add_action: gesture => gestures.push(gesture),
        menu: {close: () => calls.push('close'), toggle: () => calls.push('menu')}};
    extension._bindPanelClicks(indicator, action);
    check(original.enabled === false && !gestures.includes(original),
        'native default menu gesture is disabled and removed');
    check(gestures.length === 2, 'only two button-specific gestures remain');
    check(gestures[0].button === 1 && gestures[1].button === 3,
        'gestures require distinct mouse buttons');
    gestures[0].recognize();
    check(JSON.stringify(calls) === JSON.stringify(['close', action]),
        'left gesture dispatches the business action once');
    calls = [];
    gestures[1].recognize();
    check(JSON.stringify(calls) === '["menu"]', 'right gesture only opens menu');
}
check(!source.includes('contains(event.get_source())'), 'no nullable event source check');
print('Workflow gesture tests passed');
