import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
const directory = GLib.dir_make_tmp('workflow-settings-XXXXXX');
const schemaName = 'org.gnome.shell.extensions.focus-timer';
try {
    const [, bytes] = GLib.file_get_contents(`schemas/${schemaName}.gschema.xml`);
    GLib.file_set_contents(`${directory}/${schemaName}.gschema.xml`, bytes);
    const compiler = Gio.Subprocess.new(['glib-compile-schemas', '--strict', directory], Gio.SubprocessFlags.NONE);
    if (!compiler.wait_check(null)) throw new Error('schema compilation failed');
    const source = Gio.SettingsSchemaSource.new_from_directory(directory, null, false);
    const schema = source.lookup(schemaName, false);
    const backend = Gio.memory_settings_backend_new();
    const settings = Gio.Settings.new_full(schema, backend, null);
    if (settings.get_string('idle-display') !== 'investment') throw new Error('default must be investment');
    let changes = 0;
    settings.connect('changed::idle-display', () => changes++);
    settings.set_string('idle-display', 'hint');
    const reopened = Gio.Settings.new_full(schema, backend, null);
    if (reopened.get_string('idle-display') !== 'hint') throw new Error('preference lost on reopening');
    settings.set_string('idle-display', 'investment');
    if (changes !== 2) throw new Error('mode changes must notify the live display');
    print('Idle display settings default, persistence and change notifications passed');
} finally {
    GLib.unlink(`${directory}/gschemas.compiled`);
    GLib.unlink(`${directory}/${schemaName}.gschema.xml`);
    GLib.rmdir(directory);
}
