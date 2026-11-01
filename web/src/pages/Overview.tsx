import { useCallback, useEffect, useState } from 'react'
import { Activity, Ban, Bell, ShieldCheck, Wifi } from 'lucide-react'
import {
  api,
  type Device,
  type EventItem,
  type FilteringStatus,
  type FlowDashboard,
  type NetworkUsage,
  type Router,
  type TrafficPoint,
} from '../api'
import { DeviceCard } from '../components/DeviceCard'
import { TrafficChart } from '../components/TrafficChart'
import { Badge, Button, Card, Empty, PageHeader, Stat } from '../components/ui'
import { formatBytes } from '../utils/format'

function formatTime(value?: string) {
  if (!value) return '—'
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? value : date.toLocaleString()
}

export function Overview({
  onOpenDevice,
}: {
  onOpenDevice?: (device: Device) => void
}) {
  const [routers, setRouters] = useState<Router[]>([])
  const [devices, setDevices] = useState<Device[]>([])
  const [filtering, setFiltering] = useState<FilteringStatus | null>(null)
  const [events, setEvents] = useState<EventItem[]>([])
  const [series, setSeries] = useState<TrafficPoint[]>([])
  const [flows, setFlows] = useState<FlowDashboard | null>(null)
  const [usage, setUsage] = useState<NetworkUsage | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState<string | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const [routerList, deviceList] = await Promise.all([
        api.listRouters(),
        api.listDevices({ limit: 500 }),
      ])
      setRouters(routerList.items)
      setDevices(deviceList.items)

      const [
        filteringResult,
        eventResult,
        seriesResult,
        flowResult,
        usageResult,
      ] = await Promise.allSettled([
        api.getFilteringStatus(),
        api.listEvents({ limit: 6 }),
        api.getTrafficSeries(24, 300),
        api.getFlowDashboard(24),
        api.getNetworkUsage(),
      ])
      setFiltering(
        filteringResult.status === 'fulfilled' ? filteringResult.value : null,
      )
      setEvents(
        eventResult.status === 'fulfilled' ? (eventResult.value.items ?? []) : [],
      )
      setSeries(
        seriesResult.status === 'fulfilled'
          ? (seriesResult.value.items ?? [])
          : [],
      )
      setFlows(flowResult.status === 'fulfilled' ? flowResult.value : null)
      setUsage(usageResult.status === 'fulfilled' ? usageResult.value : null)
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to load')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load])

  const handleAction = async (device: Device, action: 'block' | 'pause') => {
    setBusy(device.id)
    setError(null)
    try {
      if (action === 'block') {
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
      setBusy(null)
    }
  }

  const syncAll = async () => {
    setBusy('sync')
    setError(null)
    try {
      for (const router of routers) {
        await api.syncRouter(router.id)
      }
      await load()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Sync failed')
    } finally {
      setBusy(null)
    }
  }

  const primaryRouter = routers[0]
  const onlineRouters = routers.filter((router) => router.status === 'online').length
  const onlineDevices = devices.filter((device) => device.online).length
  const dnsActive = Boolean(
    filtering?.running && filtering?.protection_enabled,
  )
  const topApps = flows?.flows?.top_applications ?? []
  const maxApp = Math.max(1, ...topApps.map((app) => app.count))

  return (
    <div className="space-y-6">
      <PageHeader
        title="Network overview"
        subtitle="Firewalla-style visibility for your OpenWrt router"
        actions={
          <Button onClick={() => void load()} disabled={loading}>
            {loading ? 'Refreshing…' : 'Refresh'}
          </Button>
        }
      />

      {error && (
        <div className="rounded-xl border border-[var(--danger)] bg-[var(--danger-soft)] px-4 py-3 text-sm text-[var(--danger)]">
          {error}
        </div>
      )}

      <section className="relative overflow-hidden rounded-3xl border border-[var(--border)] bg-gradient-to-br from-[var(--surface-3)] via-[var(--surface)] to-[var(--bg)] p-6">
        <div className="absolute -right-20 -top-24 h-64 w-64 rounded-full bg-[var(--accent-soft)] blur-3xl" />
        <div className="relative flex flex-wrap items-center justify-between gap-6">
          <div className="flex items-center gap-4">
            <div
              className={`flex h-16 w-16 items-center justify-center rounded-2xl ${
                onlineRouters > 0
                  ? 'bg-[var(--success-soft)] text-[var(--success)]'
                  : 'bg-[var(--warning-soft)] text-[var(--warning)]'
              }`}
            >
              <ShieldCheck size={32} />
            </div>
            <div>
              <p className="text-[11px] uppercase tracking-[0.25em] text-[var(--subtle)]">
                Network status
              </p>
              <h1 className="text-2xl font-semibold text-[var(--text-strong)]">
                {onlineRouters > 0 ? 'Protected' : 'Attention needed'}
              </h1>
              <p className="mt-1 text-sm text-[var(--muted)]">
                {primaryRouter?.name ?? 'No router'} ·{' '}
                {primaryRouter?.model || 'model unknown'} ·{' '}
                {primaryRouter?.openwrt_version || 'version unknown'}
              </p>
            </div>
          </div>

          <div className="flex flex-wrap gap-6 text-sm">
            <div>
              <p className="text-[11px] uppercase tracking-wide text-[var(--subtle)]">
                Internet
              </p>
              <p className="mt-1 flex items-center gap-1.5 text-[var(--text)]">
                <Wifi size={14} />
                {onlineRouters > 0 ? 'online' : 'offline'}
              </p>
            </div>
            <div>
              <p className="text-[11px] uppercase tracking-wide text-[var(--subtle)]">
                Devices
              </p>
              <p className="mt-1 text-[var(--text)]">{onlineDevices} online</p>
            </div>
            <div>
              <p className="text-[11px] uppercase tracking-wide text-[var(--subtle)]">
                Flows 24h
              </p>
              <p className="mt-1 flex items-center gap-1.5 text-[var(--text)]">
                <Activity size={14} />
                {flows?.flows?.flow_count ?? 0}
              </p>
            </div>
            <div>
              <p className="text-[11px] uppercase tracking-wide text-[var(--subtle)]">
                Monthly usage
              </p>
              <p className="mt-1 text-[var(--text)]">
                {usage?.month ? formatBytes(usage.month.total) : '—'}
              </p>
              <p className="text-[11px] text-[var(--subtle)]">
                {usage?.month
                  ? `↓ ${formatBytes(usage.month.download)} · ↑ ${formatBytes(usage.month.upload)}`
                  : 'no data yet'}
              </p>
            </div>
            <div>
              <p className="text-[11px] uppercase tracking-wide text-[var(--subtle)]">
                Total transfer
              </p>
              <p className="mt-1 text-[var(--text)]">
                {usage?.all_time ? formatBytes(usage.all_time.total) : '—'}
              </p>
              <p className="text-[11px] text-[var(--subtle)]">
                {usage?.source === 'vnstat-wan'
                  ? 'WAN since monitoring began'
                  : 'since monitoring began'}
              </p>
            </div>
            <div>
              <p className="text-[11px] uppercase tracking-wide text-[var(--subtle)]">
                DNS filtering
              </p>
              <p className="mt-1 flex items-center gap-1.5 text-[var(--text)]">
                <Ban size={14} />
                {dnsActive ? 'AdGuard active' : 'AdGuard off'}
              </p>
            </div>
          </div>
        </div>
      </section>

      <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Stat label="Devices online" value={`${onlineDevices}/${devices.length}`} />
        <Stat
          label="Blocked"
          value={devices.filter((device) => device.blocked).length}
        />
        <Stat label="Flows (24h)" value={flows?.flows?.flow_count ?? 0} />
        <Stat
          label="DNS filtering"
          value={dnsActive ? 'enabled' : 'disabled'}
          hint={
            filtering?.version
              ? `AdGuard Home ${filtering.version}`
              : 'AdGuard Home status unavailable'
          }
        />
      </section>

      <Card
        title="Traffic activity"
        subtitle="Flows per 5 minutes · last 24 hours"
        actions={
          <Badge tone="sky">
            <span className="flex items-center gap-1">
              <Activity size={11} /> live collector
            </span>
          </Badge>
        }
      >
        {series.length > 0 ? (
          <TrafficChart data={series} />
        ) : (
          <Empty>
            No flow data yet. Netify is connected when the Traffic page shows
            data.
          </Empty>
        )}
      </Card>

      <Card
        title="Devices"
        subtitle={`${devices.length} known · ${onlineDevices} online`}
        actions={
          <Button onClick={() => void syncAll()} disabled={busy !== null}>
            {busy === 'sync' ? 'Syncing…' : 'Sync routers'}
          </Button>
        }
      >
        <div className="grid gap-3 p-4 sm:grid-cols-2 xl:grid-cols-3">
          {devices.slice(0, 6).map((device) => (
            <DeviceCard
              key={device.id}
              device={device}
              onAction={handleAction}
              onOpen={onOpenDevice}
            />
          ))}
          {devices.length === 0 && <Empty>No devices imported yet.</Empty>}
        </div>
      </Card>

      <div className="grid gap-6 xl:grid-cols-2">
        <Card title="Top applications" subtitle="Last 24 hours">
          <div className="space-y-3 p-4">
            {topApps.slice(0, 6).map((app) => (
              <div key={app.name}>
                <div className="flex items-center justify-between gap-3 text-sm">
                  <span className="truncate text-[var(--text)]">{app.name}</span>
                  <span className="text-xs text-[var(--subtle)]">{app.count}</span>
                </div>
                <div className="mt-1 h-1.5 rounded-full bg-[var(--surface-2)]">
                  <div
                    className="h-1.5 rounded-full bg-[var(--accent)]"
                    style={{
                      width: `${Math.max(4, (app.count / maxApp) * 100)}%`,
                    }}
                  />
                </div>
              </div>
            ))}
            {topApps.length === 0 && <Empty>No application data yet.</Empty>}
          </div>
        </Card>

        <Card
          title="Recent alerts"
          subtitle="Device, policy and security events"
          actions={
            <Badge tone={events.length > 0 ? 'amber' : 'slate'}>
              <span className="flex items-center gap-1">
                <Bell size={11} /> {events.length}
              </span>
            </Badge>
          }
        >
          <div className="divide-y divide-[var(--border)]">
            {events.map((event) => (
              <div key={event.id} className="px-4 py-3">
                <div className="flex items-center gap-2">
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
                  <span className="text-xs text-[var(--subtle)]">
                    {formatTime(event.created_at)}
                  </span>
                </div>
                <p className="mt-1 text-sm text-[var(--text)]">{event.message}</p>
              </div>
            ))}
            {events.length === 0 && <Empty>No events yet.</Empty>}
          </div>
        </Card>
      </div>
    </div>
  )
}
