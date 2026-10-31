import { useCallback, useEffect, useState } from 'react'
import { api, type AdblockStatus } from '../api'
import {
  Badge,
  Button,
  Card,
  Field,
  Input,
  PageHeader,
  Stat,
} from '../components/ui'

export function Adblock() {
  const [status, setStatus] = useState<AdblockStatus | null>(null)
  const [enabled, setEnabled] = useState(false)
  const [blocklists, setBlocklists] = useState('')
  const [interval, setIntervalHours] = useState(24)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const [current, settings] = await Promise.all([
        api.getAdblockStatus(),
        api.getAdblockSettings(),
      ])
      setStatus(current)
      setEnabled(settings.enabled)
      setBlocklists(settings.blocklists.join(', '))
      setIntervalHours(settings.update_interval_hours)
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to load')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load])

  const save = async (event: React.FormEvent) => {
    event.preventDefault()
    setError(null)
    try {
      await api.updateAdblockSettings({
        enabled,
        blocklists: blocklists
          .split(',')
          .map((value) => value.trim())
          .filter(Boolean),
        update_interval_hours: Number(interval) || 24,
      })
      await load()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to save')
    }
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="Adblock & DNS"
        subtitle="Domain blocking state and blocklists"
        actions={
          <Button onClick={() => void load()} disabled={loading}>
            Refresh
          </Button>
        }
      />

      {error && (
        <div className="rounded-lg border border-[var(--danger)] bg-[var(--danger-soft)] px-4 py-3 text-sm text-[var(--danger)]">
          {error}
        </div>
      )}

      <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Stat
          label="Status"
          value={status?.enabled ? 'enabled' : 'disabled'}
          hint={status?.last_updated ? `updated ${status.last_updated}` : undefined}
        />
        <Stat
          label="Blocked domains"
          value={(status?.blocked_domains ?? status?.blocked_queries ?? 0).toLocaleString()}
        />
        <Stat label="Feeds" value={status?.blocklists?.length ?? 0} />
        <Stat label="Update interval" value={`${status?.update_interval_hours ?? 24}h`} />
      </section>

      <Card title="Settings">
        <form onSubmit={(event) => void save(event)} className="grid gap-4 p-4">
          <label className="flex items-center gap-2 text-sm text-[var(--text)]">
            <input
              type="checkbox"
              checked={enabled}
              onChange={(event) => setEnabled(event.target.checked)}
            />
            Enable adblock
          </label>
          <Field label="Blocklists (comma separated)">
            <Input
              value={blocklists}
              placeholder="stevenblack, oisd"
              onChange={(event) => setBlocklists(event.target.value)}
            />
          </Field>
          <Field label="Update interval (hours)">
            <Input
              type="number"
              min={1}
              value={interval}
              onChange={(event) => setIntervalHours(Number(event.target.value))}
            />
          </Field>
          <div>
            <Button type="submit" variant="primary">
              Save settings
            </Button>
          </div>
        </form>
      </Card>

      <Card title="Configured blocklists">
        <div className="flex flex-wrap gap-2 p-4">
          {(status?.blocklists ?? []).map((list) => (
            <Badge key={list} tone="sky">
              {list}
            </Badge>
          ))}
          {(status?.blocklists ?? []).length === 0 && (
            <p className="text-sm text-[var(--subtle)]">No blocklists configured.</p>
          )}
        </div>
      </Card>
    </div>
  )
}
