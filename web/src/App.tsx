import { useState } from 'react'
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
  ['overview', 'Overview'],
  ['devices', 'Devices'],
  ['traffic', 'Traffic'],
  ['policies', 'Policies'],
  ['parental', 'Parental'],
  ['adblock', 'Adblock'],
  ['events', 'Events'],
  ['setup', 'Router setup'],
] as const

type Tab = (typeof tabs)[number][0]

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
  const Page = pages[tab]

  return (
    <div className="min-h-screen bg-[#0b0f17] text-slate-200">
      <header className="border-b border-slate-800 bg-[#0e1420]">
        <div className="mx-auto flex max-w-7xl items-center justify-between px-6 py-4">
          <div>
            <h1 className="text-xl font-semibold text-white">OpenWalla</h1>
            <p className="text-xs text-slate-500">
              Router control plane · local test instance
            </p>
          </div>
          <Button onClick={() => setRefreshKey((value) => value + 1)}>
            Refresh
          </Button>
        </div>
      </header>

      <nav className="border-b border-slate-800 bg-[#0e1420]">
        <div className="mx-auto flex max-w-7xl gap-1 overflow-x-auto px-6">
          {tabs.map(([id, label]) => (
            <button
              key={id}
              onClick={() => setTab(id)}
              className={`whitespace-nowrap border-b-2 px-4 py-3 text-sm ${
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

      <main className="mx-auto max-w-7xl px-6 py-8">
        <Page key={`${tab}-${refreshKey}`} />
      </main>
    </div>
  )
}
