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
