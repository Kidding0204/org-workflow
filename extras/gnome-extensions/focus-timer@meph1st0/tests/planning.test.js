import {planningPresentation, weekTrackStyle} from '../planning.js';
function check(test, message) { if (!test) throw new Error(message); }
const panel = {available: true, started: false, hint: '先尝试一道题',
    habits: [{title: 'SICP', done: false}], week: [{date: '2026-09-21', state: 'complete', basis: 'investment'}]};
check(planningPresentation({phase: 'inactive'}, panel).habit === '○ SICP', 'idle habit');
check(planningPresentation({phase: 'focus'}, panel).habit === '', 'focus takes precedence');
check(planningPresentation({phase: 'short-break'}, panel).habit === '', 'break takes precedence');
check(planningPresentation({phase: 'inactive'}, panel).right === panel.hint, 'opening hint');
check(planningPresentation({phase: 'inactive'}, {...panel, started: true}).right === panel.hint, 'stopping restores hint despite earlier focus');
check(planningPresentation(null, null).right === '—', 'unknown is not zero');
check(planningPresentation({phase: 'inactive'}, {...panel, habits: [{title: 'SICP', done: true}]}).complete, 'completed');
print('Workflow planning presentation tests passed');
const compactHabit = planningPresentation({phase: 'inactive'}, {...panel,
    habits: [{title: 'A very long habit', done: false}, {title: 'Second', done: false}]});
check(compactHabit.habitCompact === '○ 2' && compactHabit.habitIndex === 0, 'compact count retains visit target');
check(planningPresentation({phase: 'inactive'}, {...panel,
    habits: [{title: 'Finished', done: true}]}).habit === '✓ 习惯已完成', 'short completed habit label');
const days = planningPresentation({phase: 'focus'}, {...panel, started: true, today: '2026-09-22',
    week: [{date: '2026-09-21', state: 'complete', basis: 'investment'}, {date: '2026-09-22', state: 'incomplete', basis: 'investment'},
        {date: '2026-09-23', state: 'future'}, {date: '2026-09-24', state: 'broken'}]}).days;
check(days[0].state === 'complete' && !days[0].today, 'past investment');
check(days[1].today && days[1].state === 'incomplete', 'today is independent of completion');
check(days[2].state === 'future' && days[3].state === 'unknown', 'future and errors differ');
check(planningPresentation(null, panel).days.length === 0, 'guidance has no tracks');

for (const phase of ['focus', 'short-break', 'long-break']) {
    check(planningPresentation({phase}, panel, 'Task cue').right === '一●', `${phase} shows week`);
}
check(planningPresentation({phase: 'inactive'}, panel, 'Task cue').right === 'Task cue', 'task cue wins');
check(planningPresentation({phase: 'inactive'}, panel, '   ').right === panel.hint, 'blank cue falls back');
check(planningPresentation({phase: 'inactive'}, {...panel, hint: ''}).right === '', 'no invented hint');
check(planningPresentation(null, panel, 'Task cue').right === '—', 'unknown timer is not idle');

const leaveRecord = {id: 'leave-1', date: '2026-09-21', slots: ['evening'], reason: '朋友邀请聚会',
    recordedAt: '2026-09-21T21:00:00+08:00', tasks: []};
const leaveView = planningPresentation({phase: 'focus'}, {...panel,
    week: [{date: leaveRecord.date, state: 'leave', leaveRecords: [leaveRecord]},
        {date: '2026-09-22', state: 'complete', basis: 'investment', leaveRecords: [{...leaveRecord, date: '2026-09-22'}]}]});
check(leaveView.right === '一◇ 二●', 'leave is distinct from invested');
check(leaveView.days[0].state === 'leave' && leaveView.days[1].state === 'complete', 'track state preserves actual investment');
check(leaveView.details.includes('已记录请假') && leaveView.details.includes('晚上 · 朋友邀请聚会'), 'leave slot and reason in details');
check(leaveView.details.includes('2026-09-22  无承诺但有投入'), 'invested leave retains actual investment text');
const commitmentWeek = planningPresentation({phase: 'focus'}, {...panel, week: [
    {date: '2026-09-21', state: 'complete', basis: 'commitment'},
    {date: '2026-09-22', state: 'incomplete', basis: 'commitment'},
    {date: '2026-09-23', state: 'complete', basis: 'investment'},
    {date: '2026-09-24', state: 'incomplete', basis: 'investment'},
]});
check(commitmentWeek.right === '一● 二· 三● 四·', 'tracks represent achievement');
for (const text of ['承诺已兑现', '承诺尚未全部兑现', '无承诺但有投入', '无承诺且无投入'])
    check(commitmentWeek.details.includes(text), `explicit achievement basis: ${text}`);
const transitional = planningPresentation({phase: 'focus'}, {...panel, week: [
    {date: '2026-09-21', state: 'invested', basis: 'commitment'},
    {date: '2026-09-22', state: 'unrecorded', basis: 'commitment'},
]});
check(transitional.days[0].state === 'complete' && transitional.days[1].state === 'incomplete', 'session rollout accepts legacy wire names');
check(transitional.details.includes('承诺已兑现'), 'legacy wire state keeps new achievement basis');
check(weekTrackStyle({state: 'complete', focusMinutes: 0}).includes('0.240'), 'zero time retains visible success');
check(weekTrackStyle({state: 'complete', focusMinutes: 300}).includes('0.595'), 'five hours is midpoint');
check(weekTrackStyle({state: 'complete', focusMinutes: 600}).includes('0.950'), 'ten hours reaches full intensity');
check(weekTrackStyle({state: 'complete', focusMinutes: 900}) === weekTrackStyle({state: 'complete', focusMinutes: 600}), 'ten-hour cap');
check(weekTrackStyle({state: 'incomplete', focusMinutes: 600}).includes('190, 195, 202'), 'incomplete remains gray');
check(weekTrackStyle({state: 'leave', focusMinutes: 300}).includes('195, 167, 214'), 'leave remains purple');
for (const state of ['future', 'unknown'])
    check(weekTrackStyle({state, focusMinutes: 600}) === '', 'no invented future or unknown intensity');
check(weekTrackStyle({state: 'complete'}) === '', 'missing time is not zero');
const timed = planningPresentation({phase: 'focus'}, {...panel,
    week: [{date: '2026-09-21', state: 'incomplete', basis: 'commitment', focusMinutes: 305}]});
check(timed.days[0].focusMinutes === 305 && timed.days[0].state === 'incomplete', 'time cannot fulfill commitment');
check(timed.details.includes('投入 5 小时 5 分钟'), 'menu shows exact recorded time');
