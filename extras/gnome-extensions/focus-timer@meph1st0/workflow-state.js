const PHASES = new Set(['minimum', 'optional', 'finalized']);

function isCount(value) {
    return Number.isInteger(value) && value >= 0;
}

function isWorkflowStatus(value) {
    return value !== null && typeof value === 'object' &&
        typeof value.available === 'boolean' &&
        typeof value.task === 'string' &&
        typeof value.parent === 'string' &&
        typeof value.parentProgress === 'string' &&
        typeof value.body === 'string' &&
        isCount(value.minimumSatisfied) &&
        isCount(value.minimumTotal) &&
        value.minimumSatisfied <= value.minimumTotal &&
        isCount(value.stageSatisfied) &&
        isCount(value.stageTotal) &&
        value.stageSatisfied <= value.stageTotal &&
        PHASES.has(value.phase) &&
        typeof value.commitmentComplete === 'boolean' &&
        isCount(value.commitmentStreak);
}

export function parseWorkflowStatus(output) {
    try {
        const status = JSON.parse(JSON.parse(output));
        return isWorkflowStatus(status) ? status : null;
    } catch (_error) {
        return null;
    }
}

export function formatWorkflowTitle(status) {
    if (!status?.available)
        return status?.commitmentComplete ? 'Commitment fulfilled' : 'No current task';

    return status.task;
}

// A reminder changes presentation and desktop actions, never the running clock.
export function currentHabitReminder(status, timer) {
    const habit = status?.panel?.habitReminder;
    return timer?.phase === 'inactive' && status?.habitReminderPaused !== true &&
        status?.panel?.available === true &&
        habit && typeof habit.key === 'string' && typeof habit.title === 'string' &&
        habit.done === false ? habit : null;
}

export function workflowTitleState(status, timer) {
    const habit = currentHabitReminder(status, timer);
    return habit
        ? {title: `习惯 · ${habit.title}`, parent: '', habit: true}
        : {title: formatWorkflowTitle(status), parent: status?.parent ?? '', habit: false};
}
