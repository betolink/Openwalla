import { useCallback, useEffect, useState } from 'react'
import {
  api,
  type AdblockStatus,
  type Device,
  type EventItem,
  type Router,
} from '../api'
import { DeviceTable } from '../components/DeviceTable'
import { Badge, Button, Card, Empty, PageHeader, Stat } from '../components/ui'

function formatTime(value?: string) {
  if (!value) return '—'
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? value : date.toLocaleString()
}

export function Overview() {
  const [routers, setRouters] = useState<Router[]>([])
  const [devices, setDevices] = useState<Device[]>([])
  const [adblock, setAdblock] = useState<AdblockStatus | null>(null)
  const [events, setEvents] = useState<EventItem[]>([])
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
      const [adblockResult, eventResult] = await Promise.allSettled([
        api.getAdblockStatus(),
        api.listEvents({ limit: 5 }),
      ])
      setAdblock(adblockResult.status === 'fulfilled' ? adblockResult.value : null)
      setEvents(
        eventResult.status === 'fulfilled' ? (eventResult.value.items ?? []) : [],
      )
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to load')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load])

  const sync = async (routerId: string) => {
    setBusy(routerId)
    setError(null)
    try {
      await api.syncRouter(routerId)
      await load()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Sync failed')
    } finally {
      setBusy(null)
    }
  }

  const onlineRouters = routers.filter((router) => router.status === 'online').length
  const onlineDevices = devices.filter((device) => device.online).length

  return (
    <div className="space-y-6">
      <PageHeader
        title="Overview"
        subtitle={`${routers.length} router(s) · ${devices.length} device(s) imported`}
        actions={
          <Button onClick={() => void load()} disabled={loading}>
            {loading ? 'Refreshing…' : 'Refresh'}
          </Button>
        }
      />

      {error && (
        <div className="rounded-lg border border-rose-900 bg-rose-950/50 px-4 py-3 text-sm text-rose-200">
          {error}
        </div>
      )}

      <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Stat label="Routers online" value={`${onlineRouters}/${routers.length}`} />
        <Stat label="Devices online" value={`${onlineDevices}/${devices.length}`} />
        <Stat
          label="Blocked devices"
          value={devices.filter((device) => device.blocked).length}
        />
        <Stat
          label="Adblock"
          value={adblock ? `${adblock.block_percent ?? 0}%` : '—'}
          hint={adblock?.enabled ? 'enabled' : 'disabled'}
        />
      </section>

      <Card title="Routers">
        <div className="divide-y divide-slate-800">
          {routers.map((router) => (
            <div
              key={router.id}
              className="flex flex-wrap items-center justify-between gap-3 px-4 py-3"
            >
              <div>
                <div className="flex items-center gap-2">
                  <Badge tone={router.status === 'online' ? 'emerald' : 'slate'}>
                    {router.status}
                  </Badge>
                  <span className="font-medium text-white">{router.name}</span>
                </div>
                <p className="mt-1 text-xs text-slate-500">
                  {router.address} · {router.model || 'model unknown'} ·{' '}
                  {router.openwrt_version || 'version unknown'} · synced{' '}
                  {formatTime(router.last_seen)}
                </p>
              </div>
              <Button
                onClick={() => void sync(router.id)}
                disabled={busy !== null}
              >
                {busy === router.id ? 'Syncing…' : 'Sync'}
              </Button>
            </div>
          ))}
          {routers.length === 0 && <Empty>No routers yet — use Router setup.</Empty>}
        </div>
      </Card>

      <div className="grid gap-6 lg:grid-cols-[2fr_1fr]">
        <Card title="Recent devices">
          <DeviceTable devices={devices.slice(0, 8)} />
        </Card>
        <Card title="Recent events">
          <div className="divide-y divide-slate-800">
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
                  <span className="text-xs text-slate-500">
                    {formatTime(event.created_at)}
                  </span>
                </div>
                <p className="mt-1 text-sm text-slate-300">{event.message}</p>
              </div>
            ))}
            {events.length === 0 && <Empty>No events yet.</Empty>}
          </div>
        </Card>
      </div>
    </div>
  )
}
