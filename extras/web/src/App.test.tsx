import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import App, { currentMetStreak, focusLevel } from './App'
import type { HistoryPayload } from './history'

const fixture: HistoryPayload = {
  schema: 'org-workflow-history',
  schemaVersion: 1,
  generatedAt: '2026-09-04T22:05:00+08:00',
  timezone: 'Asia/Shanghai',
  coverage: {
    trackingStarted: '2026-08-30',
    eligibleThrough: '2026-09-04',
  },
  days: [
    {
      date: '2026-08-30',
      recordState: 'finalized',
      commitment: 'met',
      commitmentFocusMinutes: 90,
      optionalFocusMinutes: 0,
      focusTotalMinutes: 90,
      optionalCompleted: 0,
      finalizedAt: '2026-08-30T22:00:00+08:00',
      minimumTasks: [
        { task: '完成中文最小任务', outcome: 'done', focusMinutes: 90 },
        { task: 'Queued follow-up', outcome: 'pending', focusMinutes: 0 },
        { task: 'Prepared review', outcome: 'ready', focusMinutes: 0 },
        { task: 'Deferred item', outcome: 'held', focusMinutes: 0 },
        { task: 'Focused item', outcome: 'focused', focusMinutes: 0 },
      ],
      optionalTasks: [],
    },
    {
      date: '2026-08-31',
      recordState: 'finalized',
      commitment: 'met',
      commitmentFocusMinutes: 15,
      optionalFocusMinutes: 0,
      focusTotalMinutes: 15,
      optionalCompleted: 0,
      finalizedAt: '2026-08-31T22:00:00+08:00',
      minimumTasks: [
        { task: 'Quick review', outcome: 'done', focusMinutes: 15 },
      ],
      optionalTasks: [],
    },
    {
      date: '2026-09-01',
      recordState: 'finalized',
      commitment: 'unmet',
      commitmentFocusMinutes: 20,
      optionalFocusMinutes: 0,
      focusTotalMinutes: 20,
      optionalCompleted: 0,
      finalizedAt: '2026-09-01T22:00:00+08:00',
      minimumTasks: [],
      optionalTasks: [],
    },
    { date: '2026-09-02', recordState: 'missing' },
    {
      date: '2026-09-03',
      recordState: 'finalized',
      commitment: 'untouch',
      commitmentFocusMinutes: 0,
      optionalFocusMinutes: 30,
      focusTotalMinutes: 30,
      optionalCompleted: 1,
      finalizedAt: '2026-09-03T22:00:00+08:00',
      minimumTasks: [],
      optionalTasks: [
        { task: 'Optional reading', outcome: 'done', focusMinutes: 30 },
      ],
    },
    {
      date: '2026-09-04',
      recordState: 'finalized',
      commitment: 'met',
      commitmentFocusMinutes: 50,
      optionalFocusMinutes: 25,
      focusTotalMinutes: 75,
      optionalCompleted: 1,
      finalizedAt: '2026-09-04T22:00:00+08:00',
      minimumTasks: [
        { task: 'Write reflection', outcome: 'done', focusMinutes: 50 },
      ],
      optionalTasks: [
        { task: '整理复习笔记', outcome: 'ready', focusMinutes: 25 },
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

function installFetch(response: Response): void {
  vi.stubGlobal('fetch', vi.fn().mockResolvedValue(response))
}

describe('leave records', () => {
  it.each(['missing', 'finalized'] as const)('shows reasons and affected tasks on %s days without changing metrics', async (state) => {
    const payload = structuredClone(fixture)
    const date = state === 'missing' ? '2026-09-02' : '2026-09-04'
    const day = payload.days.find(day => day.date === date)!
    day.leaveRecords = [{ id: 'leave-1', date, slots: ['evening'], reason: '朋友临时邀请聚会',
      recordedAt: `${date}T21:00:00+08:00`, tasks: [{ id: null, task: '未完成的学习', slot: 'evening' }] }]
    installFetch(jsonResponse(payload))
    render(<App />)
    const button = await screen.findByRole('button', { name: new RegExp(`${date}.*leave recorded`) })
    expect(within(button).getByText('L')).toBeVisible()
    fireEvent.click(button)
    expect(screen.getByRole('heading', { name: 'Leave · Evening' })).toBeVisible()
    expect(screen.getByText('朋友临时邀请聚会')).toBeVisible()
    expect(screen.getByText('未完成的学习')).toBeVisible()
    if (state === 'missing') {
      expect(button).toHaveClass('is-missing')
      expect(screen.getByText('No finalized Journal record exists for this date.')).toBeVisible()
    } else {
      expect(screen.getByText('Focus total: 75 min')).toBeVisible()
    }
  })
})

afterEach(() => {
  cleanup()
  vi.unstubAllGlobals()
})

describe('focusLevel', () => {
  it.each([
    [0, 0],
    [1, 1],
    [24, 1],
    [25, 2],
    [49, 2],
    [50, 3],
    [89, 3],
    [90, 4],
  ])('places %i Focus minutes in level %i', (minutes, level) => {
    expect(focusLevel(minutes)).toBe(level)
  })
})

describe('currentMetStreak', () => {
  it('stops at every non-met state, including untouch and missing', () => {
    const lastFinalized = fixture.days[fixture.days.length - 1]
    if (lastFinalized.recordState !== 'finalized') {
      throw new Error('Fixture must end with a finalized day')
    }

    expect(currentMetStreak(fixture.days)).toBe(1)
    expect(currentMetStreak([...fixture.days.slice(0, -1), { date: '2026-09-04', recordState: 'missing' }])).toBe(0)
    expect(currentMetStreak([...fixture.days.slice(0, -1), { ...lastFinalized, commitment: 'untouch' }])).toBe(0)
    expect(currentMetStreak([...fixture.days.slice(0, -1), { ...lastFinalized, commitment: 'unmet' }])).toBe(0)
  })
})

describe('App', () => {
  it('shows readable coverage, snapshot time, and timezone metadata', async () => {
    installFetch(jsonResponse(fixture))

    render(<App />)

    expect(await screen.findByText('Aug 30, 2026 – Sep 4, 2026')).toBeVisible()
    expect(screen.getByText(/Sep 4, 2026, 10:05 PM/)).toBeVisible()
    expect(screen.getByText('Asia/Shanghai')).toBeVisible()
    expect(screen.queryByText(fixture.generatedAt)).not.toBeInTheDocument()
  })

  it('summarizes finalized activity without treating a missing day as zero', async () => {
    installFetch(jsonResponse(fixture))

    render(<App />)

    const activeDays = await screen.findByText('Active days')
    expect(screen.getByText('3h 50m')).toBeVisible()
    expect(within(activeDays.parentElement!).getByText('5')).toBeVisible()
    expect(screen.getByText('5 finalized · 6 covered days')).toBeVisible()
  })

  it('uses a darker Focus level for 90 minutes than 15 minutes', async () => {
    installFetch(jsonResponse(fixture))

    render(<App />)

    const highFocusDay = await screen.findByRole('button', { name: /2026-08-30/i })
    const lowFocusDay = screen.getByRole('button', { name: /2026-08-31/i })
    expect(highFocusDay).toHaveClass('focus-level-4')
    expect(lowFocusDay).toHaveClass('focus-level-1')
  })

  it('groups the Focus calendar into weekday-aligned months', async () => {
    installFetch(jsonResponse(fixture))

    render(<App />)

    const augustHeading = await screen.findByRole('heading', { name: 'August 2026' })
    expect(augustHeading).toBeVisible()
    expect(screen.getByRole('heading', { name: 'September 2026' })).toBeVisible()
    expect(screen.getAllByText('Mon')).toHaveLength(2)
    expect(screen.getAllByText('Sun')).toHaveLength(2)
    expect(
      augustHeading.closest('article')!.querySelectorAll('.calendar-blank'),
    ).toHaveLength(34)
  })

  it('shows commitment state separately from Focus intensity', async () => {
    installFetch(jsonResponse(fixture))

    render(<App />)

    const metDay = await screen.findByRole('button', { name: /2026-08-30/i })
    const unmetDay = screen.getByRole('button', { name: /2026-09-01/i })
    const untouchDay = screen.getByRole('button', { name: /2026-09-03/i })

    expect(within(metDay).getByText('✓')).toBeVisible()
    expect(within(unmetDay).getByText('!')).toBeVisible()
    expect(within(untouchDay).getByText('○')).toBeVisible()
    expect(screen.getByText('Met')).toBeVisible()
    expect(screen.getByText('Unmet')).toBeVisible()
    expect(screen.getByText('Untouch')).toBeVisible()
  })

  it('labels a missing date as unavailable rather than Focus zero', async () => {
    installFetch(jsonResponse(fixture))

    render(<App />)

    const missingDay = await screen.findByRole('button', { name: /2026-09-02/i })
    expect(missingDay).toHaveAccessibleName(/unavailable|missing/i)
    expect(missingDay).not.toHaveAccessibleName(/focus.*0/i)
    expect(missingDay).toHaveClass('is-missing')
  })

  it('shows selected finalized lists and the exact missing-record message', async () => {
    installFetch(jsonResponse(fixture))

    render(<App />)

    fireEvent.click(await screen.findByRole('button', { name: /2026-08-30/i }))
    expect(screen.getByRole('heading', { name: 'Minimum Commitment Progress' })).toBeVisible()
    expect(screen.getByText('完成中文最小任务')).toBeVisible()
    expect(screen.getByRole('heading', { name: 'Optional Work' })).toBeVisible()

    for (const outcome of ['pending', 'done', 'ready', 'held', 'focused']) {
      expect(
        screen.getByText(new RegExp(`^${outcome}$`, 'i'), {
          selector: '.outcome-badge',
        }),
      ).toBeVisible()
    }

    fireEvent.click(screen.getByRole('button', { name: /2026-09-02/i }))
    expect(screen.getByText('No finalized Journal record exists for this date.')).toBeVisible()
  })

  it('keeps selected detail before the long trend and announces its updates', async () => {
    installFetch(jsonResponse(fixture))

    render(<App />)

    const detailHeading = await screen.findByRole('heading', { name: 'Day detail' })
    const trendHeading = screen.getByRole('heading', { name: 'Daily trend' })
    const detailSection = detailHeading.closest('section')

    expect(
      detailHeading.compareDocumentPosition(trendHeading) &
        Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy()
    expect(detailSection).toHaveAttribute('aria-live', 'polite')
  })

  it('shows every supported finalized root value and a selected Chinese optional task', async () => {
    installFetch(jsonResponse(fixture))

    render(<App />)

    fireEvent.click(await screen.findByRole('button', { name: /2026-09-04/i }))
    expect(screen.getByText('Focus total: 75 min')).toBeVisible()
    expect(screen.getByText('Commitment Focus: 50 min')).toBeVisible()
    expect(screen.getByText('Optional Focus: 25 min')).toBeVisible()
    expect(screen.getByText('Optional completed: 1')).toBeVisible()
    expect(screen.getByText('Commitment state: met')).toBeVisible()
    const optionalTask = screen.getByText('整理复习笔记').closest('li')
    expect(optionalTask).toBeVisible()
    expect(optionalTask).toHaveTextContent('Focus: 25 min')
    expect(
      screen.getByText(/^ready$/i, { selector: '.outcome-badge' }),
    ).toBeVisible()
  })

  it('does not give the calendar grid an invalid list role', async () => {
    installFetch(jsonResponse(fixture))

    render(<App />)

    await screen.findByRole('button', { name: /2026-08-30/i })
    expect(screen.queryByRole('list', { name: 'Historical Focus calendar' })).not.toBeInTheDocument()
  })

  it('shows loading and invalid-snapshot error states', async () => {
    const pending = new Promise<Response>(() => {})
    vi.stubGlobal('fetch', vi.fn().mockReturnValue(pending))

    const { unmount } = render(<App />)
    expect(screen.getByRole('status')).toHaveTextContent(/loading/i)
    unmount()

    installFetch(jsonResponse({ ...fixture, schemaVersion: 2 }))
    render(<App />)
    await waitFor(() => expect(screen.getByText(/unable to load/i)).toBeVisible())
  })

  it('does not present zero-value metrics when no history is tracked', async () => {
    installFetch(jsonResponse({ ...fixture, coverage: null, days: [] }))

    render(<App />)

    expect(
      await screen.findByRole('heading', { name: 'No finalized history yet' }),
    ).toBeVisible()
    expect(screen.queryByText('Total Focus')).not.toBeInTheDocument()
  })

  it('keeps covered missing dates distinct from finalized zero days', async () => {
    installFetch(jsonResponse({
      ...fixture,
      coverage: {
        trackingStarted: '2026-09-03',
        eligibleThrough: '2026-09-04',
      },
      days: [
        { date: '2026-09-03', recordState: 'missing' },
        { date: '2026-09-04', recordState: 'missing' },
      ],
    }))

    render(<App />)

    expect(
      await screen.findByRole('heading', { name: 'No finalized records in this coverage' }),
    ).toBeVisible()
    expect(screen.getAllByRole('button', { name: /unavailable/i })).toHaveLength(2)
    expect(screen.queryByText('Total Focus')).not.toBeInTheDocument()
  })

  it('does not expose workflow-changing actions', async () => {
    installFetch(jsonResponse(fixture))

    render(<App />)
    await screen.findByRole('button', { name: /2026-08-30/i })

    const prohibited = /schedule|start|stop|complete|save/i
    const actions = Array.from(document.querySelectorAll('button, a, input[type="submit"]'))
    expect(actions.some((action) => prohibited.test(action.textContent ?? action.getAttribute('aria-label') ?? ''))).toBe(false)
  })
})

it('shows habit focus and completed habit detail without changing commitment', async () => {
  const payload = structuredClone(fixture)
  const day = payload.days[payload.days.length - 1]
  if (day.recordState !== 'finalized') throw new Error('Expected finalized fixture')
  day.habitFocusMinutes = 20
  day.habitCompleted = 1
  day.habitTasks = [{ task: 'SICP practice', outcome: 'done', focusMinutes: 20 }]
  day.focusTotalMinutes += 20
  installFetch(jsonResponse(payload))
  render(<App />)
  expect(await screen.findByText('SICP practice')).toBeInTheDocument()
  expect(screen.getByText('Habits completed: 1')).toBeInTheDocument()
  expect(screen.getByText('Habit Focus: 20 min')).toBeInTheDocument()
})
