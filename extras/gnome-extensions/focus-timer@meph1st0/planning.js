// Presentation only: Emacs owns dates and completion; timer phase selects the presentation.
export function weekTrackStyle(day) {
    if (!Number.isFinite(day?.focusMinutes) || day.focusMinutes < 0)
        return '';
    const ratio = Math.min(1, day.focusMinutes / 600);
    const palette = {
        complete: [141, 200, 189, 0.24, 0.95],
        incomplete: [190, 195, 202, 0.08, 0.55],
        leave: [195, 167, 214, 0.08, 0.65],
    };
    const color = palette[day.state];
    if (!color)
        return '';
    const [r, g, b, low, high] = color;
    return `background-color: rgba(${r}, ${g}, ${b}, ${(low + (high - low) * ratio).toFixed(3)});`;
}

export function planningPresentation(timer, panel, resume = '') {
    if (!panel || panel.available !== true || !Array.isArray(panel.habits) || !Array.isArray(panel.week))
        return {right: '—', details: 'Workflow 数据暂不可用', habit: '', habitIndex: -1, complete: false};
    // A running Emacs daemon may retain the old wire names during a Shell update.
    panel = {...panel, week: panel.week.map(day => ({...day,
        state: ({invested: 'complete', unrecorded: 'incomplete'})[day.state] ?? day.state}))};
    const cycling = ['focus', 'short-break', 'long-break'].includes(timer?.phase);
    const idle = timer?.phase === 'inactive';
    const hint = (typeof resume === 'string' ? resume.trim() : '') || panel.hint || '';
    const pending = panel.habits.map((h, index) => ({...h, index})).filter(h => !h.done);
    const habit = timer?.phase !== 'inactive' ? '' : pending.length
        ? `○ ${pending[0].title}${pending.length > 1 ? ` +${pending.length - 1}` : ''}`
        : panel.habits.length ? '✓ 习惯已完成' : '';
    const labels = ['一', '二', '三', '四', '五', '六', '日'];
    const symbols = {complete: '●', leave: '◇', incomplete: '·', future: '–', unknown: '?'};
    const week = panel.week.map((day, i) => `${labels[i]}${symbols[day.state] ?? '?'}`).join(' ');
    return {
        right: cycling ? week : idle ? hint : '—',
        days: cycling ? panel.week.map(day => ({
            state: Object.hasOwn(symbols, day.state) ? day.state : 'unknown',
            today: day.date === panel.today,
            focusMinutes: day.focusMinutes,
        })) : [],
        details: [!cycling && !idle ? '专注状态暂不可用' : '', panel.hint ? `开工提示：${panel.hint}` : '',
            ...panel.week.map(day => {
                const commitment = day.basis === 'commitment';
                const label = {
                    complete: commitment ? '承诺已兑现' : '无承诺但有投入',
                    incomplete: commitment ? '承诺尚未全部兑现' : '无承诺且无投入',
                    leave: commitment ? '承诺尚未全部兑现 · 已记录请假' : '已记录请假',
                    future: '未来', unknown: '数据不可用',
                }[day.state] ?? '数据不可用';
                const records = Array.isArray(day.leaveRecords) ? day.leaveRecords : [];
                const notes = records.filter(record => typeof record?.reason === 'string' && Array.isArray(record.slots))
                    .map(record => `请假：${record.slots.map(slot => ({morning: '上午', afternoon: '下午', evening: '晚上'}[slot] ?? slot)).join('／')} · ${record.reason}`);
                const minutes = day.focusMinutes;
                const time = Number.isFinite(minutes) && minutes >= 0 &&
                    !['future', 'unknown'].includes(day.state)
                    ? ` · 投入 ${Math.floor(minutes / 60)} 小时 ${Math.floor(minutes % 60)} 分钟` : '';
                return [`${day.date}  ${label}${time}`, ...notes.map(note => `  ${note}`)].join('\n');
            })].filter(Boolean).join('\n'),
        habit, habitCompact: pending.length ? `○ ${pending.length}` : panel.habits.length ? '✓' : '',
        habitIndex: pending[0]?.index ?? -1, complete: pending.length === 0,
    };
}
