import GLib from 'gi://GLib';

function assertContains(source, fragment, description) {
    if (!source.includes(fragment))
        throw new Error(`${description}: missing ${JSON.stringify(fragment)}`);
}

const [, bytes] = GLib.file_get_contents('extension.js');
const source = new TextDecoder().decode(bytes);
const [, metadataBytes] = GLib.file_get_contents('metadata.json');
const metadata = JSON.parse(new TextDecoder().decode(metadataBytes));

if (metadata.version !== 22)
    throw new Error(`canonical Workflow API release version: expected 22, got ${metadata.version}`);

assertContains(source, 'WORKFLOW_MENU_ACTIONS',
    'extension consumes the shared workflow menu model');
assertContains(source, 'workflowCommandArgv',
    'extension consumes the shared emacsclient argv builder');
assertContains(source, "new PopupMenu.PopupSubMenuMenuItem('任务操作')",
    'extension exposes a grouped workflow action menu');
assertContains(source, "this._runWorkflowAction('visit')",
    '打开当前任务 uses the frame-aware workflow command path');
assertContains(source, 'for (const action of WORKFLOW_MENU_ACTIONS)',
    'every modeled workflow action is added to the title-bar menu');
assertContains(source, 'Commitment streak:',
    'extension gives the streak an accessible name');

print('focus-timer extension contract tests passed');
assertContains(source, 'this._parentLabel.set_text(status.parent)', 'parent is a separate label');
assertContains(source, 'track.set_style(weekTrackStyle(day))', 'recorded time controls track intensity');
if (source.includes('_habitButton'))
    throw new Error('habit reminders use the current task label');

assertContains(source, "const TIMER_STATUS_EXPRESSION = '(org-workflow-focus-timer-status-json)'",
    'timer status uses the standalone package API');
assertContains(source, "const FINISH_EXPRESSION = '(progn (org-workflow-focus-timer-finish-phase) (org-workflow-focus-timer-status-json))'",
    'finish action uses the standalone package API');
assertContains(source, "const STOP_EXPRESSION = '(progn (org-workflow-focus-timer-stop) (org-workflow-focus-timer-status-json))'",
    'stop action uses the standalone package API');
for (const oldName of ['focus-timer-status-json', 'focus-timer-finish-phase', 'focus-timer-stop']) {
    if (source.includes(`(${oldName}`))
        throw new Error(`legacy Emacs interface remains: ${oldName}`);
}
