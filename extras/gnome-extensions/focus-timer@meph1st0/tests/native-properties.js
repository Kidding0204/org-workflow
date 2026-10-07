// Run with the installed GNOME Shell/Mutter GI paths; no display or actors needed.
import GLib from 'gi://GLib';
import St from 'gi://St';
import Clutter from 'gi://Clutter';
import Pango from 'gi://Pango';
import PangoCairo from 'gi://PangoCairo';
const [, bytes] = GLib.file_get_contents('extension.js');
const source = new TextDecoder().decode(bytes);
let constructors = 0;
for (const match of source.matchAll(/new St\.(\w+)\(\{([\s\S]*?)\}\)/g)) {
    const [, name, body] = match;
    const properties = new Set(St[name].list_properties().map(p => p.name));
    for (const field of body.matchAll(/(?:^|[,\n])\s*(\w+)\s*:/g)) {
        const property = field[1].replaceAll('_', '-');
        if (!properties.has(property))
            throw new Error(`Installed St.${name} does not support ${property}`);
    }
    constructors++;
}
if (constructors < 10 || Clutter.Orientation.VERTICAL === undefined)
    throw new Error('Native property coverage or orientation enum unavailable');
print(`Installed GNOME widget properties passed (${constructors} constructors)`);

const gesture = new Clutter.ClickGesture();
gesture.set_required_button(3);
gesture.set_recognize_on_press(true);
if (gesture.get_required_button() !== 3 || !gesture.get_recognize_on_press())
    throw new Error('Native button-specific gesture configuration failed');
print('Installed Clutter button-specific gesture passed');

const layout = Pango.Layout.new(PangoCairo.FontMap.get_default().create_context());
layout.set_text('任务与习惯名称', -1);
const copy = layout.copy();
copy.set_width(-1);
copy.set_ellipsize(Pango.EllipsizeMode.NONE);
copy.set_text('○ 2', -1);
if (copy.get_pixel_size()[0] <= 0 || layout.get_text() !== '任务与习惯名称')
    throw new Error('Native title measurement must not mutate the visible label');
for (const method of ['get_transformed_position', 'get_preferred_width']) {
    if (typeof Clutter.Actor.prototype[method] !== 'function')
        throw new Error(`Native layout API unavailable: ${method}`);
}
print('Installed Pango title measurement passed');
