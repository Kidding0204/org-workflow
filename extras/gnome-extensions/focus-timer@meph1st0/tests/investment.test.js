import {minimumInvestmentState, PROGRESS_WIDTH} from '../ui.js';
function check(value, message) { if (!value) throw new Error(message); }
let view = minimumInvestmentState({focusTotalMinutes: 30, dailyMinimumMinutes: 60,
    minimumSatisfied: 4, minimumTotal: 4, dailyFloorComplete: true});
check(view.width === PROGRESS_WIDTH / 2 && view.text === '30/60m', 'only time controls progress');
check(!view.complete, 'completed commitments do not fill the investment bar');
view = minimumInvestmentState({focusTotalMinutes: 85, dailyMinimumMinutes: 60});
check(view.width === PROGRESS_WIDTH && view.text === '85/60m' && view.complete,
    'cap the bar while retaining actual minutes');
view = minimumInvestmentState({focusTotalMinutes: 0, dailyMinimumMinutes: 90});
check(view.width === 0 && view.text === '0/90m', 'new day starts at zero with its recorded target');
for (const status of [null, {}, {focusTotalMinutes: 1, dailyMinimumMinutes: 0},
    {focusTotalMinutes: -1, dailyMinimumMinutes: 60}, {dailyMinimumMinutes: 60}])
    check(minimumInvestmentState(status).text === '—', 'missing data must not invent zero progress');
print('Minimum investment progress tests passed');
