import * as PanelPlacement from '../panel-placement.js';

function assertEqual(actual, expected, description) {
    if (actual !== expected)
        throw new Error(`${description}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
}

function testWorkflowIndicatorFollowsPlacesInTheLeftBox() {
    const calls = [];
    const panel = {
        statusArea: {
            activities: {},
            'places-menu': {},
        },
        addToStatusArea(...args) {
            calls.push(args);
        },
    };
    const indicator = {};

    PanelPlacement.addToLeftPanel(
        panel, ['activities'], 'org-workflow-focus-timer@meph1st0', indicator);

    assertEqual(calls.length, 1, 'adds exactly one status indicator');
    assertEqual(calls[0][0], 'org-workflow-focus-timer@meph1st0', 'keeps the extension role');
    assertEqual(calls[0][1], indicator, 'adds the extension indicator');
    assertEqual(calls[0][2], 2, 'inserts after Places');
    assertEqual(calls[0][3], 'left', 'uses the left panel container');
}

function testDailyProgressPrecedesTaskAndFocusProgressFollowsIt() {
    const actors = {
        dailyGroup: {},
        taskLabel: {},
        accessoryGroup: {},
    };

    const ordered = PanelPlacement.orderedPanelActors?.(actors) ?? [];

    assertEqual(ordered[0], actors.dailyGroup, 'places the daily group first');
    assertEqual(ordered[1], actors.taskLabel, 'task is an independent middle group');
    assertEqual(ordered[2], actors.accessoryGroup, 'habit or timer follows the task');
    assertEqual(ordered.length, 3, 'streak does not occupy the left task area');
}

testWorkflowIndicatorFollowsPlacesInTheLeftBox();
testDailyProgressPrecedesTaskAndFocusProgressFollowsIt();

print('org-workflow-focus-timer panel placement tests passed');

const tray = {};
let children = [tray];
let onAdded;
let disconnected = false;
const box = {
    get_children: () => children,
    connect: (_signal, callback) => { onAdded = callback; return 7; },
    disconnect: id => { disconnected = id === 7; },
    set_child_at_index: (actor, index) => {
        children.splice(children.indexOf(actor), 1);
        children.splice(index, 0, actor);
    },
};
const container = {get_parent: () => box};
children.push(container);
const release = PanelPlacement.keepFirstInRightPanel({_rightBox: box}, {container});
assertEqual(children[0], container, 'guidance starts nearest the date');
children.unshift({});
onAdded();
assertEqual(children[0], container, 'later tray insertion stays after guidance');
release();
assertEqual(disconnected, true, 'placement signal is removed on disable');
