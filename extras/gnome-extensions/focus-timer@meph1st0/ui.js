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

    if (Number.isInteger(status.dailyMinimumMinutes) && status.dailyMinimumMinutes > 0 &&
        Number.isFinite(status.focusTotalMinutes)) {
        const total = status.minimumTotal;
        const done = status.minimumSatisfied;
        const minutes = Math.max(0, Math.floor(status.focusTotalMinutes));
        const target = status.dailyMinimumMinutes;
        const ratio = Math.max(total > 0 ? done / total : 0, minutes / target);
        return {
            width: Math.round(PROGRESS_WIDTH * Math.min(1, ratio)),
            text: `${done}/${total} · ${minutes}/${target}m`,
            variant: status.dailyFloorComplete === true ? 'complete' : 'daily',
        };
    }
    // Compatibility with daemons that still expose the previous daily policy.
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

// Three source lines, each rendered on one ellipsized visual row by the menu.
export function leftMenuPresentation(timer, workflow) {
    const canAct = workflow?.available === true;
    const body = !workflow ? '暂时无法读取任务，请稍后刷新。' : canAct
        ? (workflow.body?.trim() || '暂无任务备注。') : '选择一个任务，开始今天的工作。';
    const lines = body.split(/\r?\n/);
    const preview = lines.slice(0, 3);
    if (lines.length > 3)
        preview[2] += '…';
    return {
        title: !workflow ? '等待 Emacs' : canAct ? workflow.task : '暂无当前任务',
        preview,
        canAct,
        canCancel: Boolean(timer && timer.phase !== 'inactive'),
    };
}
