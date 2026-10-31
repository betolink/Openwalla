import { useEffect, useMemo, useState } from 'react'
import {
  Activity,
  Ban,
  Bell,
  LayoutDashboard,
  MonitorSmartphone,
  Moon,
  RefreshCw,
  Settings,
  Shield,
  Sun,
  Users,
  Wifi,
} from 'lucide-react'
import type { ComponentType } from 'react'
import { Button } from './components/ui'
import { Adblock } from './pages/Adblock'
import { Devices } from './pages/Devices'
import { Events } from './pages/Events'
import { Overview } from './pages/Overview'
import { Parental } from './pages/Parental'
import { Policies } from './pages/Policies'
import { Setup } from './pages/Setup'
import { Traffic } from './pages/Traffic'

const tabs = [
  { id: 'overview', label: 'Overview', icon: LayoutDashboard },
  { id: 'devices', label: 'Devices', icon: MonitorSmartphone },
  { id: 'traffic', label: 'Traffic', icon: Activity },
  { id: 'policies', label: 'Policies', icon: Shield },
  { id: 'parental', label: 'Parental', icon: Users },
  { id: 'adblock', label: 'Adblock', icon: Ban },
  { id: 'events', label: 'Events', icon: Bell },
  { id: 'setup', label: 'Router setup', icon: Settings },
] as const

type Tab = (typeof tabs)[number]['id']
type Theme = 'dark' | 'light'

const pages: Record<Tab, ComponentType> = {
  overview: Overview,
  devices: Devices,
  traffic: Traffic,
  policies: Policies,
  parental: Parental,
  adblock: Adblock,
  events: Events,
  setup: Setup,
}

export default function App() {
  const [tab, setTab] = useState<Tab>('overview')
  const [refreshKey, setRefreshKey] = useState(0)
  const [theme, setTheme] = useState<Theme>(() => {
    if (typeof window === 'undefined') return 'dark'
    return window.localStorage.getItem('openwalla-theme') === 'light'
      ? 'light'
      : 'dark'
  })
  const Page = pages[tab]
  const current = useMemo(
    () => tabs.find((item) => item.id === tab) ?? tabs[0],
    [tab],
  )

  useEffect(() => {
    document.title = `${current.label} · OpenWalla`
  }, [current])

  useEffect(() => {
    document.documentElement.dataset.theme = theme
    try {
      window.localStorage.setItem('openwalla-theme', theme)
    } catch {
      // private mode / storage disabled
    }
  }, [theme])

  const refresh = () => setRefreshKey((value) => value + 1)
  const toggleTheme = () =>
    setTheme((value) => (value === 'dark' ? 'light' : 'dark'))

  return (
    <div className="min-h-screen bg-[var(--bg)] text-[var(--text)]">
      <aside className="fixed inset-y-0 left-0 hidden w-60 flex-col border-r border-[var(--border)] bg-[var(--surface)] md:flex">
        <div className="flex items-center gap-3 px-5 py-5">
          <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-[var(--accent-soft)] text-[var(--accent-text)]">
            <Shield size={18} />
          </div>
          <div>
            <p className="text-base font-semibold text-[var(--text-strong)]">OpenWalla</p>
            <p className="text-[11px] text-[var(--subtle)]">Network security</p>
          </div>
        </div>

        <nav className="flex-1 space-y-1 px-3">
          {tabs.map((item) => {
            const Icon = item.icon
            const active = tab === item.id
            return (
              <button
                key={item.id}
                onClick={() => setTab(item.id)}
                className={`flex w-full items-center gap-3 rounded-lg px-3 py-2 text-sm transition ${
                  active
                    ? 'bg-[var(--accent-soft)] text-[var(--accent-text)]'
                    : 'text-[var(--muted)] hover:bg-[var(--surface-3)] hover:text-[var(--text)]'
                }`}
              >
                <Icon size={16} />
                {item.label}
              </button>
            )
          })}
        </nav>

        <div className="border-t border-[var(--border)] px-5 py-4 text-[11px] text-[var(--subtle)]">
          <p className="flex items-center gap-1.5">
            <Wifi size={12} /> betowrt · 192.168.0.1
          </p>
          <p className="mt-1">OpenWalla 0.1 · local</p>
        </div>
      </aside>

      <div className="md:pl-60">
        <header className="sticky top-0 z-10 flex items-center justify-between gap-3 border-b border-[var(--border)] bg-[var(--bg)] px-5 py-3 backdrop-blur">
          <div>
            <p className="text-sm font-medium text-[var(--text)]">{current.label}</p>
            <p className="text-[11px] text-[var(--subtle)]">
              Router control plane · local test instance
            </p>
          </div>
          <div className="flex items-center gap-2">
            <button
              type="button"
              aria-label={`Switch to ${theme === 'dark' ? 'light' : 'dark'} theme`}
              title={`Switch to ${theme === 'dark' ? 'light' : 'dark'} theme`}
              onClick={toggleTheme}
              className="rounded-md bg-[var(--surface-2)] p-1.5 text-[var(--muted)] hover:bg-[var(--surface-3)]"
            >
              {theme === 'dark' ? <Sun size={14} /> : <Moon size={14} />}
            </button>
            <Button onClick={refresh}>
              <span className="flex items-center gap-1.5">
                <RefreshCw size={13} /> Refresh
              </span>
            </Button>
          </div>
        </header>

        <div className="border-b border-[var(--border)] bg-[var(--surface)] md:hidden">
          <div className="flex gap-1 overflow-x-auto px-3 py-2">
            {tabs.map((item) => {
              const Icon = item.icon
              const active = tab === item.id
              return (
                <button
                  key={item.id}
                  onClick={() => setTab(item.id)}
                  className={`flex shrink-0 items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs ${
                    active
                      ? 'bg-[var(--accent-soft)] text-[var(--accent-text)]'
                      : 'text-[var(--muted)] hover:text-[var(--text)]'
                  }`}
                >
                  <Icon size={13} />
                  {item.label}
                </button>
              )
            })}
          </div>
        </div>

        <main className="mx-auto max-w-[1500px] px-5 py-6">
          <Page key={`${tab}-${refreshKey}`} />
        </main>
      </div>
    </div>
  )
}
