import { useCallback, useEffect, useState } from 'react'
import { api, type Device, type Router, type RouterInput } from './api'

type Tab = 'overview' | 'devices' | 'setup'

const emptyForm: RouterInput = {
  name: 'betowrt',
  address: '192.168.0.1',
  port: 80,
  scheme: 'http',
  username: 'root',
  password: '',
  verify_tls: true,
}

function StatusDot({ status }: { status: string }) {
  const color =
    status === 'online'
      ? 'bg-emerald-400'
      : status === 'degraded'
        ? 'bg-amber-400'
        : status === 'offline'
          ? 'bg-rose-400'
          : 'bg-slate-500'
  return <span className={`inline-block h-2.5 w-2.5 rounded-full ${color}`} />
}

function Badge({
  children,
  tone = 'slate',
}: {
  children: React.ReactNode
  tone?: 'slate' | 'emerald' | 'amber' | 'rose' | 'sky'
}) {
  const tones: Record<string, string> = {
    slate: 'bg-slate-800 text-slate-300',
    emerald: 'bg-emerald-950 text-emerald-300',
    amber: 'bg-amber-950 text-amber-300',
    rose: 'bg-rose-950 text-rose-300',
    sky: 'bg-sky-950 text-sky-300',
  }
  return (
    <span className={`rounded-full px-2 py-0.5 text-xs ${tones[tone]}`}>
      {children}
    </span>
  )
}

export default function App() {
  const [tab, setTab] = useState<Tab>('overview')
  const [routers, setRouters] = useState<Router[]>([])
  const [devices, setDevices] = useState<Device[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState<string | null>(null)
  const [form, setForm] = useState<RouterInput>(emptyForm)

  const refresh = useCallback(async () => {
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
      setError(caught instanceof Error ? caught.message : 'Unable to load data')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void refresh()
  }, [refresh])

  const run = async (key: string, action: () => Promise<unknown>) => {
    setBusy(key)
    setError(null)
    try {
      await action()
      await refresh()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Action failed')
    } finally {
      setBusy(null)
    }
  }

  const onlineRouters = routers.filter((router) => router.status === 'online').length
  const onlineDevices = devices.filter((device) => device.online).length

  const deviceActions = (device: Device) => (
    <div className="flex flex-wrap gap-1.5">
      <button
        className="rounded-md bg-slate-800 px-2 py-1 text-xs hover:bg-slate-700 disabled:opacity-40"
        disabled={busy !== null}
        onClick={() =>
          void run(`block-${device.id}`, () =>
            device.blocked ? api.unblockDevice(device.id) : api.blockDevice(device.id),
          )
        }
      >
        {device.blocked ? 'Unblock' : 'Block'}
      </button>
      <button
        className="rounded-md bg-slate-800 px-2 py-1 text-xs hover:bg-slate-700 disabled:opacity-40"
        disabled={busy !== null}
        onClick={() =>
          void run(`pause-${device.id}`, () =>
            device.paused ? api.resumeDevice(device.id) : api.pauseDevice(device.id),
          )
        }
      >
        {device.paused ? 'Resume' : 'Pause'}
      </button>
    </div>
  )

  const deviceTable = (items: Device[]) => (
    <div className="overflow-x-auto">
      <table className="min-w-full text-left text-sm">
        <thead className="text-xs uppercase tracking-wide text-slate-500">
          <tr>
            <th className="px-3 py-2">Device</th>
            <th className="px-3 py-2">IP</th>
            <th className="px-3 py-2">MAC</th>
            <th className="px-3 py-2">Type</th>
            <th className="px-3 py-2">State</th>
            <th className="px-3 py-2">Actions</th>
          </tr>
        </thead>
        <tbody>
          {items.map((device) => (
            <tr key={device.id} className="border-t border-slate-800">
              <td className="px-3 py-2 font-medium text-slate-100">
                {device.hostname || 'unknown'}
              </td>
              <td className="px-3 py-2 text-slate-400">{device.ipv4 || '—'}</td>
              <td className="px-3 py-2 font-mono text-xs text-slate-500">
                {device.mac}
              </td>
              <td className="px-3 py-2 text-slate-400">
                {device.device_type || device.connection || '—'}
              </td>
              <td className="px-3 py-2">
                <div className="flex flex-wrap gap-1">
                  <Badge tone={device.online ? 'emerald' : 'slate'}>
                    {device.online ? 'online' : 'offline'}
                  </Badge>
                  {device.blocked && <Badge tone="rose">blocked</Badge>}
                  {device.paused && <Badge tone="amber">paused</Badge>}
                </div>
              </td>
              <td className="px-3 py-2">{deviceActions(device)}</td>
            </tr>
          ))}
          {items.length === 0 && (
            <tr>
              <td className="px-3 py-6 text-center text-slate-500" colSpan={6}>
                No devices yet — add a router and sync.
              </td>
            </tr>
          )}
        </tbody>
      </table>
    </div>
  )

  return (
    <div className="min-h-screen bg-[#0b0f17] text-slate-200">
      <header className="border-b border-slate-800 bg-[#0e1420]">
        <div className="mx-auto flex max-w-6xl items-center justify-between px-6 py-4">
          <div>
            <h1 className="text-xl font-semibold text-white">OpenWalla</h1>
            <p className="text-xs text-slate-500">
              Router control plane · local test instance
            </p>
          </div>
          <button
            className="rounded-lg bg-sky-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-sky-500 disabled:opacity-40"
            disabled={loading}
            onClick={() => void refresh()}
          >
            {loading ? 'Refreshing…' : 'Refresh'}
          </button>
        </div>
      </header>

      <nav className="border-b border-slate-800 bg-[#0e1420]">
        <div className="mx-auto flex max-w-6xl gap-1 px-6">
          {(
            [
              ['overview', 'Overview'],
              ['devices', 'Devices'],
              ['setup', 'Router setup'],
            ] as const
          ).map(([id, label]) => (
            <button
              key={id}
              onClick={() => setTab(id)}
              className={`border-b-2 px-4 py-3 text-sm ${
                tab === id
                  ? 'border-sky-400 text-white'
                  : 'border-transparent text-slate-400 hover:text-slate-200'
              }`}
            >
              {label}
            </button>
          ))}
        </div>
      </nav>

      <main className="mx-auto max-w-6xl space-y-6 px-6 py-8">
        {error && (
          <div className="rounded-lg border border-rose-900 bg-rose-950/50 px-4 py-3 text-sm text-rose-200">
            {error}
          </div>
        )}

        {tab === 'overview' && (
          <>
            <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
              {[
                ['Routers online', `${onlineRouters}/${routers.length}`],
                ['Devices online', `${onlineDevices}/${devices.length}`],
                ['Blocked', String(devices.filter((d) => d.blocked).length)],
                ['Paused', String(devices.filter((d) => d.paused).length)],
              ].map(([label, value]) => (
                <div
                  key={label}
                  className="rounded-xl border border-slate-800 bg-[#0e1420] p-4"
                >
                  <p className="text-xs uppercase tracking-wide text-slate-500">
                    {label}
                  </p>
                  <p className="mt-1 text-2xl font-semibold text-white">{value}</p>
                </div>
              ))}
            </section>

            <section className="rounded-xl border border-slate-800 bg-[#0e1420]">
              <div className="border-b border-slate-800 px-4 py-3">
                <h2 className="text-sm font-semibold text-white">Routers</h2>
              </div>
              <div className="divide-y divide-slate-800">
                {routers.map((router) => (
                  <div
                    key={router.id}
                    className="flex flex-wrap items-center justify-between gap-3 px-4 py-3"
                  >
                    <div>
                      <div className="flex items-center gap-2">
                        <StatusDot status={router.status} />
                        <span className="font-medium text-white">{router.name}</span>
                        <Badge tone={router.status === 'online' ? 'emerald' : 'slate'}>
                          {router.status}
                        </Badge>
                      </div>
                      <p className="mt-1 text-xs text-slate-500">
                        {router.address} · {router.model || 'model unknown'} ·{' '}
                        {router.openwrt_version || 'version unknown'}
                      </p>
                    </div>
                    <button
                      className="rounded-md bg-slate-800 px-3 py-1.5 text-xs hover:bg-slate-700 disabled:opacity-40"
                      disabled={busy !== null}
                      onClick={() =>
                        void run(`sync-${router.id}`, () => api.syncRouter(router.id))
                      }
                    >
                      Sync
                    </button>
                  </div>
                ))}
                {routers.length === 0 && (
                  <p className="px-4 py-6 text-sm text-slate-500">
                    No routers yet. Use “Router setup”.
                  </p>
                )}
              </div>
            </section>

            <section className="rounded-xl border border-slate-800 bg-[#0e1420]">
              <div className="border-b border-slate-800 px-4 py-3">
                <h2 className="text-sm font-semibold text-white">
                  Recent devices
                </h2>
              </div>
              {deviceTable(devices.slice(0, 8))}
            </section>
          </>
        )}

        {tab === 'devices' && (
          <section className="rounded-xl border border-slate-800 bg-[#0e1420]">
            <div className="border-b border-slate-800 px-4 py-3">
              <h2 className="text-sm font-semibold text-white">All devices</h2>
            </div>
            {deviceTable(devices)}
          </section>
        )}

        {tab === 'setup' && (
          <section className="mx-auto max-w-2xl rounded-xl border border-slate-800 bg-[#0e1420] p-6">
            <h2 className="text-lg font-semibold text-white">Connect a router</h2>
            <p className="mt-1 text-sm text-slate-500">
              Credentials are stored by the backend and used for LuCI RPC. They
              are never returned to the browser.
            </p>
            <form
              className="mt-5 grid gap-4"
              onSubmit={(event) => {
                event.preventDefault()
                void run('create-router', async () => {
                  const router = await api.createRouter({
                    ...form,
                    port: Number(form.port) || 80,
                  })
                  await api.syncRouter(router.id)
                  setForm(emptyForm)
                  setTab('overview')
                })
              }}
            >
              {(
                [
                  ['name', 'Name', 'betowrt'],
                  ['address', 'LAN address', '192.168.0.1'],
                  ['username', 'Username', 'root'],
                  ['password', 'Password', ''],
                ] as const
              ).map(([key, label, placeholder]) => (
                <label key={key} className="grid gap-1 text-sm">
                  <span className="text-slate-400">{label}</span>
                  <input
                    className="rounded-lg border border-slate-700 bg-[#0b0f17] px-3 py-2 text-slate-100 outline-none focus:border-sky-500"
                    type={key === 'password' ? 'password' : 'text'}
                    value={String(form[key] ?? '')}
                    placeholder={placeholder}
                    onChange={(event) =>
                      setForm((current) => ({
                        ...current,
                        [key]: event.target.value,
                      }))
                    }
                    required={key !== 'password'}
                  />
                </label>
              ))}
              <button
                className="mt-2 rounded-lg bg-sky-600 px-4 py-2 text-sm font-medium text-white hover:bg-sky-500 disabled:opacity-40"
                disabled={busy !== null}
                type="submit"
              >
                {busy === 'create-router' ? 'Connecting…' : 'Save and sync'}
              </button>
            </form>
          </section>
        )}
      </main>
    </div>
  )
}
