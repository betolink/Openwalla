import { useCallback, useEffect, useState } from 'react'
import { api, type EventItem } from '../api'
import { Badge, Button, Card, Empty, PageHeader } from '../components/ui'

function formatTime(value: string) {
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? value : date.toLocaleString()
}

export function Events() {
  const [events, setEvents] = useState<EventItem[]>([])
  const [severity, setSeverity] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const result = await api.listEvents({
        limit: 200,
        severity: severity || undefined,
      })
      setEvents(result.items)
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to load')
    } finally {
      setLoading(false)
    }
  }, [severity])

  useEffect(() => {
    void load()
  }, [load])

  return (
    <div className="space-y-6">
      <PageHeader
        title="Events"
        subtitle="Security, device and policy activity"
        actions={
          <div className="flex gap-2">
            <select
              className="rounded-lg border border-[var(--border)] bg-[var(--input-bg)] px-3 py-1.5 text-sm text-[var(--text)]"
              value={severity}
              onChange={(event) => setSeverity(event.target.value)}
            >
              <option value="">All severities</option>
              <option value="info">Info</option>
              <option value="warning">Warning</option>
              <option value="critical">Critical</option>
            </select>
            <Button onClick={() => void load()} disabled={loading}>
              Refresh
            </Button>
          </div>
        }
      />

      {error && (
        <div className="rounded-lg border border-[var(--danger)] bg-[var(--danger-soft)] px-4 py-3 text-sm text-[var(--danger)]">
          {error}
        </div>
      )}

      <Card>
        <div className="divide-y divide-[var(--border)]">
          {events.map((event) => (
            <div key={event.id} className="px-4 py-3">
              <div className="flex flex-wrap items-center gap-2">
                <Badge
                  tone={
                    event.severity === 'critical'
                      ? 'rose'
                      : event.severity === 'warning'
                        ? 'amber'
                        : 'slate'
                  }
                >
                  {event.severity}
                </Badge>
                <span className="text-xs text-[var(--subtle)]">{event.type}</span>
                <span className="text-xs text-[var(--subtle)]">
                  {formatTime(event.created_at)}
                </span>
              </div>
              <p className="mt-1 text-sm text-[var(--text)]">{event.message}</p>
            </div>
          ))}
          {events.length === 0 && <Empty>No events recorded.</Empty>}
        </div>
      </Card>
    </div>
  )
}
