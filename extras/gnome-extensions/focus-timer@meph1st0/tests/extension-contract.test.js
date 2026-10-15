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
assertContains(source, "this._runWorkflowAction('cancel')",
    'cancel uses the configured clock backend');
assertContains(source, "this._runWorkflowAction('record-last-pomodoro')",
    'retrospective recording resolves the shared current item');
for (const oldName of ['focus-timer-status-json', 'focus-timer-finish-phase', 'focus-timer-stop']) {
    if (source.includes(`(${oldName}`))
        throw new Error(`legacy Emacs interface remains: ${oldName}`);
}

assertContains(source, "this._runWorkflowAction('select')",
    '选择任务 uses the dedicated selector client path');

const directLabels = ['选择任务', '打开当前任务', '完成当前任务', '取消计时', '补记番茄钟', '任务操作'];
const positions = directLabels.map(label => source.indexOf(`'${label}'`));
if (positions.some((position, index) => position < 0 || (index > 0 && position <= positions[index - 1])))
    throw new Error('direct actions precede the task submenu in the requested order');
if (source.includes("PopupSeparatorMenuItem('计时')") || source.includes("PopupSubMenuMenuItem('今日习惯')"))
    throw new Error('timer header and habit submenu must not remain');
assertContains(source, 'new PopupMenu.PopupMenuSection()', 'habit rows are exposed directly');
assertContains(source, '(org-workflow-panel-toggle-habit ', 'habit rows toggle their current-item selection');
assertContains(source, 'item.setSensitive(!habit.done)', 'completed habits cannot be selected');
assertContains(source, "this._runWorkflowAction('history')", 'right menu opens native history');
if (source.includes("menu.addAction('打开 Sprint'"))
    throw new Error('Sprint remains a left-click action, not a duplicate menu entry');
