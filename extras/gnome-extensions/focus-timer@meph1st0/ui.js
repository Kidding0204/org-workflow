import {formatStatus} from './state.js';

const INACTIVE_CLASS = 'focus-timer-inactive';
export const PROGRESS_WIDTH = 116;
export const PROGRESS_HEIGHT = 12;

export function progressState(status) {
    if (status.phase === 'inactive')
        return {width: 0, variant: 'inactive'};

    if (status.expired)
        return {width: PROGRESS_WIDTH, variant: 'overtime'};

    const width = Math.round(PROGRESS_WIDTH * Math.min(1, status.elapsed / status.target));
    const variant = status.phase === 'focus' ? 'focus' : 'break';
    return {width, variant};
}

export function dailyProgressState(status) {
    if (!status)
        return {width: 0, text: '0/0', variant: 'unavailable'};

    // Emacs counts today's valid attempts (or completed goals), not TODO states.
    const total = status.stageTotal;
    const satisfied = status.stageSatisfied;
    const ratio = total === 0 ? 0 : Math.min(1, satisfied / total);
    return {
        width: Math.round(PROGRESS_WIDTH * ratio),
        text: `${satisfied}/${total}`,
        variant: total > 0 && satisfied === total ? 'complete' : 'daily',
    };
}

export function commitmentStreakText(status) {
    return `🔥 ${status?.commitmentStreak ?? 0}`;
}

export function applyStatus(indicator, label, status) {
    const text = formatStatus(status);
    label.set_text(text);

    if (status.phase === 'inactive')
        label.add_style_class_name(INACTIVE_CLASS);
    else
        label.remove_style_class_name(INACTIVE_CLASS);

    indicator.accessible_name = `Focus Timer: ${text}`;
}

export function applyUnavailable(indicator, label, _message) {
    label.set_text('F —');
    label.add_style_class_name(INACTIVE_CLASS);
    indicator.accessible_name = 'Focus Timer unavailable';
}

// Menu-only presentation: the backend reports elapsed whole minutes.
export function leftMenuPresentation(timer, workflow) {
    const canAct = workflow?.available === true;
    const active = timer && timer.phase !== 'inactive';
    const elapsed = timer?.elapsed ?? 0;
    const phase = {focus: '专注中', 'short-break': '短休息', 'long-break': '长休息'}[timer?.phase];
    return {
        title: !workflow ? '等待 Emacs' : canAct ? workflow.task : '暂无当前任务',
        parent: [workflow?.parent, workflow?.parentProgress].filter(Boolean).join(' · '),
        time: active ? `${String(Math.floor(elapsed)).padStart(2, '0')}:00` : '—',
        phase: !timer ? '计时状态暂不可用' : active
            ? `${phase} · ${timer.expired ? '已到时' : '按分钟更新'}` : '尚未计时',
        details: !workflow ? '暂时无法读取任务，请稍后刷新。' : canAct
            ? [workflow.body || '暂无任务备注。', workflow.resume
                ? `下次从这里开始：${workflow.resume}` : ''].filter(Boolean).join('\n\n')
            : '选择一个任务，开始今天的工作。',
        canAct,
        canCancel: Boolean(active),
    };
}
