import { afterEach, describe, expect, it, vi } from 'vitest'
import { loadHistory, parseHistory } from './history'

const validPayload = {
  schema: 'org-workflow-history',
  schemaVersion: 1,
  generatedAt: '2026-08-30T22:05:00+08:00',
  timezone: 'Asia/Shanghai',
  coverage: {
    trackingStarted: '2026-08-30',
    eligibleThrough: '2026-08-30',
  },
  days: [
    {
      date: '2026-08-30',
      recordState: 'finalized',
      commitment: 'met',
      commitmentFocusMinutes: 30,
      optionalFocusMinutes: 15,
      focusTotalMinutes: 45,
      optionalCompleted: 1,
      finalizedAt: '2026-08-30T22:00:00+08:00',
      minimumTasks: [
        { task: '完成中文任务', outcome: 'done', focusMinutes: 30 },
      ],
      optionalTasks: [
        { task: 'Read notes', outcome: 'ready', focusMinutes: 15 },
      ],
    },
  ],
}

function jsonResponse(input: unknown, status = 200): Response {
  return new Response(JSON.stringify(input), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
  })
}

function installFetch(response: Response) {
  const request = vi.fn().mockResolvedValue(response)
  vi.stubGlobal('fetch', request)
  return request
}

function payloadWithoutCoverage(): Record<string, unknown> {
  const payload: Record<string, unknown> = { ...validPayload }
  delete payload.coverage
  return payload
}

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('parseHistory', () => {
  const leave = { id: 'leave-1', date: '2026-08-30', slots: ['evening'],
    reason: '朋友临时邀请聚会', recordedAt: '2026-08-30T21:00:00+08:00',
    tasks: [{ id: null, task: 'Read notes', slot: 'evening' }] }

  it('accepts optional leave on finalized and missing days without inventing Focus', () => {
    const finalized = { ...validPayload, days: [{ ...validPayload.days[0], leaveRecords: [leave] }] }
    expect(parseHistory(finalized)).toEqual(finalized)
    const missing = { ...validPayload, days: [{ date: leave.date, recordState: 'missing', leaveRecords: [leave] }] }
    expect(parseHistory(missing)).toEqual(missing)
  })
  it('accepts unknown historical task slots without inferring a new schedule', () => {
    const record = { ...leave, tasks: [{ id: null, task: 'Yesterday task', slot: null }] }
    expect(parseHistory({ ...validPayload, days: [{ ...validPayload.days[0], leaveRecords: [record] }] }).days[0].leaveRecords?.[0].tasks[0].slot).toBeNull()
  })

  it.each([
    { ...leave, slots: [] }, { ...leave, slots: ['night'] },
    { ...leave, slots: ['evening', 'evening'] }, { ...leave, date: '2026-08-29' },
    { ...leave, reason: ' ' }, { ...leave, recordedAt: 'invalid' },
    { ...leave, tasks: [{ id: null, task: 'Read notes', slot: 'morning' }] },
  ])('rejects malformed leave records %#', (record) => {
    expect(() => parseHistory({ ...validPayload, days: [{ ...validPayload.days[0], leaveRecords: [record] }] })).toThrow(/leaveRecords/)
  })

  it('preserves a valid UTF-8 payload including Chinese task text', () => {
    expect(parseHistory(validPayload)).toEqual(validPayload)
  })

  it('rejects required fields inherited from a payload prototype', () => {
    expect(() => parseHistory(Object.create(validPayload))).toThrow(
      /missing required field: schema/i,
    )
  })

  it('accepts an empty history when coverage is null', () => {
    const emptyHistory = { ...validPayload, coverage: null, days: [] }

    expect(parseHistory(emptyHistory)).toEqual(emptyHistory)
  })

  it('rejects an unsupported schema version', () => {
    expect(() =>
      parseHistory({ ...validPayload, schemaVersion: 2 }),
    ).toThrow(/schema/i)
  })

  it('rejects a timezone that Intl cannot render', () => {
    expect(() =>
      parseHistory({ ...validPayload, timezone: 'Invalid/Zone' }),
    ).toThrow(/timezone/i)
  })

  it('rejects a missing day with finalized minutes', () => {
    expect(() =>
      parseHistory({
        ...validPayload,
        days: [
          {
            date: '2026-08-30',
            recordState: 'missing',
            focusTotalMinutes: 0,
          },
        ],
      }),
    ).toThrow(/missing/i)
  })

  it('rejects an untouch finalized day without all totals', () => {
    expect(() =>
      parseHistory({
        ...validPayload,
        days: [
          {
            date: '2026-08-30',
            recordState: 'finalized',
            commitment: 'untouch',
            commitmentFocusMinutes: 20,
            optionalFocusMinutes: 0,
            optionalCompleted: 0,
            finalizedAt: '2026-08-30T22:00:00+08:00',
            minimumTasks: [],
            optionalTasks: [],
          },
        ],
      }),
    ).toThrow(/finalized/i)
  })

  it('rejects a finalized day whose Focus total disagrees with its split', () => {
    expect(() =>
      parseHistory({
        ...validPayload,
        days: [
          {
            ...validPayload.days[0],
            focusTotalMinutes: 46,
          },
        ],
      }),
    ).toThrow(/focus total/i)
  })

  it.each([
    {
      name: 'missing coverage',
      payload: payloadWithoutCoverage(),
      message: /coverage/i,
    },
    {
      name: 'non-object coverage',
      payload: { ...validPayload, coverage: [] },
      message: /coverage/i,
    },
    {
      name: 'coverage with malformed dates',
      payload: {
        ...validPayload,
        coverage: {
          trackingStarted: '2026-02-30',
          eligibleThrough: '2026-08-30',
        },
      },
      message: /coverage/i,
    },
    {
      name: 'null coverage with a day',
      payload: { ...validPayload, coverage: null },
      message: /coverage/i,
    },
    {
      name: 'coverage that runs backward',
      payload: {
        ...validPayload,
        coverage: {
          trackingStarted: '2026-08-31',
          eligibleThrough: '2026-08-30',
        },
      },
      message: /coverage/i,
    },
    {
      name: 'non-consecutive coverage days',
      payload: {
        ...validPayload,
        coverage: {
          trackingStarted: '2026-08-30',
          eligibleThrough: '2026-09-01',
        },
        days: [
          validPayload.days[0],
          { date: '2026-09-01', recordState: 'missing' },
        ],
      },
      message: /days/i,
    },
    {
      name: 'unsorted coverage days',
      payload: {
        ...validPayload,
        coverage: {
          trackingStarted: '2026-08-30',
          eligibleThrough: '2026-08-31',
        },
        days: [
          { date: '2026-08-31', recordState: 'missing' },
          validPayload.days[0],
        ],
      },
      message: /days/i,
    },
  ])('rejects $name', ({ payload, message }) => {
    expect(() => parseHistory(payload)).toThrow(message)
  })
})

describe('loadHistory', () => {
  it('returns the validated payload after a successful static fetch', async () => {
    const request = installFetch(jsonResponse(validPayload))

    await expect(loadHistory()).resolves.toEqual({
      kind: 'ready',
      payload: validPayload,
    })
    expect(request).toHaveBeenCalledWith('/data/workflow-history.v1.json')
  })

  it('returns a readable error state for an HTTP failure', async () => {
    installFetch(jsonResponse({ error: 'unavailable' }, 503))

    await expect(loadHistory()).resolves.toEqual({
      kind: 'error',
      message: 'Snapshot request failed: 503',
    })
  })

  it('returns a readable error state for invalid JSON', async () => {
    installFetch(
      new Response('{', {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      }),
    )

    await expect(loadHistory()).resolves.toMatchObject({
      kind: 'error',
      message: expect.stringMatching(/json|unexpected/i),
    })
  })

  it('returns a readable error state for an invalid payload', async () => {
    installFetch(jsonResponse({ ...validPayload, schemaVersion: 2 }))

    await expect(loadHistory()).resolves.toMatchObject({
      kind: 'error',
      message: expect.stringMatching(/schema/i),
    })
  })
})

it('accepts habit facts as a separate contribution to total focus', () => {
  const payload = structuredClone(validPayload)
  Object.assign(payload.days[0], {
    habitFocusMinutes: 20,
    habitCompleted: 1,
    habitTasks: [{ task: 'SICP', outcome: 'done', focusMinutes: 20 }],
    focusTotalMinutes: 65,
  })
  expect(parseHistory(payload).days[0]).toMatchObject({
    focusTotalMinutes: 65, optionalFocusMinutes: 15, habitFocusMinutes: 20,
  })
  payload.days[0].focusTotalMinutes = 45
  expect(() => parseHistory(payload)).toThrow(/Focus total/)
})
