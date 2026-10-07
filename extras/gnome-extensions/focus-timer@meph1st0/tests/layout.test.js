import {titleLayout} from '../layout.js';
function check(value, message) {
    if (!value)
        throw new Error(message);
}
let view = titleLayout(900, 180, 300, 400);
check(view.task === 300 && view.parent === 400, 'parent has no fixed maximum');
view = titleLayout(650, 180, 300, 400);
check(view.task === 300 && view.parent === 170, 'parent shrinks before task');
view = titleLayout(520, 180, 300, 400);
check(view.task === 260 && view.parent === 80, 'task shrinks after parent reaches 80px');
view = titleLayout(900, 180, 70, 45);
check(view.task === 70 && view.parent === 45, 'short parent uses natural width');
view = titleLayout(500, 320, 600, 0);
check(view.task === 180 && view.parent === 0, 'focus keeps timer without parent');
view = titleLayout(200, 180, 300, 400);
check(view.task === 20 && view.parent === 0, 'extreme narrow width still fits');
for (const screen of [1024, 1366, 1920, 2560, 3840]) {
    for (const scale of [1, 1.25, 1.5, 2]) {
        const available = Math.max(0, screen / scale / 2 - 120);
        for (const fixed of [180, 320]) {
            const caps = titleLayout(available, fixed, 600, fixed === 180 ? 400 : 0);
            check(caps.task + caps.parent <= Math.max(0, available - fixed), 'titles respect clock boundary');
            check(caps.task >= 0 && caps.parent >= 0, 'nonnegative widths');
        }
    }
}
print('Adaptive parent-first title layout tests passed');
