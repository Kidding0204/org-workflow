const PHASES = new Set(['inactive', 'focus', 'short-break', 'long-break']);

function isNonNegativeInteger(value) {
    return Number.isInteger(value) && value >= 0;
}

function isStatus(value) {
    return value !== null && typeof value === 'object' &&
        PHASES.has(value.phase) &&
        isNonNegativeInteger(value.elapsed) &&
        isNonNegativeInteger(value.target) &&
        isNonNegativeInteger(value.completed) &&
        typeof value.expired === 'boolean';
}

export function parseEmacsclientStatus(output) {
    try {
        const status = JSON.parse(JSON.parse(output));
        return isStatus(status) ? status : null;
    } catch (_error) {
        return null;
    }
}

export function formatStatus(status) {
    if (!status || status.phase === 'inactive')
        return 'F —';

    const prefix = {
        focus: 'F',
        'short-break': 'B',
        'long-break': 'L',
    }[status.phase];

    if (!prefix || !isNonNegativeInteger(status.elapsed) ||
        !isNonNegativeInteger(status.target) || typeof status.expired !== 'boolean')
        return 'F —';

    const minutes = status.expired
        ? `+${Math.max(0, status.elapsed - status.target)}m`
        : `-${Math.max(0, status.target - status.elapsed)}m`;
    return `${prefix} ${minutes}`;
}
