import GLib from 'gi://GLib';
import {
    ACTIVE_REFRESH_SECONDS,
    DBUS_INTERFACE,
    DBUS_OBJECT_PATH,
    DBUS_SIGNAL,
    RECOVERY_REFRESH_SECONDS,
    UNAVAILABLE_REFRESH_SECONDS,
    WORKFLOW_DBUS_INTERFACE,
    WORKFLOW_DBUS_OBJECT_PATH,
    WORKFLOW_MENU_ACTIONS,
    refreshIntervalFor,
    isServerUnavailable,
    workflowCommandArgv,
} from '../sync.js';

function assertEqual(actual, expected, description) {
    if (actual !== expected)
        throw new Error(`${description}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
}

function assertDeepEqual(actual, expected, description) {
    assertEqual(JSON.stringify(actual), JSON.stringify(expected), description);
}

function assertThrows(callback, expectedMessage, description) {
    try {
        callback();
    } catch (error) {
        assertEqual(error.message, expectedMessage, description);
        return;
    }
    throw new Error(`${description}: expected an exception`);
}

function test刷新状态PolicyAlignsWithEmacsEvents() {
    assertEqual(ACTIVE_REFRESH_SECONDS, 60, 'uses minute-based active refreshes');
    assertEqual(RECOVERY_REFRESH_SECONDS, 300, 'uses low-frequency recovery checks');
    assertEqual(UNAVAILABLE_REFRESH_SECONDS, 5, 'repairs unavailable state promptly');
    assertEqual(refreshIntervalFor({phase: 'focus'}, {task: 'Current'}), 60,
        'continues a minute cadence for an active Focus phase');
    assertEqual(refreshIntervalFor({phase: 'short-break'}, {task: 'Current'}), 60,
        'continues a minute cadence for an active break');
    assertEqual(refreshIntervalFor({phase: 'inactive'}, {task: 'Current'}), 300,
        'retains low-frequency repair polling while inactive');
    assertEqual(refreshIntervalFor(null, {task: 'Current'}), 5,
        'retries a timer read failure promptly');
    assertEqual(refreshIntervalFor({phase: 'inactive'}, null), 5,
        'retries a workflow read failure promptly');
}

function testDbusSignalCarriesNoTimerState() {
    assertEqual(DBUS_OBJECT_PATH, '/io/github/meph1st0/FocusTimer',
        'uses a fixed private D-Bus object path');
    assertEqual(DBUS_INTERFACE, 'io.github.meph1st0.FocusTimer',
        'uses a fixed private D-Bus interface');
    assertEqual(DBUS_SIGNAL, 'Changed', 'uses an argument-free state-change signal');
    assertEqual(WORKFLOW_DBUS_OBJECT_PATH, '/io/github/meph1st0/OrgWorkflow',
        'uses a separate workflow object path');
    assertEqual(WORKFLOW_DBUS_INTERFACE, 'io.github.meph1st0.OrgWorkflow',
        'uses a separate workflow interface');
}

function testWorkflowMenuExposesExistingDesktopActions() {
    assertDeepEqual(WORKFLOW_MENU_ACTIONS, [
        {id: 'start', label: '开始当前任务'},
        {id: 'prerequisite', label: '添加前置任务…'},
        {id: 'defer', label: '移至晚间'},
        {id: 'defer-group', label: '整组移至晚间'},
        {id: 'complete', label: '标记完成'},
        {id: 'rest', label: '休息'},
        {id: 'continue', label: '继续'},
        {id: 'cancel', label: '取消当前任务'},
    ], 'keeps the title-bar menu aligned with global workflow shortcuts');
}

function testWorkflowCommandsReuseOrCreateFramesOnlyWhenNeeded() {
    assertDeepEqual(workflowCommandArgv('visit'), [
        GLib.build_filenamev([GLib.get_home_dir(), '.local', 'bin', 'org-workflow-client']), 'visit',
    ], 'open delegates persistent-frame handling to the workflow bridge');
    assertDeepEqual(workflowCommandArgv('prerequisite'), [
        GLib.build_filenamev([GLib.get_home_dir(), '.local', 'bin', 'org-workflow-client']), 'prerequisite',
    ], 'interactive parameters use the same persistent-frame bridge');
    assertDeepEqual(workflowCommandArgv('start'), [
        GLib.build_filenamev([GLib.get_home_dir(), '.local', 'bin', 'org-workflow-client']), 'start',
    ], 'background actions share the validated desktop boundary');
    assertThrows(() => workflowCommandArgv('erase-buffer'),
        'Unknown Org Workflow action: erase-buffer',
        'rejects actions outside the desktop allowlist');
}

test刷新状态PolicyAlignsWithEmacsEvents();
testDbusSignalCarriesNoTimerState();
testWorkflowMenuExposesExistingDesktopActions();
testWorkflowCommandsReuseOrCreateFramesOnlyWhenNeeded();


assertDeepEqual([1, 2, 3, 4, 5, 100].map(attempt =>
    refreshIntervalFor(null, null, attempt)), [5, 10, 20, 40, 60, 60],
    'unavailable server backs off with a bounded recovery delay');
assertEqual(refreshIntervalFor({phase: 'focus'}, {}, 100), 60,
    'recovery restores the normal cadence');
assertEqual(isServerUnavailable("emacsclient: can't find socket; have you started the server?"), true,
    'startup socket absence is an expected waiting state');
assertEqual(isServerUnavailable('emacsclient: timed out'), true,
    'busy server timeout uses waiting state');
assertEqual(isServerUnavailable('Symbol function definition is void: org-workflow-focus-timer-status-json'), false,
    'backend errors remain visible');

print('org-workflow-focus-timer sync tests passed');
