import {formatWorkflowTitle, parseWorkflowStatus} from '../workflow-state.js';
import {dailyProgressState, PROGRESS_WIDTH} from '../ui.js';

function assertEqual(actual, expected, description) {
    if (actual !== expected)
        throw new Error(`${description}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
}

const output = '"{\\"available\\":true,\\"task\\":\\"Read textbook\\",' +
    '\\"parent\\":\\"Cache Performance\\",\\"parentProgress\\":\\"1/3\\",' +
    '\\"body\\":\\"Read section 2.1\\",\\"minimumSatisfied\\":2,' +
    '\\"minimumTotal\\":3,\\"phase\\":\\"minimum\\",' +
    '\\"commitmentComplete\\":false,\\"stageSatisfied\\":1,' +
    '\\"stageTotal\\":2,\\"commitmentStreak\\":7}"\n';

const status = parseWorkflowStatus(output);
assertEqual(status?.minimumSatisfied, 2, 'parses daily progress');
assertEqual(status?.stageSatisfied, 1, 'parses current-stage progress');
assertEqual(status?.commitmentStreak, 7, 'parses the commitment streak');
assertEqual(formatWorkflowTitle(status),
    'Read textbook', 'top bar omits parent and project statistics');
assertEqual(formatWorkflowTitle({available: false, commitmentComplete: true}),
    'Commitment fulfilled', 'formats fulfilled commitment without claiming goal completion');
assertEqual(parseWorkflowStatus('"{\\"available\\":true}"'), null,
    'rejects incomplete payloads');

const legacyOutput = '"{\\"available\\":true,\\"task\\":\\"Read\\",' +
    '\\"parent\\":\\"\\",\\"parentProgress\\":\\"\\",' +
    '\\"body\\":\\"\\",\\"minimumSatisfied\\":0,' +
    '\\"minimumTotal\\":1,\\"phase\\":\\"minimum\\",' +
    '\\"commitmentComplete\\":false,\\"commitmentStreak\\":0}"\n';
assertEqual(parseWorkflowStatus(legacyOutput), null,
    'requires current-stage progress fields');

const negativeStreakOutput = output.replace('\\"commitmentStreak\\":7', '\\"commitmentStreak\\":-1');
assertEqual(parseWorkflowStatus(negativeStreakOutput), null,
    'rejects negative commitment streaks');

const attemptedStatus = parseWorkflowStatus(JSON.stringify(JSON.stringify({
    available: true, task: 'Continue textbook', parent: 'Course', parentProgress: '0/3',
    body: '', minimumSatisfied: 1, minimumTotal: 1, phase: 'optional',
    commitmentComplete: true, commitmentStreak: 1, stageSatisfied: 2, stageTotal: 2,
})));
assertEqual(attemptedStatus?.available, true, 'unfinished attempted task remains available');
assertEqual(formatWorkflowTitle(attemptedStatus), 'Continue textbook',
    'shows the current task despite fulfilling its daily commitment');
assertEqual(dailyProgressState(attemptedStatus).width, PROGRESS_WIDTH,
    'commitment and added task attempts fill the stage bar');
assertEqual(dailyProgressState(attemptedStatus).variant, 'complete',
    'attempts receive the existing completion feedback');

const addedPendingStatus = {...attemptedStatus, stageSatisfied: 1};
assertEqual(dailyProgressState(addedPendingStatus).text, '1/2',
    'unattempted added task keeps its place in stage progress');
assertEqual(dailyProgressState(addedPendingStatus).variant, 'daily',
    'fulfilled commitments do not prematurely fill additional-task progress');

print('org workflow state tests passed');
