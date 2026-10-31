import { useCallback, useEffect, useState } from 'react'
import { api, type FlowDashboard } from '../api'
import { Badge, Button, Card, Empty, PageHeader, Stat } from '../components/ui'

function formatBytes(value?: number) {
  if (!value) return '0 B'
  const units = ['B', 'KB', 'MB', 'GB', 'TB']
  let amount = value
  let unit = 0
  while (amount >= 1024 && unit < units.length - 1) {
    amount /= 1024
    unit += 1
  }
  return `${amount.toFixed(1)} ${units[unit]}`
}

function formatEpoch(value?: number | null) {
  if (!value) return '—'
  const date = new Date(value * 1000)
  return Number.isNaN(date.getTime()) ? '—' : date.toLocaleString()
}

export function Traffic() {
  const [summary, setSummary] = useState<FlowDashboard | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      setSummary(await api.getFlowDashboard(24))
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to load flows')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load])

  const flows = summary?.flows
  const collectorConnected = summary?.collector?.connected ?? false
  const recent = flows?.recent_flows ?? []

  return (
    <div className="space-y-6">
      <PageHeader
        title="Traffic & flows"
        subtitle="Netify flow collector, last 24 hours"
        actions={
          <Button onClick={() => void load()} disabled={loading}>
            {loading ? 'Refreshing…' : 'Refresh'}
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
          label="Collector"
          value={collectorConnected ? 'connected' : 'offline'}
          hint={summary?.collector?.last_error ?? undefined}
        />
        <Stat label="Flows (24h)" value={flows?.flow_count ?? 0} />
        <Stat label="Devices seen" value={flows?.device_count ?? 0} />
        <Stat label="Latest flow" value={formatEpoch(flows?.latest_flow)} />
      </section>

      {!collectorConnected && (
        <div className="rounded-lg border border-[var(--warning)] bg-[var(--warning-soft)] px-4 py-3 text-sm text-[var(--warning)]">
          The Netify collector is not connected. Install the OpenWalla Standard or
          Everything router components on betowrt to populate flows and DPI.
        </div>
      )}

      <div className="grid gap-6 lg:grid-cols-[1fr_2fr]">
        <Card title="Top applications">
          <div className="divide-y divide-[var(--border)]">
            {(flows?.top_applications ?? []).map((app) => (
              <div
                key={app.name}
                className="flex items-center justify-between px-4 py-2 text-sm"
              >
                <span className="text-[var(--text)]">{app.name}</span>
                <Badge tone="sky">{app.count}</Badge>
              </div>
            ))}
            {(flows?.top_applications ?? []).length === 0 && (
              <Empty>No application data yet.</Empty>
            )}
          </div>
        </Card>

        <Card
          title="Recent flows"
          subtitle={`${formatBytes(flows?.database_bytes)} stored`}
        >
          <div className="overflow-x-auto">
            <table className="min-w-full text-left text-sm">
              <thead className="text-xs uppercase tracking-wide text-[var(--subtle)]">
                <tr>
                  <th className="px-3 py-2">Time</th>
                  <th className="px-3 py-2">Source</th>
                  <th className="px-3 py-2">Destination</th>
                  <th className="px-3 py-2">Application</th>
                  <th className="px-3 py-2">Protocol</th>
                  <th className="px-3 py-2">Risk</th>
                </tr>
              </thead>
              <tbody>
                {recent.map((flow, index) => {
                  const row = flow as Record<string, unknown>
                  return (
                    <tr key={index} className="border-t border-[var(--border)]">
                      <td className="px-3 py-2 text-xs text-[var(--subtle)]">
                        {formatEpoch(Number(row.timeinsert ?? 0))}
                      </td>
                      <td className="px-3 py-2 text-[var(--text)]">
                        {String(row.local_ip ?? '—')}
                      </td>
                      <td className="px-3 py-2 text-[var(--muted)]">
                        {String(row.fqdn || row.dest_ip || '—')}
                      </td>
                      <td className="px-3 py-2 text-[var(--text)]">
                        {String(row.detected_app_name || row.detected_protocol_name || '—')}
                      </td>
                      <td className="px-3 py-2 text-[var(--muted)]">
                        {String(row.detected_protocol_name || '—')}
                      </td>
                      <td className="px-3 py-2">
                        {Number(row.ndpi_risk_score ?? 0) > 0 ? (
                          <Badge tone="rose">{String(row.ndpi_risk_score)}</Badge>
                        ) : (
                          <span className="text-[var(--subtle)]">0</span>
                        )}
                      </td>
                    </tr>
                  )
                })}
                {recent.length === 0 && (
                  <tr>
                    <td
                      className="px-3 py-6 text-center text-[var(--subtle)]"
                      colSpan={6}
                    >
                      No flows recorded yet.
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </Card>
      </div>
    </div>
  )
}
