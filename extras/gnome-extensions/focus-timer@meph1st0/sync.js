import GLib from 'gi://GLib';

export const ACTIVE_REFRESH_SECONDS = 60;
export const RECOVERY_REFRESH_SECONDS = 300;
export const UNAVAILABLE_REFRESH_SECONDS = 5;

export const DBUS_OBJECT_PATH = '/io/github/meph1st0/FocusTimer';
export const DBUS_INTERFACE = 'io.github.meph1st0.FocusTimer';
export const DBUS_SIGNAL = 'Changed';
export const WORKFLOW_DBUS_OBJECT_PATH = '/io/github/meph1st0/OrgWorkflow';
export const WORKFLOW_DBUS_INTERFACE = 'io.github.meph1st0.OrgWorkflow';

export const WORKFLOW_MENU_ACTIONS = [
    {id: 'start', label: '开始当前任务'},
    {id: 'prerequisite', label: '添加前置任务…'},
    {id: 'defer', label: '移至晚间'},
    {id: 'defer-group', label: '整组移至晚间'},
    {id: 'complete', label: '标记完成'},
    {id: 'rest', label: '休息'},
    {id: 'continue', label: '继续'},
    {id: 'cancel', label: '取消当前任务'},
];

const WORKFLOW_ACTION_IDS = new Set([
    'visit', 'toggle', 'agenda', 'week',
    ...WORKFLOW_MENU_ACTIONS.map(action => action.id),
]);
const WORKFLOW_CLIENT = GLib.build_filenamev([
    GLib.get_home_dir(), '.local', 'bin', 'org-workflow-client',
]);

export function workflowCommandArgv(actionId) {
    if (!WORKFLOW_ACTION_IDS.has(actionId))
        throw new Error(`Unknown Org Workflow action: ${actionId}`);

    return [WORKFLOW_CLIENT, actionId];
}

export function isServerUnavailable(message) {
    return /can't find socket|No socket or alternate editor|Connection refused|Connection timed out|Timed out/i.test(message);
}

export function refreshIntervalFor(timerStatus, workflowStatus, unavailableAttempts = 1) {
    if (!timerStatus || !workflowStatus)
        return Math.min(60, UNAVAILABLE_REFRESH_SECONDS *
            2 ** Math.min(4, Math.max(0, unavailableAttempts - 1)));

    return timerStatus.phase === 'inactive'
        ? RECOVERY_REFRESH_SECONDS
        : ACTIVE_REFRESH_SECONDS;
}
