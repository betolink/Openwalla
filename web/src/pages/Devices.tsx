import { useCallback, useEffect, useMemo, useState } from 'react'
import { api, type Device, type Router } from '../api'
import { DeviceTable } from '../components/DeviceTable'
import { Button, Card, Input, PageHeader } from '../components/ui'

export function Devices({
  onOpenDevice,
}: {
  onOpenDevice?: (device: Device) => void
}) {
  const [devices, setDevices] = useState<Device[]>([])
  const [routers, setRouters] = useState<Router[]>([])
  const [query, setQuery] = useState('')
  const [onlineOnly, setOnlineOnly] = useState(false)
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
        subtitle={`${devices.length} imported · ${filtered.length} shown · click a device for details`}
        actions={
          <Button onClick={() => void syncAll()} disabled={busy !== null}>
            {busy === 'sync-all' ? 'Syncing…' : 'Sync routers'}
          </Button>
        }
      />

      {error && (
        <div className="rounded-xl border border-[var(--danger)] bg-[var(--danger-soft)] px-4 py-3 text-sm text-[var(--danger)]">
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
        <label className="flex items-center gap-2 text-sm text-[var(--muted)]">
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

      <Card title="Inventory">
        <DeviceTable
          devices={filtered}
          onAction={handleAction}
          onSelect={onOpenDevice}
        />
      </Card>
    </div>
  )
}
