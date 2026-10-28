// Run without frontend dependencies: node test/history-contract.node.mjs
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { test } from 'node:test'
import { parseHistory } from '../src/history.ts'

// Produced by org-workflow-web-export-history against a temporary SQLite store.
const fixture = JSON.parse(readFileSync(new URL('./fixtures/current-history-export.json', import.meta.url), 'utf8'))

test('accepts the current Lisp export and retains backend floor and satisfaction facts', () => {
  assert.equal(parseHistory(fixture), fixture)
  assert.equal(fixture.days[0].dailyFloorComplete, false)
  assert.equal(fixture.days[0].minimumTasks[0].satisfied, false)
})

test('accepts legacy exports with the optional additions absent', () => {
  const payload = structuredClone(fixture)
  const day = payload.days[0]
  delete day.dailyMinimumMinutes
  delete day.dailyFloorComplete
  delete day.dailyFloorBasis
  delete day.minimumTasks[0].satisfied
  assert.equal(parseHistory(payload), payload)
})

for (const [field, invalid] of [
  ['dailyMinimumMinutes', -1], ['dailyMinimumMinutes', 1.5],
  ['dailyMinimumMinutes', '60'], ['dailyMinimumMinutes', Number.MAX_SAFE_INTEGER + 1],
  ['dailyMinimumMinutes', null], ['dailyFloorComplete', 'false'],
  ['dailyFloorComplete', 0], ['dailyFloorComplete', null],
  ['dailyFloorBasis', 'done'], ['dailyFloorBasis', null],
  ['unknownFloorField', false],
]) {
  test(`rejects ${field}=${JSON.stringify(invalid)}`, () => {
    const payload = structuredClone(fixture)
    payload.days[0][field] = invalid
    assert.throws(() => parseHistory(payload), new RegExp(field))
  })
}

for (const basis of ['commitment', 'investment', 'pending']) {
  test(`accepts floor basis ${basis} without recomputing backend progress`, () => {
    const payload = structuredClone(fixture)
    Object.assign(payload.days[0], {
      dailyMinimumMinutes: 0, dailyFloorComplete: true, dailyFloorBasis: basis,
    })
    payload.days[0].minimumTasks[0].satisfied = true
    assert.equal(parseHistory(payload), payload)
  })
}

for (const field of ['dailyMinimumMinutes', 'dailyFloorComplete', 'dailyFloorBasis']) {
  test(`accepts optional ${field} independently`, () => {
    const payload = structuredClone(fixture)
    for (const absent of ['dailyMinimumMinutes', 'dailyFloorComplete', 'dailyFloorBasis']) {
      if (absent !== field) delete payload.days[0][absent]
    }
    assert.equal(parseHistory(payload), payload)
  })
}

for (const field of ['minimumTasks', 'optionalTasks', 'habitTasks']) {
  test(`validates optional satisfaction in ${field} and rejects unknown task fields`, () => {
    const payload = structuredClone(fixture)
    payload.days[0][field] = [{ task: 'Task', outcome: 'pending', focusMinutes: 0, satisfied: false }]
    assert.equal(parseHistory(payload), payload)
    payload.days[0][field][0].satisfied = 'false'
    assert.throws(() => parseHistory(payload), /satisfied/)
    payload.days[0][field][0].satisfied = false
    payload.days[0][field][0].unexpected = true
    assert.throws(() => parseHistory(payload), /unexpected/)
  })
}
