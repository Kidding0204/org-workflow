import Cairo from 'cairo';
import * as UI from '../ui.js';
function check(value, message) { if (!value) throw new Error(message); }
check(typeof UI.periodProgressState === 'function', 'period presentation must exist');
const start = 1000, end = 2000;
for (const name of ['morning', 'afternoon', 'evening']) {
    const status = {workPeriod: {name, start, end}};
    check(UI.periodProgressState(status, 1000).fraction === 0, 'start is empty');
    const half = UI.periodProgressState(status, 1500);
    check(half.fraction === 0.5 && half.label.includes('50%'), 'half elapsed');
    check(UI.periodProgressState(status, 2500).fraction === 1, 'rest gap caps at full');
    check(UI.periodProgressState(status, 999).fraction === 0, 'clock rollback clamps');
    const surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, 40, 40);
    const cr = new Cairo.Context(surface);
    UI.drawPeriodProgress(cr, 40, 40, half);
    cr.$dispose();
}
for (const workPeriod of [null, {}, {name: 'other', start, end},
    {name: 'morning', start: end, end: start}])
    check(!UI.periodProgressState({workPeriod}, 1500).available, 'invalid windows are neutral');
check(!UI.periodProgressState(null).available, 'older or unavailable daemon stays neutral');
const blue = UI.periodProgressState({workPeriod: {name:'morning', start, end}}, 1500).color;
check(blue[2] > blue[0], 'morning is blue');
print('Period ring tests passed');
