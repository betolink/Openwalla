import { useCallback, useEffect, useState } from 'react'
import {
  ArrowLeft,
  Download,
  Upload,
} from 'lucide-react'
import { api, type Device, type DeviceDetails } from '../api'
import { DeviceTrafficChart } from '../components/DeviceTrafficChart'
import { Badge, Button, Card, Empty, Stat } from '../components/ui'
import { formatBytes, formatDateTime } from '../utils/format'

const ranges = [
  { key: '1h', label: '1 hour', hours: 1 },
  { key: '12h', label: '12 hours', hours: 12 },
  { key: '1d', label: '1 day', hours: 24 },
  { key: '7d', label: '7 days', hours: 168 },
] as const

type RangeKey = (typeof ranges)[number]['key']

export function DeviceDetail({
  device,
  onBack,
}: {
  device: Device
  onBack: () => void
}) {
  const [hours, setHours] = useState(24)
  const [range, setRange] = useState<RangeKey>('1d')
  const [details, setDetails] = useState<DeviceDetails | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      setDetails(await api.getDeviceDetails(device.id, hours))
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to load details')
    } finally {
      setLoading(false)
    }
  }, [device.id, hours])

  useEffect(() => {
    void load()
  }, [load])

  const action = async (kind: 'block' | 'pause') => {
    setBusy(true)
    setError(null)
    try {
      if (kind === 'block') {
        await (device.blocked
          ? api.unblockDevice(device.id)
          : api.blockDevice(device.id))
      } else {
        await (device.paused
          ? api.resumeDevice(device.id)
          : api.pauseDevice(device.id))
      }
      await load()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Action failed')
    } finally {
      setBusy(false)
    }
  }

  const totals = details?.ranges[range]
  const summary = details?.summary ?? {}

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <Button onClick={onBack}>
            <span className="flex items-center gap-1.5">
              <ArrowLeft size={13} /> Back
            </span>
          </Button>
          <div>
            <div className="flex flex-wrap items-center gap-2">
              <h1 className="text-2xl font-semibold text-[var(--text-strong)]">
                {device.hostname || device.mac}
              </h1>
              <Badge tone={device.online ? 'emerald' : 'slate'}>
                {device.online ? 'online' : 'offline'}
              </Badge>
              {device.blocked && <Badge tone="rose">blocked</Badge>}
              {device.paused && <Badge tone="amber">paused</Badge>}
            </div>
            <p className="mt-1 text-sm text-[var(--subtle)]">
              {device.ipv4 || '—'} · {device.mac}
            </p>
          </div>
        </div>
        <div className="flex gap-2">
          <Button onClick={() => void action('block')} disabled={busy}>
            {device.blocked ? 'Unblock' : 'Block'}
          </Button>
          <Button onClick={() => void action('pause')} disabled={busy}>
            {device.paused ? 'Resume' : 'Pause'}
          </Button>
        </div>
      </div>

      {error && (
        <div className="rounded-xl border border-[var(--danger)] bg-[var(--danger-soft)] px-4 py-3 text-sm text-[var(--danger)]">
          {error}
        </div>
      )}

      <div className="flex flex-wrap gap-2">
        {ranges.map((item) => (
          <button
            key={item.key}
            onClick={() => {
              setHours(item.hours)
              setRange(item.key)
            }}
            className={`rounded-lg px-3 py-1.5 text-xs ${
              range === item.key
                ? 'bg-[var(--accent-soft)] text-[var(--accent-text)]'
                : 'bg-[var(--surface-2)] text-[var(--muted)] hover:text-[var(--text)]'
            }`}
          >
            {item.label}
          </button>
        ))}
      </div>

      <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Stat
          label="Download"
          value={formatBytes(totals?.download)}
          hint={`${range} total`}
        />
        <Stat
          label="Upload"
          value={formatBytes(totals?.upload)}
          hint={`${range} total`}
        />
        <Stat
          label="Websites"
          value={details?.websites.length ?? 0}
          hint={`${range} top sites`}
        />
        <Stat
          label="Status"
          value={device.online ? 'online' : 'offline'}
          hint={String(summary.status ?? device.connection)}
        />
      </section>

      <Card
        title="Traffic"
        subtitle={`Download and upload · last ${range}`}
        actions={
          <Badge tone="sky">
            <span className="flex items-center gap-1">
              <Download size={11} /> / <Upload size={11} />
            </span>
          </Badge>
        }
      >
        {loading ? (
          <Empty>Loading traffic…</Empty>
        ) : details && details.series.length > 0 ? (
          <DeviceTrafficChart data={details.series} />
        ) : (
          <Empty>No bandwidth samples yet for this time slice.</Empty>
        )}
      </Card>

      <div className="grid gap-6 xl:grid-cols-[2fr_1fr]">
        <Card title="Most visited websites" subtitle={`Top domains · last ${range}`}>
          <div className="overflow-x-auto">
            <table className="min-w-full text-left text-sm">
              <thead className="text-xs uppercase tracking-wide text-[var(--subtle)]">
                <tr>
                  <th className="px-3 py-2">Domain</th>
                  <th className="px-3 py-2">Application</th>
                  <th className="px-3 py-2">Protocol</th>
                  <th className="px-3 py-2">Visits</th>
                  <th className="px-3 py-2">Last seen</th>
                </tr>
              </thead>
              <tbody>
                {(details?.websites ?? []).map((site) => (
                  <tr
                    key={`${site.domain}-${site.app}-${site.protocol}`}
                    className="border-t border-[var(--border)]"
                  >
                    <td className="px-3 py-2 text-[var(--text)]">
                      {site.domain || '—'}
                    </td>
                    <td className="px-3 py-2 text-[var(--muted)]">
                      {site.app || '—'}
                    </td>
                    <td className="px-3 py-2 text-[var(--muted)]">
                      {site.protocol || '—'}
                    </td>
                    <td className="px-3 py-2 text-[var(--text)]">{site.visits}</td>
                    <td className="px-3 py-2 text-[var(--subtle)]">
                      {formatDateTime(site.last_seen)}
                    </td>
                  </tr>
                ))}
                {(details?.websites ?? []).length === 0 && (
                  <tr>
                    <td
                      className="px-3 py-6 text-center text-[var(--subtle)]"
                      colSpan={5}
                    >
                      No website history for this time slice.
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </Card>

        <Card title="Device information">
          <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-2 p-4 text-xs">
            <dt className="text-[var(--subtle)]">MAC</dt>
            <dd className="font-mono text-[var(--text)]">{device.mac}</dd>
            <dt className="text-[var(--subtle)]">IP</dt>
            <dd className="text-[var(--text)]">{device.ipv4 || '—'}</dd>
            <dt className="text-[var(--subtle)]">Vendor</dt>
            <dd className="text-[var(--text)]">
              {device.vendor || String(summary.vendor ?? '—')}
            </dd>
            <dt className="text-[var(--subtle)]">Type</dt>
            <dd className="text-[var(--text)]">
              {device.device_type || 'unknown'}
            </dd>
            <dt className="text-[var(--subtle)]">Connection</dt>
            <dd className="text-[var(--text)]">{device.connection}</dd>
            <dt className="text-[var(--subtle)]">First seen</dt>
            <dd className="text-[var(--text)]">
              {formatDateTime(device.first_seen)}
            </dd>
            <dt className="text-[var(--subtle)]">Last seen</dt>
            <dd className="text-[var(--text)]">
              {formatDateTime(device.last_seen)}
            </dd>
            <dt className="text-[var(--subtle)]">Tags</dt>
            <dd className="text-[var(--text)]">
              {device.tags?.join(', ') || '—'}
            </dd>
          </dl>
        </Card>
      </div>
    </div>
  )
}
