import { useState, type FormEvent } from 'react'
import { Shield } from 'lucide-react'
import { api, ApiError, type User } from '../api'
import { Button, Input } from '../components/ui'

export function Login({ onSuccess }: { onSuccess: (user: User) => void }) {
  const [username, setUsername] = useState('admin')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const submit = async (event: FormEvent) => {
    event.preventDefault()
    setBusy(true)
    setError(null)
    try {
      const result = await api.login(username.trim(), password)
      onSuccess(result.user)
    } catch (caught) {
      if (caught instanceof ApiError && caught.status === 401) {
        setError('Invalid username or password.')
      } else {
        setError(caught instanceof Error ? caught.message : 'Login failed')
      }
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-[var(--bg)] px-5 text-[var(--text)]">
      <div className="w-full max-w-sm rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-6 shadow-xl">
        <div className="mb-6 flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-[var(--accent-soft)] text-[var(--accent-text)]">
            <Shield size={20} />
          </div>
          <div>
            <h1 className="text-lg font-semibold text-[var(--text-strong)]">
              OpenWalla
            </h1>
            <p className="text-[11px] text-[var(--subtle)]">
              Sign in to the network dashboard
            </p>
          </div>
        </div>

        <form className="space-y-3" onSubmit={(event) => void submit(event)}>
          <label className="block text-xs text-[var(--subtle)]">
            Username
            <Input
              className="mt-1 w-full"
              autoComplete="username"
              value={username}
              onChange={(event) => setUsername(event.target.value)}
            />
          </label>
          <label className="block text-xs text-[var(--subtle)]">
            Password
            <Input
              className="mt-1 w-full"
              type="password"
              autoComplete="current-password"
              autoFocus
              value={password}
              onChange={(event) => setPassword(event.target.value)}
            />
          </label>

          {error && (
            <div className="rounded-lg border border-[var(--danger)] bg-[var(--danger-soft)] px-3 py-2 text-xs text-[var(--danger)]">
              {error}
            </div>
          )}

          <Button
            type="submit"
            variant="primary"
            disabled={busy || !username || !password}
          >
            {busy ? 'Signing in…' : 'Sign in'}
          </Button>
        </form>

        <p className="mt-4 text-[11px] leading-relaxed text-[var(--subtle)]">
          Use the OpenWalla GUI password (<span className="font-mono">vault_openwalla_gui_password</span>).
          This is separate from the betowrt/router password used in Router setup.
        </p>
      </div>
    </div>
  )
}
