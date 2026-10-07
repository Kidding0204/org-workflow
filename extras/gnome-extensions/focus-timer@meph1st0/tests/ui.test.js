import {
    applyStatus,
    applyUnavailable,
    commitmentStreakText,
    dailyProgressState,
    PROGRESS_HEIGHT,
    progressState,
} from '../ui.js';

function assertEqual(actual, expected, description) {
    if (actual !== expected)
        throw new Error(`${description}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
}

function makeLabel() {
    return {
        text: '',
        classes: new Set(['focus-timer-inactive']),
        set_text(text) {
            this.text = text;
        },
        add_style_class_name(name) {
            this.classes.add(name);
        },
        remove_style_class_name(name) {
            this.classes.delete(name);
        },
    };
}

function testActiveStatusUpdatesTheVisibleLabel() {
    const label = makeLabel();
    const indicator = {};

    applyStatus(indicator, label, {
        phase: 'focus', elapsed: 7, target: 25, completed: 0, expired: false,
    });

    assertEqual(label.text, 'F -18m', 'shows the active Focus status');
    assertEqual(label.classes.has('focus-timer-inactive'), false,
        'removes the inactive appearance for an active status');
    assertEqual(indicator.accessible_name, 'Focus Timer: F -18m',
        'updates the panel control accessibility label');
}

function testUnavailableStatusKeepsTheControlUsable() {
    const label = makeLabel();
    const indicator = {};

    applyUnavailable(indicator, label, 'Emacs daemon unavailable');

    assertEqual(label.text, 'F —', 'shows the low-distraction unavailable state');
    assertEqual(label.classes.has('focus-timer-inactive'), true,
        'keeps the unavailable state visually subdued');
    assertEqual(indicator.accessible_name, 'Focus Timer unavailable',
        'identifies the failure to assistive technology');
}

function testProgressStateShowsElapsedTimeAndPhase() {
    assertEqual(PROGRESS_HEIGHT, 12, 'uses the rounded 12px progress-bar height');

    const focus = progressState({
        phase: 'focus', elapsed: 7, target: 25, completed: 0, expired: false,
    });
    assertEqual(focus.width, 32, 'fills the wider Focus bar by elapsed time');
    assertEqual(focus.variant, 'focus', 'keeps the Focus color variant');

    const breakState = progressState({
        phase: 'short-break', elapsed: 2, target: 5, completed: 0, expired: false,
    });
    assertEqual(breakState.width, 46, 'fills the wider short-break bar by elapsed time');
    assertEqual(breakState.variant, 'break', 'uses the break color variant');

    const overtime = progressState({
        phase: 'focus', elapsed: 37, target: 25, completed: 0, expired: true,
    });
    assertEqual(overtime.width, 116, 'fills the wider bar completely after the target');
    assertEqual(overtime.variant, 'overtime', 'uses the overtime color variant');

    const inactive = progressState({
        phase: 'inactive', elapsed: 0, target: 0, completed: 0, expired: false,
    });
    assertEqual(inactive.width, 0, 'keeps the inactive bar empty');
    assertEqual(inactive.variant, 'inactive', 'uses the inactive variant');
}

function testDailyProgressStateShowsCurrentStageProgress() {
    const afternoon = dailyProgressState({
        stageSatisfied: 2, stageTotal: 3,
    });
    assertEqual(afternoon.width, 77, 'fills two thirds of the stage bar');
    assertEqual(afternoon.text, '2/3', 'shows the numeric stage ratio');
    assertEqual(afternoon.variant, 'daily', 'uses the active daily style');

    const complete = dailyProgressState({
        stageSatisfied: 3, stageTotal: 3,
    });
    assertEqual(complete.width, 116, 'fills a completed stage');
    assertEqual(complete.text, '3/3', 'keeps the completed stage count visible');
    assertEqual(complete.variant, 'complete', 'uses the completed style');

    const empty = dailyProgressState({stageSatisfied: 0, stageTotal: 0});
    assertEqual(empty.width, 0, 'keeps an empty stage bar unfilled');
    assertEqual(empty.text, '0/0', 'shows an empty current stage explicitly');
}

function testCommitmentStreakTextAlwaysUsesACompactZeroBasedLabel() {
    assertEqual(commitmentStreakText({commitmentStreak: 7}), '🔥 7',
        'shows a compact commitment streak');
    assertEqual(commitmentStreakText(null), '🔥 0',
        'keeps a zero-valued streak visible when workflow is unavailable');
}

testActiveStatusUpdatesTheVisibleLabel();
testUnavailableStatusKeepsTheControlUsable();
testProgressStateShowsElapsedTimeAndPhase();
testDailyProgressStateShowsCurrentStageProgress();
testCommitmentStreakTextAlwaysUsesACompactZeroBasedLabel();

print('org-workflow-focus-timer UI tests passed');
