import { useEffect, useMemo, useState } from 'react'
import {
  type FinalizedDay,
  type HistoryDay,
  type HistoryPayload,
  type LoadState,
  loadHistory,
} from './history'

export function focusLevel(minutes: number): number {
  if (minutes === 0) return 0
  if (minutes < 25) return 1
  if (minutes < 50) return 2
  if (minutes < 90) return 3
  return 4
}

export function currentMetStreak(days: HistoryDay[]): number {
  let streak = 0

  for (let index = days.length - 1; index >= 0; index -= 1) {
    const day = days[index]
    if (day.recordState !== 'finalized' || day.commitment !== 'met') break
    streak += 1
  }

  return streak
}

function isFinalized(day: HistoryDay): day is FinalizedDay {
  return day.recordState === 'finalized'
}

function formatMinutes(minutes: number): string {
  return `${minutes} min`
}

function formatDuration(minutes: number): string {
  const hours = Math.floor(minutes / 60)
  const remainder = minutes % 60

  if (hours === 0) return formatMinutes(remainder)
  if (remainder === 0) return `${hours}h`
  return `${hours}h ${remainder}m`
}

function formatCalendarDate(date: string): string {
  return new Intl.DateTimeFormat('en-US', {
    day: 'numeric',
    month: 'short',
    timeZone: 'UTC',
    year: 'numeric',
  }).format(new Date(`${date}T12:00:00Z`))
}

function formatSnapshotTime(timestamp: string, timezone: string): string {
  return new Intl.DateTimeFormat('en-US', {
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
    month: 'short',
    timeZone: timezone,
    year: 'numeric',
  }).format(new Date(timestamp))
}

function formatShortDate(date: string): string {
  return new Intl.DateTimeFormat('en-US', {
    day: 'numeric',
    month: 'short',
    timeZone: 'UTC',
  }).format(new Date(`${date}T12:00:00Z`))
}

function DashboardHeader({ payload }: { payload: HistoryPayload }) {
  const coverage = payload.coverage === null
    ? 'Not started'
    : `${formatCalendarDate(payload.coverage.trackingStarted)} – ${formatCalendarDate(payload.coverage.eligibleThrough)}`

  return (
    <header className="dashboard-header">
      <div className="header-copy">
        <p className="eyebrow">Read-only historical review</p>
        <h1>Workflow history</h1>
        <p className="header-lead">A quiet view of finalized Journal facts.</p>
      </div>
      <dl className="snapshot-meta">
        <div>
          <dt>Coverage</dt>
          <dd>{coverage}</dd>
        </div>
        <div>
          <dt>Snapshot</dt>
          <dd>
            <time dateTime={payload.generatedAt}>
              {formatSnapshotTime(payload.generatedAt, payload.timezone)}
            </time>
          </dd>
        </div>
        <div>
          <dt>Timezone</dt>
          <dd>{payload.timezone}</dd>
        </div>
      </dl>
    </header>
  )
}

const weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
const leaveSlotLabels = { morning: 'Morning', afternoon: 'Afternoon', evening: 'Evening' }
const commitmentSymbols = {
  met: '✓',
  unmet: '!',
  untouch: '○',
} as const

function groupDaysByMonth(days: HistoryDay[]) {
  const groups = new Map<string, HistoryDay[]>()

  for (const day of days) {
    const key = day.date.slice(0, 7)
    const group = groups.get(key)
    if (group === undefined) groups.set(key, [day])
    else group.push(day)
  }

  return Array.from(groups, ([key, monthDays]) => {
    const firstCoveredDay = Number(monthDays[0].date.slice(-2))
    const monthStart = new Date(`${key}-01T12:00:00Z`)
    const mondayBasedWeekday = (monthStart.getUTCDay() + 6) % 7

    return {
      key,
      label: new Intl.DateTimeFormat('en-US', {
        month: 'long',
        timeZone: 'UTC',
        year: 'numeric',
      }).format(monthStart),
      leadingBlanks: mondayBasedWeekday + firstCoveredDay - 1,
      days: monthDays,
    }
  })
}

function Calendar({
  days,
  selectedDate,
  onSelect,
}: {
  days: HistoryDay[]
  selectedDate: string | null
  onSelect: (date: string) => void
}) {
  const months = groupDaysByMonth(days)

  return (
    <section className="panel calendar-panel" aria-labelledby="focus-calendar-title">
      <h2 id="focus-calendar-title">Focus calendar</h2>
      <div className="calendar-months">
        {months.map((month) => (
          <article
            key={month.key}
            className="calendar-month"
            aria-labelledby={`month-${month.key}`}
          >
            <h3 id={`month-${month.key}`}>{month.label}</h3>
            <div className="calendar-weekdays" aria-hidden="true">
              {weekdayLabels.map((weekday) => <span key={weekday}>{weekday}</span>)}
            </div>
            <div className="calendar-grid">
              {Array.from({ length: month.leadingBlanks }, (_, index) => (
                <span key={`blank-${index}`} className="calendar-blank" aria-hidden="true" />
              ))}
              {month.days.map((day) => {
                const finalized = isFinalized(day)
                const hasLeave = Boolean(day.leaveRecords?.length)
                const label = (finalized
                  ? `${day.date}: Focus ${day.focusTotalMinutes} minutes; commitment ${day.commitment}`
                  : `${day.date}: unavailable; no finalized Journal record`) + (hasLeave ? '; leave recorded' : '')
                const classes = finalized
                  ? `calendar-day focus-level-${focusLevel(day.focusTotalMinutes)}`
                  : 'calendar-day is-missing'

                return (
                  <button
                    key={day.date}
                    className={classes}
                    type="button"
                    aria-label={label}
                    aria-pressed={selectedDate === day.date}
                    onClick={() => onSelect(day.date)}
                  >
                    <time dateTime={day.date}>{Number(day.date.slice(-2))}</time>
                    {hasLeave && <span className="leave-marker" aria-hidden="true">L</span>}
                    {finalized && (
                      <span
                        className={`commitment-marker commitment-${day.commitment}`}
                        aria-hidden="true"
                      >
                        {commitmentSymbols[day.commitment]}
                      </span>
                    )}
                  </button>
                )
              })}
            </div>
          </article>
        ))}
      </div>
      <div className="calendar-legend" aria-label="Calendar legend">
        <div className="focus-legend">
          <span>Less Focus</span>
          {[0, 1, 2, 3, 4].map((level) => (
            <span
              key={level}
              className={`legend-swatch focus-level-${level}`}
              aria-hidden="true"
            />
          ))}
          <span>More</span>
          <span className="legend-swatch is-missing" aria-hidden="true" />
          <span>Missing</span>
        </div>
        <div className="commitment-legend">
          <span><b aria-hidden="true">✓</b> Met</span>
          <span><b aria-hidden="true">!</b> Unmet</span>
          <span><b aria-hidden="true">○</b> Untouch</span>
          <span><b aria-hidden="true">L</b> Leave recorded</span>
        </div>
      </div>
    </section>
  )
}

function Summary({ days }: { days: HistoryDay[] }) {
  const finalized = days.filter(isFinalized)
  const focusTotal = finalized.reduce((total, day) => total + day.focusTotalMinutes, 0)
  const commitmentTotal = finalized.reduce(
    (total, day) => total + day.commitmentFocusMinutes,
    0,
  )
  const optionalTotal = finalized.reduce(
    (total, day) => total + day.optionalFocusMinutes,
    0,
  )
  const habitTrackedDays = finalized.filter((day) => day.habitFocusMinutes !== undefined).length
  const habitTotal = finalized.reduce((total, day) => total + (day.habitFocusMinutes ?? 0), 0)
  const habitShare = focusTotal === 0 ? 0 : (habitTotal / focusTotal) * 100
  const metDays = finalized.filter((day) => day.commitment === 'met').length
  const activeDays = finalized.filter((day) => day.focusTotalMinutes > 0).length
  const commitmentShare = focusTotal === 0 ? 0 : (commitmentTotal / focusTotal) * 100
  const optionalShare = focusTotal === 0 ? 0 : (optionalTotal / focusTotal) * 100

  return (
    <section className="panel summary-panel" aria-labelledby="summary-title">
      <h2 id="summary-title">Summary</h2>
      <dl className="summary-grid">
        <div>
          <dt>Total Focus</dt>
          <dd>{formatDuration(focusTotal)}</dd>
        </div>
        <div>
          <dt>Active days</dt>
          <dd>{activeDays}</dd>
        </div>
        <div>
          <dt>Met days</dt>
          <dd>{metDays}</dd>
        </div>
        <div>
          <dt>Current streak</dt>
          <dd>{currentMetStreak(days)}</dd>
        </div>
      </dl>
      <div className="focus-split">
        <div className="focus-split-labels">
          <span>Commitment {formatDuration(commitmentTotal)}</span>
          <span>Optional {formatDuration(optionalTotal)}</span>
          <span>Habits {habitTrackedDays ? formatDuration(habitTotal) : "not tracked"}{habitTrackedDays > 0 && habitTrackedDays < finalized.length ? " (tracked days)" : ""}</span>
        </div>
        <div
          className="focus-split-track"
          role="img"
          aria-label={`${commitmentTotal} commitment Focus minutes and ${optionalTotal} optional Focus minutes and ${habitTrackedDays ? `${habitTotal} habit Focus minutes` : "habit Focus not tracked"}`}
        >
          <span className="focus-split-commitment" style={{ width: `${commitmentShare}%` }} />
          <span className="focus-split-optional" style={{ width: `${optionalShare}%` }} />
          <span className="focus-split-habit" style={{ width: `${habitShare}%` }} />
        </div>
        <p>{finalized.length} finalized · {days.length} covered days</p>
      </div>
    </section>
  )
}

function Trend({ days }: { days: HistoryDay[] }) {
  const maximum = Math.max(
    1,
    ...days.filter(isFinalized).map((day) => day.focusTotalMinutes),
  )

  return (
    <section className="panel trend-panel" aria-labelledby="trend-title">
      <div className="section-heading">
        <div>
          <p className="section-kicker">Across the coverage</p>
          <h2 id="trend-title">Daily trend</h2>
        </div>
        <div className="split-key" aria-hidden="true">
          <span><i className="key-commitment" /> Commitment</span>
          <span><i className="key-optional" /> Optional</span>
          <span><i className="key-habit" /> Habits</span>
        </div>
      </div>
      <ol className="trend-list">
        {days.map((day) => {
          if (!isFinalized(day)) {
            return (
              <li
                key={day.date}
                className="trend-day is-missing"
                aria-label={`${day.date}: unavailable; no finalized Journal record`}
              >
                <time dateTime={day.date}>{formatShortDate(day.date)}</time>
                <span className="status-badge status-missing">MISSING</span>
                <div className="trend-bars is-missing" aria-hidden="true" />
                <span className="trend-total">Unavailable</span>
              </li>
            )
          }

          const commitmentWidth = (day.commitmentFocusMinutes / maximum) * 100
          const optionalWidth = (day.optionalFocusMinutes / maximum) * 100
          const habitWidth = ((day.habitFocusMinutes ?? 0) / maximum) * 100
          return (
            <li
              key={day.date}
              className="trend-day"
              aria-label={`${day.date}: ${day.commitmentFocusMinutes} commitment minutes and ${day.optionalFocusMinutes} optional minutes and ${day.habitFocusMinutes === undefined ? "habits not tracked" : `${day.habitFocusMinutes} habit minutes`}; commitment ${day.commitment}`}
            >
              <time dateTime={day.date}>{formatShortDate(day.date)}</time>
              <span className={`status-badge status-${day.commitment}`}>
                {day.commitment.toUpperCase()}
              </span>
              <div className="trend-bars" aria-hidden="true">
                <span className="trend-commitment" style={{ width: `${commitmentWidth}%` }} />
                <span className="trend-optional" style={{ width: `${optionalWidth}%` }} />
                <span className="trend-habit" style={{ width: `${habitWidth}%` }} />
              </div>
              <span className="trend-total">{formatDuration(day.focusTotalMinutes)}</span>
            </li>
          )
        })}
      </ol>
    </section>
  )
}

const outcomeLabels = {
  pending: 'Pending',
  done: 'Done',
  ready: 'Ready',
  held: 'Held',
  focused: 'Focused',
} as const

function TaskList({ title, tasks }: { title: string; tasks: FinalizedDay['minimumTasks'] }) {
  return (
    <div className="task-list">
      <h3>{title}</h3>
      {tasks.length === 0 ? (
        <p>None</p>
      ) : (
        <ul>
          {tasks.map((task, index) => (
            <li key={`${task.task}-${index}`} className="task-row">
              <span className="task-title">{task.task}</span>
              <span className={`outcome-badge outcome-${task.outcome}`}>
                {outcomeLabels[task.outcome]}
              </span>
              <span className="task-focus">
                <span className="visually-hidden">Focus: </span>
                {formatMinutes(task.focusMinutes)}
              </span>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

function Detail({ day }: { day: HistoryDay | undefined }) {
  return (
    <section className="detail-panel" aria-labelledby="detail-title" aria-live="polite">
      <div className="section-heading detail-heading">
        <div>
          <p className="section-kicker">Selected record</p>
          <h2 id="detail-title">Day detail</h2>
        </div>
        {day !== undefined && (
          <time className="selected-date" dateTime={day.date}>
            {formatCalendarDate(day.date)}
          </time>
        )}
      </div>
      {day === undefined ? (
        <p>Select a date to inspect its finalized record.</p>
      ) : day.recordState === 'missing' ? (
        <div className="missing-detail">
          <span className="status-badge status-missing">MISSING</span>
          <p>No finalized Journal record exists for this date.</p>
        </div>
      ) : (
        <>
          <span className={`status-badge detail-status status-${day.commitment}`}>
            {day.commitment.toUpperCase()}
          </span>
          <div className="detail-totals">
            <p>Focus total: {formatMinutes(day.focusTotalMinutes)}</p>
            <p>Commitment Focus: {formatMinutes(day.commitmentFocusMinutes)}</p>
            <p>Optional Focus: {formatMinutes(day.optionalFocusMinutes)}</p>
            <p>Optional completed: {day.optionalCompleted}</p>
            <p>Habit Focus: {day.habitFocusMinutes === undefined ? "Not tracked" : formatMinutes(day.habitFocusMinutes)}</p>
            <p>Habits completed: {day.habitCompleted ?? "Not tracked"}</p>
            <p>Commitment state: {day.commitment}</p>
          </div>
          <TaskList title="Minimum Commitment Progress" tasks={day.minimumTasks} />
          <TaskList title="Optional Work" tasks={day.optionalTasks} />
          {day.habitTasks && <TaskList title="Habits" tasks={day.habitTasks} />}
        </>
      )}
      {day?.leaveRecords?.map(record => (
        <div className="leave-detail" key={record.id}>
          <h3>Leave · {record.slots.map(slot => leaveSlotLabels[slot]).join(' / ')}</h3>
          <p>{record.reason}</p>
          {record.tasks.length > 0 && (
            <ul>{record.tasks.map((task, index) => <li key={index}>{task.task}</li>)}</ul>
          )}
        </div>
      ))}
    </section>
  )
}

function ReadyApp({ state }: { state: Extract<LoadState, { kind: 'ready' }> }) {
  const [selectedDate, setSelectedDate] = useState<string | null>(
    state.payload.coverage?.eligibleThrough ?? null,
  )
  const selectedDay = useMemo(
    () => state.payload.days.find((day) => day.date === selectedDate),
    [selectedDate, state.payload.days],
  )

  if (state.payload.coverage === null) {
    return (
      <main className="history-dashboard">
        <DashboardHeader payload={state.payload} />
        <section className="panel empty-state" aria-labelledby="empty-history-title">
          <h2 id="empty-history-title">No finalized history yet</h2>
          <p>The snapshot has no eligible Journal coverage to review.</p>
        </section>
      </main>
    )
  }

  if (!state.payload.days.some(isFinalized)) {
    return (
      <main className="history-dashboard">
        <DashboardHeader payload={state.payload} />
        <section className="panel empty-state" aria-labelledby="no-finalized-title">
          <h2 id="no-finalized-title">No finalized records in this coverage</h2>
          <p>Covered dates remain unavailable until a trustworthy Journal seal exists.</p>
        </section>
        <div className="review-grid">
          <Calendar
            days={state.payload.days}
            selectedDate={selectedDate}
            onSelect={setSelectedDate}
          />
          <Detail day={selectedDay} />
        </div>
      </main>
    )
  }

  return (
    <main className="history-dashboard">
      <DashboardHeader payload={state.payload} />
      <Summary days={state.payload.days} />
      <div className="review-grid">
        <Calendar
          days={state.payload.days}
          selectedDate={selectedDate}
          onSelect={setSelectedDate}
        />
        <Detail day={selectedDay} />
      </div>
      <Trend days={state.payload.days} />
    </main>
  )
}

export default function App() {
  const [state, setState] = useState<LoadState | null>(null)

  useEffect(() => {
    let active = true
    loadHistory().then((nextState) => {
      if (active) setState(nextState)
    })
    return () => {
      active = false
    }
  }, [])

  if (state === null) {
    return (
      <main className="history-dashboard state-screen">
        <p role="status">Loading historical review…</p>
      </main>
    )
  }

  if (state.kind === 'error') {
    return (
      <main className="history-dashboard state-screen" role="alert">
        <p>Unable to load history: {state.message}</p>
      </main>
    )
  }

  return <ReadyApp state={state} />
}
