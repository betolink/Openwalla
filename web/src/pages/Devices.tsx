import { useCallback, useEffect, useMemo, useState } from 'react'
import { api, type Device, type Router } from '../api'
import { DeviceTable } from '../components/DeviceTable'
import { Badge, Button, Card, Empty, Input, PageHeader } from '../components/ui'

function formatTime(value?: string) {
  if (!value) return '—'
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? value : date.toLocaleString()
}

export function Devices() {
  const [devices, setDevices] = useState<Device[]>([])
  const [routers, setRouters] = useState<Router[]>([])
  const [query, setQuery] = useState('')
  const [onlineOnly, setOnlineOnly] = useState(false)
  const [selected, setSelected] = useState<Device | null>(null)
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
      setSelected((current) =>
        current
          ? (deviceList.items.find((item) => item.id === current.id) ?? null)
          : null,
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

  const filtered = useMemo(() => {
    const needle = query.trim().toLowerCase()
    return devices.filter((device) => {
      if (onlineOnly && !device.online) return false
      if (!needle) return true
      return [device.hostname, device.ipv4, device.mac, device.vendor, device.device_type]
        .filter(Boolean)
        .some((value) => String(value).toLowerCase().includes(needle))
    })
  }, [devices, onlineOnly, query])

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
    setBusy('sync-all')
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

  return (
    <div className="space-y-6">
      <PageHeader
        title="Devices"
        subtitle={`${devices.length} imported · ${filtered.length} shown`}
        actions={
          <Button onClick={() => void syncAll()} disabled={busy !== null}>
            {busy === 'sync-all' ? 'Syncing…' : 'Sync routers'}
          </Button>
        }
      />

      {error && (
        <div className="rounded-lg border border-rose-900 bg-rose-950/50 px-4 py-3 text-sm text-rose-200">
          {error}
        </div>
      )}

      <div className="flex flex-wrap items-center gap-3">
        <Input
          className="w-72"
          placeholder="Search hostname, IP, MAC or vendor"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
        />
        <label className="flex items-center gap-2 text-sm text-slate-400">
          <input
            type="checkbox"
            checked={onlineOnly}
            onChange={(event) => setOnlineOnly(event.target.checked)}
          />
          Online only
        </label>
        <Button onClick={() => void load()} disabled={loading}>
          Refresh
        </Button>
      </div>

      <div className="grid gap-6 xl:grid-cols-[2fr_1fr]">
        <Card title="Inventory">
          <DeviceTable
            devices={filtered}
            onAction={handleAction}
            onSelect={setSelected}
            selectedId={selected?.id}
          />
        </Card>

        <Card title="Device details">
          {selected ? (
            <div className="space-y-4 p-4 text-sm">
              <div>
                <div className="flex flex-wrap items-center gap-2">
                  <span className="text-base font-semibold text-white">
                    {selected.hostname || selected.mac}
                  </span>
                  <Badge tone={selected.online ? 'emerald' : 'slate'}>
                    {selected.online ? 'online' : 'offline'}
                  </Badge>
                  {selected.blocked && <Badge tone="rose">blocked</Badge>}
                  {selected.paused && <Badge tone="amber">paused</Badge>}
                </div>
                <p className="mt-1 text-xs text-slate-500">
                  {selected.device_type || 'unknown type'} ·{' '}
                  {selected.connection}
                </p>
              </div>

              <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-2 text-xs">
                <dt className="text-slate-500">IPv4</dt>
                <dd className="text-slate-300">{selected.ipv4 || '—'}</dd>
                <dt className="text-slate-500">IPv6</dt>
                <dd className="break-all text-slate-300">
                  {selected.ipv6?.join(', ') || '—'}
                </dd>
                <dt className="text-slate-500">MAC</dt>
                <dd className="font-mono text-slate-300">{selected.mac}</dd>
                <dt className="text-slate-500">Vendor</dt>
                <dd className="text-slate-300">{selected.vendor || '—'}</dd>
                <dt className="text-slate-500">First seen</dt>
                <dd className="text-slate-300">{formatTime(selected.first_seen)}</dd>
                <dt className="text-slate-500">Last seen</dt>
                <dd className="text-slate-300">{formatTime(selected.last_seen)}</dd>
                <dt className="text-slate-500">Tags</dt>
                <dd className="text-slate-300">{selected.tags?.join(', ') || '—'}</dd>
              </dl>

              <div className="flex gap-2">
                <Button onClick={() => void handleAction(selected, 'block')}>
                  {selected.blocked ? 'Unblock' : 'Block'}
                </Button>
                <Button onClick={() => void handleAction(selected, 'pause')}>
                  {selected.paused ? 'Resume' : 'Pause'}
                </Button>
              </div>
            </div>
          ) : (
            <Empty>Select a device to see details and actions.</Empty>
          )}
        </Card>
      </div>
    </div>
  )
}
