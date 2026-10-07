import {formatStatus, parseEmacsclientStatus} from '../state.js';

function assertEqual(actual, expected, description) {
    if (actual !== expected)
        throw new Error(`${description}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
}

function assertStatus(actual, expected, description) {
    for (const [key, value] of Object.entries(expected))
        assertEqual(actual?.[key], value, `${description} (${key})`);
}

function testParseEmacsclientStatus() {
    const output = '"{\\"phase\\":\\"focus\\",\\"elapsed\\":7,\\"target\\":25,\\"completed\\":2,\\"expired\\":false}"\n';

    assertStatus(parseEmacsclientStatus(output), {
        phase: 'focus',
        elapsed: 7,
        target: 25,
        completed: 2,
        expired: false,
    }, 'decodes the Emacs Lisp string and its embedded JSON');
}

function testRejectsInvalidStatus() {
    assertEqual(parseEmacsclientStatus('not JSON'), null,
        'rejects a non-JSON emacsclient response');
    assertEqual(parseEmacsclientStatus('"{\\"phase\\":\\"paused\\"}"'), null,
        'rejects an unknown timer phase');
}

function testFormatStatus() {
    assertEqual(formatStatus({phase: 'focus', elapsed: 7, target: 25, expired: false}), 'F -18m',
        'shows remaining Focus minutes with a negative sign');
    assertEqual(formatStatus({phase: 'focus', elapsed: 25, target: 25, expired: false}), 'F -0m',
        'shows zero remaining Focus minutes with a negative sign');
    assertEqual(formatStatus({phase: 'focus', elapsed: 37, target: 25, expired: true}), 'F +12m',
        'shows Focus overtime minutes');
    assertEqual(formatStatus({phase: 'short-break', elapsed: 2, target: 5, expired: false}), 'B -3m',
        'shows remaining short-break minutes with a negative sign');
    assertEqual(formatStatus({phase: 'long-break', elapsed: 3, target: 15, expired: false}), 'L -12m',
        'shows remaining long-break minutes with a negative sign');
    assertEqual(formatStatus({phase: 'inactive', elapsed: 0, target: 0, expired: false}), 'F —',
        'keeps an inactive indicator available for refresh');
}

testParseEmacsclientStatus();
testRejectsInvalidStatus();
testFormatStatus();

print('org-workflow-focus-timer state tests passed');
