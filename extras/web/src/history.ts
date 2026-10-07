export type TaskOutcome = 'pending' | 'done' | 'ready' | 'held' | 'focused'

export type Commitment = 'met' | 'unmet' | 'untouch'

export type TaskRow = {
  task: string
  outcome: TaskOutcome
  focusMinutes: number
}

export type LeaveSlot = 'morning' | 'afternoon' | 'evening'
export type LeaveRecord = {
  id: string
  date: string
  slots: LeaveSlot[]
  reason: string
  recordedAt: string
  tasks: { id: string | null; task: string; slot: LeaveSlot | null }[]
}

export type FinalizedDay = {
  leaveRecords?: LeaveRecord[]
  date: string
  recordState: 'finalized'
  commitment: Commitment
  commitmentFocusMinutes: number
  optionalFocusMinutes: number
  habitFocusMinutes?: number
  habitCompleted?: number
  habitTasks?: TaskRow[]
  focusTotalMinutes: number
  optionalCompleted: number
  finalizedAt: string
  minimumTasks: TaskRow[]
  optionalTasks: TaskRow[]
}

export type MissingDay = {
  leaveRecords?: LeaveRecord[]
  date: string
  recordState: 'missing'
}

export type HistoryDay = FinalizedDay | MissingDay

export type Coverage = {
  trackingStarted: string
  eligibleThrough: string
}

export type HistoryPayload = {
  schema: 'org-workflow-history'
  schemaVersion: 1
  generatedAt: string
  timezone: string
  coverage: Coverage | null
  days: HistoryDay[]
}

export type LoadState =
  | { kind: 'ready'; payload: HistoryPayload }
  | { kind: 'error'; message: string }

const taskOutcomes = new Set<TaskOutcome>([
  'pending',
  'done',
  'ready',
  'held',
  'focused',
])

const commitments = new Set<Commitment>(['met', 'unmet', 'untouch'])

function asObject(input: unknown, label: string): Record<string, unknown> {
  if (typeof input !== 'object' || input === null || Array.isArray(input)) {
    throw new Error(`${label} must be an object`)
  }

  return input as Record<string, unknown>
}

function assertKeys(
  input: Record<string, unknown>,
  keys: readonly string[],
  label: string,
): void {
  for (const key of keys) {
    if (!Object.hasOwn(input, key)) {
      throw new Error(`${label} is missing required field: ${key}`)
    }
  }

  for (const key of Object.keys(input)) {
    if (!keys.includes(key)) {
      throw new Error(`${label} has unsupported field: ${key}`)
    }
  }
}

function assertIsoDate(input: unknown, label: string): asserts input is string {
  if (typeof input !== 'string') {
    throw new Error(`${label} must be an ISO date string`)
  }

  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(input)
  if (match === null) {
    throw new Error(`${label} must be an ISO date string`)
  }

  const date = new Date(`${input}T00:00:00.000Z`)
  if (Number.isNaN(date.getTime()) || date.toISOString().slice(0, 10) !== input) {
    throw new Error(`${label} must be a valid ISO date`)
  }
}

function assertIsoTimestamp(input: unknown, label: string): asserts input is string {
  if (typeof input !== 'string') {
    throw new Error(`${label} must be an ISO timestamp string`)
  }

  const match = /^(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(Z|[+-]\d{2}:\d{2})$/.exec(
    input,
  )
  if (match === null) {
    throw new Error(`${label} must be an ISO timestamp string`)
  }

  const [, date, hour, minute, second, offset] = match
  assertIsoDate(date, label)
  if (
    Number(hour) > 23 ||
    Number(minute) > 59 ||
    Number(second) > 59 ||
    (offset !== 'Z' &&
      (Number(offset.slice(1, 3)) > 23 || Number(offset.slice(4, 6)) > 59)) ||
    Number.isNaN(Date.parse(input))
  ) {
    throw new Error(`${label} must be a valid ISO timestamp`)
  }
}

function assertTimezone(input: unknown, label: string): asserts input is string {
  if (typeof input !== 'string' || input.length === 0) {
    throw new Error(`${label} must be a supported timezone`)
  }

  try {
    new Intl.DateTimeFormat('en-US', { timeZone: input }).format(0)
  } catch {
    throw new Error(`${label} must be a supported timezone`)
  }
}

function assertSafeNonNegativeInteger(
  input: unknown,
  label: string,
): asserts input is number {
  if (
    typeof input !== 'number' ||
    !Number.isSafeInteger(input) ||
    input < 0
  ) {
    throw new Error(`${label} must be a non-negative safe integer`)
  }
}

function assertTaskRow(input: unknown, label: string): void {
  const task = asObject(input, label)
  assertKeys(task, ['task', 'outcome', 'focusMinutes'], label)

  if (typeof task.task !== 'string' || task.task.length === 0) {
    throw new Error(`${label}.task must be a non-empty string`)
  }
  if (typeof task.outcome !== 'string' || !taskOutcomes.has(task.outcome as TaskOutcome)) {
    throw new Error(`${label}.outcome is invalid`)
  }
  assertSafeNonNegativeInteger(task.focusMinutes, `${label}.focusMinutes`)
}

function assertTaskRows(input: unknown, label: string): void {
  if (!Array.isArray(input)) {
    throw new Error(`${label} must be an array`)
  }

  input.forEach((task, index) => assertTaskRow(task, `${label}[${index}]`))
}

function assertLeaveRecords(input: unknown, date: unknown, label: string): void {
  if (!Array.isArray(input)) throw new Error(`${label} must be an array`)
  const slots = new Set(['morning', 'afternoon', 'evening'])
  const ids = new Set<string>()
  input.forEach((value, index) => {
    const key = `${label}[${index}]`
    const record = asObject(value, key)
    assertKeys(record, ['id', 'date', 'slots', 'reason', 'recordedAt', 'tasks'], key)
    if (typeof record.id !== 'string' || !record.id.trim() || ids.has(record.id))
      throw new Error(`${key}.id must be a unique non-empty string`)
    ids.add(record.id)
    assertIsoDate(record.date, `${key}.date`)
    if (record.date !== date) throw new Error(`${key}.date must match its day`)
    if (typeof record.reason !== 'string' || !record.reason.trim())
      throw new Error(`${key}.reason must be non-empty`)
    assertIsoTimestamp(record.recordedAt, `${key}.recordedAt`)
    if (!Array.isArray(record.slots) || !record.slots.length ||
        record.slots.some(slot => !slots.has(slot)) || new Set(record.slots).size !== record.slots.length)
      throw new Error(`${key}.slots is invalid`)
    const coveredSlots = record.slots
    if (!Array.isArray(record.tasks)) throw new Error(`${key}.tasks must be an array`)
    record.tasks.forEach((value, taskIndex) => {
      const taskKey = `${key}.tasks[${taskIndex}]`
      const task = asObject(value, taskKey)
      assertKeys(task, ['id', 'task', 'slot'], taskKey)
      if (task.id !== null && (typeof task.id !== 'string' || !task.id.trim()))
        throw new Error(`${taskKey}.id is invalid`)
      if (typeof task.task !== 'string' || !task.task.trim())
        throw new Error(`${taskKey}.task must be non-empty`)
      if (task.slot !== null && !coveredSlots.includes(task.slot)) throw new Error(`${taskKey}.slot must be covered`)
    })
  })
}

function assertFinalizedDay(input: Record<string, unknown>, index: number): void {
  const label = `Finalized day at days[${index}]`
  assertKeys(
    input,
    [
      'date',
      'recordState',
      'commitment',
      'commitmentFocusMinutes',
      'optionalFocusMinutes',
      'focusTotalMinutes',
      'optionalCompleted',
      'finalizedAt',
      'minimumTasks',
      'optionalTasks',
      ...(Object.hasOwn(input, 'habitFocusMinutes') ? ['habitFocusMinutes', 'habitCompleted', 'habitTasks'] : []),
      ...(Object.hasOwn(input, 'leaveRecords') ? ['leaveRecords'] : []),
    ],
    label,
  )
  assertIsoDate(input.date, `${label}.date`)
  if (Object.hasOwn(input, 'leaveRecords')) assertLeaveRecords(input.leaveRecords, input.date, `${label}.leaveRecords`)
  if (input.recordState !== 'finalized') {
    throw new Error(`${label}.recordState must be finalized`)
  }
  if (
    typeof input.commitment !== 'string' ||
    !commitments.has(input.commitment as Commitment)
  ) {
    throw new Error(`${label}.commitment is invalid`)
  }

  assertSafeNonNegativeInteger(
    input.commitmentFocusMinutes,
    `${label}.commitmentFocusMinutes`,
  )
  assertSafeNonNegativeInteger(
    input.optionalFocusMinutes,
    `${label}.optionalFocusMinutes`,
  )
  assertSafeNonNegativeInteger(
    input.focusTotalMinutes,
    `${label}.focusTotalMinutes`,
  )
  if (Object.hasOwn(input, 'habitFocusMinutes')) {
    assertSafeNonNegativeInteger(input.habitFocusMinutes, `${label}.habitFocusMinutes`)
    assertSafeNonNegativeInteger(input.habitCompleted, `${label}.habitCompleted`)
    assertTaskRows(input.habitTasks, `${label}.habitTasks`)
  }
  if (
    input.focusTotalMinutes !==
    input.commitmentFocusMinutes + input.optionalFocusMinutes + ((input.habitFocusMinutes as number | undefined) ?? 0)
  ) {
    throw new Error(
      `${label} Focus total must equal commitment Focus plus optional Focus plus habit Focus`,
    )
  }
  assertSafeNonNegativeInteger(input.optionalCompleted, `${label}.optionalCompleted`)
  assertIsoTimestamp(input.finalizedAt, `${label}.finalizedAt`)
  assertTaskRows(input.minimumTasks, `${label}.minimumTasks`)
  assertTaskRows(input.optionalTasks, `${label}.optionalTasks`)
}

function assertMissingDay(input: Record<string, unknown>, index: number): void {
  const label = `Missing day at days[${index}]`
  assertKeys(input, ['date', 'recordState', ...(Object.hasOwn(input, 'leaveRecords') ? ['leaveRecords'] : [])], label)
  assertIsoDate(input.date, `${label}.date`)
  if (Object.hasOwn(input, 'leaveRecords')) assertLeaveRecords(input.leaveRecords, input.date, `${label}.leaveRecords`)
  if (input.recordState !== 'missing') {
    throw new Error(`${label}.recordState must be missing`)
  }
}

function nextDate(date: string): string {
  const value = new Date(`${date}T00:00:00.000Z`)
  value.setUTCDate(value.getUTCDate() + 1)
  return value.toISOString().slice(0, 10)
}

function assertCoverage(
  coverage: unknown,
  days: unknown[],
): Coverage | null {
  if (coverage === null) {
    if (days.length !== 0) {
      throw new Error('Coverage null requires an empty days array')
    }
    return null
  }

  const range = asObject(coverage, 'Coverage')
  assertKeys(range, ['trackingStarted', 'eligibleThrough'], 'Coverage')
  assertIsoDate(range.trackingStarted, 'Coverage.trackingStarted')
  assertIsoDate(range.eligibleThrough, 'Coverage.eligibleThrough')
  if (range.trackingStarted > range.eligibleThrough) {
    throw new Error('Coverage trackingStarted must not be after eligibleThrough')
  }

  return {
    trackingStarted: range.trackingStarted,
    eligibleThrough: range.eligibleThrough,
  }
}

function assertDaySequence(days: unknown[], coverage: Coverage): void {
  let expectedDate = coverage.trackingStarted

  for (const [index, entry] of days.entries()) {
    const day = asObject(entry, `Day at days[${index}]`)
    if (day.recordState === 'finalized') {
      assertFinalizedDay(day, index)
    } else if (day.recordState === 'missing') {
      assertMissingDay(day, index)
    } else {
      throw new Error(`Day at days[${index}] has an invalid recordState`)
    }

    if (day.date !== expectedDate) {
      throw new Error(
        `Days must be consecutive and ordered: expected ${expectedDate} at days[${index}]`,
      )
    }
    expectedDate = nextDate(expectedDate)
  }

  if (expectedDate !== nextDate(coverage.eligibleThrough)) {
    throw new Error('Days must contain every date in coverage')
  }
}

export function parseHistory(input: unknown): HistoryPayload {
  const payload = asObject(input, 'History payload')
  assertKeys(
    payload,
    ['schema', 'schemaVersion', 'generatedAt', 'timezone', 'coverage', 'days'],
    'History payload',
  )
  if (payload.schema !== 'org-workflow-history' || payload.schemaVersion !== 1) {
    throw new Error('Unsupported Workflow history schema or version')
  }
  assertIsoTimestamp(payload.generatedAt, 'History payload.generatedAt')
  assertTimezone(payload.timezone, 'History payload.timezone')
  if (!Array.isArray(payload.days)) {
    throw new Error('History payload.days must be an array')
  }

  const coverage = assertCoverage(payload.coverage, payload.days)
  if (coverage !== null) {
    assertDaySequence(payload.days, coverage)
  }

  return input as HistoryPayload
}

export async function loadHistory(): Promise<LoadState> {
  try {
    const response = await fetch('/data/workflow-history.v1.json')
    if (!response.ok) throw new Error(`Snapshot request failed: ${response.status}`)
    return { kind: 'ready', payload: parseHistory(await response.json()) }
  } catch (error) {
    return {
      kind: 'error',
      message: error instanceof Error ? error.message : String(error),
    }
  }
}
