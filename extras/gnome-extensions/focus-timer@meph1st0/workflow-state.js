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
