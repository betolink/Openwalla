import { useCallback, useEffect, useState } from 'react'
import { api, type Router, type RouterInput } from '../api'
import {
  Badge,
  Button,
  Card,
  Empty,
  Field,
  Input,
  PageHeader,
} from '../components/ui'

const blankForm: RouterInput = {
  name: 'betowrt',
  address: '192.168.0.1',
  port: 80,
  scheme: 'http',
  username: 'root',
  password: '',
  verify_tls: true,
}

export function Setup() {
  const [routers, setRouters] = useState<Router[]>([])
  const [form, setForm] = useState<RouterInput>(blankForm)
  const [busy, setBusy] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const result = await api.listRouters()
      setRouters(result.items)
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to load')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load])

  const submit = async (event: React.FormEvent) => {
    event.preventDefault()
    setBusy('create')
    setError(null)
    try {
      const router = await api.createRouter({
        ...form,
        port: Number(form.port) || 80,
      })
      await api.syncRouter(router.id)
      setForm({ ...blankForm })
      await load()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to connect')
    } finally {
      setBusy(null)
    }
  }

  const sync = async (router: Router) => {
    setBusy(`sync-${router.id}`)
    setError(null)
    try {
      await api.syncRouter(router.id)
      await load()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Sync failed')
    } finally {
      setBusy(null)
    }
  }

  const remove = async (router: Router) => {
    setBusy(`delete-${router.id}`)
    setError(null)
    try {
      await api.deleteRouter(router.id)
      await load()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Delete failed')
    } finally {
      setBusy(null)
    }
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="Router setup"
        subtitle="LuCI RPC credentials are stored by the backend and never returned."
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

      <Card title="Add a router">
        <form onSubmit={(event) => void submit(event)} className="grid gap-4 p-4">
          <div className="grid gap-4 sm:grid-cols-2">
            <Field label="Name">
              <Input
                value={form.name}
                onChange={(event) =>
                  setForm((current) => ({ ...current, name: event.target.value }))
                }
                required
              />
            </Field>
            <Field label="LAN address">
              <Input
                value={form.address}
                onChange={(event) =>
                  setForm((current) => ({
                    ...current,
                    address: event.target.value,
                  }))
                }
                required
              />
            </Field>
            <Field label="Username">
              <Input
                value={form.username}
                onChange={(event) =>
                  setForm((current) => ({
                    ...current,
                    username: event.target.value,
                  }))
                }
                required
              />
            </Field>
            <Field label="Password">
              <Input
                type="password"
                value={form.password}
                onChange={(event) =>
                  setForm((current) => ({
                    ...current,
                    password: event.target.value,
                  }))
                }
              />
            </Field>
          </div>
          <div>
            <Button type="submit" variant="primary" disabled={busy !== null}>
              {busy === 'create' ? 'Connecting…' : 'Save and sync'}
            </Button>
          </div>
        </form>
      </Card>

      <Card title="Configured routers">
        <div className="divide-y divide-[var(--border)]">
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
                  <span className="font-medium text-[var(--text-strong)]">{router.name}</span>
                </div>
                <p className="mt-1 text-xs text-[var(--subtle)]">
                  {router.address} · {router.model || 'model unknown'} ·{' '}
                  {router.openwrt_version || 'version unknown'} ·{' '}
                  {router.has_credentials ? 'credentials stored' : 'no credentials'}
                </p>
              </div>
              <div className="flex gap-2">
                <Button
                  onClick={() => void sync(router)}
                  disabled={busy !== null}
                >
                  {busy === `sync-${router.id}` ? 'Syncing…' : 'Sync'}
                </Button>
                <Button
                  variant="danger"
                  onClick={() => void remove(router)}
                  disabled={busy !== null}
                >
                  Remove
                </Button>
              </div>
            </div>
          ))}
          {routers.length === 0 && <Empty>No routers configured.</Empty>}
        </div>
      </Card>
    </div>
  )
}
